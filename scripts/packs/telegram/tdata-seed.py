#!/usr/bin/env python3
# tdata-seed.py — telegram bundle: seed a never-started Telegram Desktop data
# dir so the FIRST launch already uses W's palette (pack-telegram.md, stage 2).
#
# What it writes into <data-dir>/tdata/ (both files are tdesktop's own on-disk
# format, verified against the `dev` sources and round-tripped through the
# dev-side reader devtools/usr/local/bin/w-tdata-decode):
#
#   settingss           dbiThemeKey day=K night=K nightMode=1  (+ optionally a
#                       dbiApplicationSettings prefix that turns "Use Qt window
#                       frame" on, see APP_SETTINGS below)
#   <ToFilePart(K)>s    the theme record: content = the W theme file as it is
#                       right now, pathAbsolute/pathRelative pointing at it,
#                       cloud fields zero, cache EMPTY — tdesktop loads the
#                       palette from `content` on a cache miss and writes the
#                       cache itself (Window::Theme::InitializeFromSaved).
#
# Both are encrypted with the SettingsKey only: PBKDF2-SHA1 of an EMPTY
# passcode over a salt stored in settingss itself (tdesktop's obfuscation
# layer, no secret). The salt is freshly random per account. key_datas — the
# real local key, root of trust for the sessions — is deliberately NOT written:
# tdesktop generates it on first start (Local::start reads settings before
# Domain::start, which calls generateLocalKey when key_datas is absent).
#
# Safety: refuses to touch an initialised tdata (any settings{s,0,1} present —
# that account has a running history and keeps its one-click flow); writes the
# theme record before settingss and both via tmp+rename, so no state can point
# at a half-written file. A format mismatch on tdesktop's side is soft: it
# discards what it cannot read and writes its own defaults (stock look).
#
#   tdata-seed.py --data-dir DIR --theme FILE --version N [--no-app-settings]
#     DIR       Telegram's data dir (~/.local/share/TelegramDesktop)
#     FILE      the rendered theme (w.tdesktop-theme), absolute path
#     N         AppVersion of the installed telegram-desktop (M*1000000+m*1000+p);
#               a header newer than the running app makes it skip the file
#   exit 0 seeded · 3 tdata already initialised (nothing written) · 2 error
#
# Needs python-cryptography (declared in the bundle's pkgs.txt).
import argparse
import hashlib
import os
import struct
import sys
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

DBI_THEME_KEY = 0x54
DBI_APPLICATION_SETTINGS = 0x5E
SALT_SIZE = 32
NEW_TAG = "special://new_tag"

# The positional prefix of Core::Settings::addFromSerialized, stopped right
# after nativeWindowFrame ("Use Qt window frame"). The reader is prefix-
# tolerant (every group is guarded by `if (!stream.atEnd())`): the fields
# behind the cut take tdesktop's defaults, exactly as an old blob would.
# Values are the DEFAULTS of a fresh first start — every field but the last
# must equal what tdesktop itself writes on an untouched account, and they are
# pinned from such a capture on the VM (w-tdata-decode --app-settings; the
# recipe is in pack-telegram.md). Types: i qint32, s QString, b QByteArray;
# None = a null Qt string/array (0xFFFFFFFF on the wire), which is what a
# default-constructed member serialises to.
APP_SETTINGS = (
    ("themesAccentColors", "b", None),
    ("adaptiveForWide", "i", 1),
    ("moderateModeEnabled", "i", 0),
    ("songVolume", "i", 900000),
    ("videoVolume", "i", 900000),
    ("askDownloadPath", "i", 0),
    ("downloadPath", "s", None),
    ("downloadPathBookmark", "b", None),
    ("nonDefaultVoicePlaybackSpeed", "i", 1),
    ("soundNotify", "i", 1),
    ("desktopNotify", "i", 1),
    ("flashBounceNotify", "i", 1),
    ("notifyView", "i", 0),
    ("nativeNotifications", "i", 0),
    ("notificationsCount", "i", 3),
    ("notificationsCorner", "i", 2),
    ("autoLock", "i", 3600),
    ("legacyCallPlaybackDeviceId", "s", None),
    ("legacyCallCaptureDeviceId", "s", None),
    ("callOutputVolume", "i", 100),
    ("callInputVolume", "i", 100),
    ("callAudioDuckingEnabled", "i", 1),
    ("lastSeenWarningSeen", "i", 0),
    ("soundOverridesCount", "i", 0),
    ("sendFilesWay", "i", 0),
    ("sendSubmitWay", "i", 0),
    ("includeMutedCounter", "i", 1),
    ("countUnreadMessages", "i", 1),
    ("legacyExeLaunchWarning", "i", 1),
    ("notifyAboutPinned", "i", 1),
    ("loopAnimatedStickers", "i", 1),
    ("largeEmoji", "i", 1),
    ("replaceEmoji", "i", 1),
    ("suggestEmoji", "i", 1),
    ("suggestStickersByEmoji", "i", 1),
    ("spellcheckerEnabled", "i", 1),
    ("videoPlaybackSpeed", "i", -170),
    ("videoPipGeometry", "b", None),
    ("dictionariesEnabledCount", "i", 0),
    ("autoDownloadDictionaries", "i", 1),
    ("mainMenuAccountsShown", "i", 1),
    ("tabbedSelectorSectionEnabled", "i", 0),
    ("floatPlayerColumn", "i", 1),
    ("floatPlayerCorner", "i", 4),
    ("thirdSectionInfoEnabled", "i", 1),
    ("dialogsWithChatWidthRatioInt", "i", 357143),
    ("thirdColumnWidth", "i", 0),
    ("thirdSectionExtendedBy", "i", -1),
    ("notifyFromAll", "i", 1),
    ("nativeWindowFrame", "i", 1),       # the one non-default: Qt window frame ON
)


class Stream:
    """Minimal QDataStream (Qt_5_1, big-endian) writer."""

    def __init__(self) -> None:
        self.buf = bytearray()

    def u32(self, v: int) -> None:
        self.buf += struct.pack(">I", v)

    def i32(self, v: int) -> None:
        self.buf += struct.pack(">i", v)

    def u64(self, v: int) -> None:
        self.buf += struct.pack(">Q", v)

    def bytes(self, v) -> None:
        if v is None:
            self.u32(0xFFFFFFFF)
        else:
            self.u32(len(v))
            self.buf += v

    def string(self, v) -> None:
        self.bytes(None if v is None else v.encode("utf-16-be"))

    def data(self) -> bytes:
        return bytes(self.buf)


# ── crypto (mirror of w-tdata-decode, which mirrors tdesktop) ─────────────────
def settings_key(salt: bytes) -> bytes:
    # CreateLegacyLocalKey(passcode="", salt): PBKDF2-SHA1, 4 iterations, 256 bytes.
    return hashlib.pbkdf2_hmac("sha1", b"", salt, 4, 256)


def prepare_aes_oldmtp(key: bytes, msg_key: bytes):
    x = 8  # aesEncryptLocal → prepareAES_oldmtp(send=false)
    a = hashlib.sha1(msg_key + key[x:x + 32]).digest()
    b = hashlib.sha1(key[32 + x:48 + x] + msg_key + key[48 + x:64 + x]).digest()
    c = hashlib.sha1(key[64 + x:96 + x] + msg_key).digest()
    d = hashlib.sha1(msg_key + key[96 + x:128 + x]).digest()
    return (a[0:8] + b[8:20] + c[4:16], a[8:20] + b[0:8] + c[16:20] + d[0:8])


def ige_encrypt(data: bytes, key: bytes, iv: bytes) -> bytes:
    # IGE: c[i] = E(m[i] ^ c[i-1]) ^ m[i-1], with c[0] = iv[:16], m[0] = iv[16:].
    ecb = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    c_prev, m_prev = iv[:16], iv[16:]
    out = bytearray()
    for i in range(0, len(data), 16):
        m = data[i:i + 16]
        c = bytes(p ^ q for p, q in zip(ecb.update(bytes(p ^ q for p, q in zip(m, c_prev))), m_prev))
        out += c
        c_prev, m_prev = c, m
    return bytes(out)


def encrypt_local(body: bytes, key: bytes) -> bytes:
    # PrepareEncrypted: plain = uint32 LE (4 + len) + body, random-padded to 16;
    # msg_key = sha1(plain)[:16]; out = msg_key + AES-IGE(plain).
    size = 4 + len(body)
    plain = struct.pack("<I", size) + body
    if size & 0x0F:
        plain += os.urandom(0x10 - (size & 0x0F))
    msg_key = hashlib.sha1(plain).digest()[:16]
    aes_key, aes_iv = prepare_aes_oldmtp(key, msg_key)
    return msg_key + ige_encrypt(plain, aes_key, aes_iv)


# ── TDF$ container ────────────────────────────────────────────────────────────
def tdf(version: int, *parts: bytes) -> bytes:
    # FileWriteDescriptor: each part as a QByteArray; md5 over the serialised
    # parts, then int32 LE full size, int32 LE version, magic.
    s = Stream()
    for part in parts:
        s.bytes(part)
    payload = s.data()
    digest = hashlib.md5(
        payload + struct.pack("<i", len(payload)) + struct.pack("<i", version) + b"TDF$"
    ).digest()
    return b"TDF$" + struct.pack("<i", version) + payload + digest


def file_part(key: int) -> str:
    # ToFilePart(): 16 hex digits, least significant nibble first.
    return "".join(f"{(key >> (4 * i)) & 0xF:X}" for i in range(16))


def generate_key(tdata: Path) -> int:
    # GenerateKey(): random non-zero, not colliding with <name>{0,1,s}.
    while True:
        key = int.from_bytes(os.urandom(8), "little")
        name = file_part(key)
        if key and not any((tdata / (name + suffix)).exists() for suffix in "01s"):
            return key


# ── records ───────────────────────────────────────────────────────────────────
def app_settings_blob() -> bytes:
    s = Stream()
    write = {"i": s.i32, "s": s.string, "b": s.bytes}
    for _name, kind, value in APP_SETTINGS:
        write[kind](value)
    return s.data()


def settings_body(key: int, app_settings: bool) -> bytes:
    s = Stream()
    s.u32(DBI_THEME_KEY)
    s.u64(key)      # day slot
    s.u64(key)      # night slot — the same record, so either mode is W
    s.u32(1)        # nightMode
    if app_settings:
        s.u32(DBI_APPLICATION_SETTINGS)
        s.bytes(app_settings_blob())
    return s.data()


def theme_body(content: bytes, path_absolute: str, path_relative: str) -> bytes:
    # writeTheme(): object, cloud zeros, empty cache, empty chatTheme.
    s = Stream()
    s.bytes(content)
    s.string(NEW_TAG)
    s.string(path_absolute)
    s.string(path_relative)
    s.u64(0)        # cloud.id
    s.u64(0)        # cloud.accessHash
    s.string(None)  # cloud.slug
    s.string(None)  # cloud.title
    s.u64(0)        # cloud.documentId
    s.i32(0)        # field1 (createdBy low bits)
    s.i32(0)        # cache.paletteChecksum
    s.i32(0)        # cache.contentChecksum
    s.bytes(None)   # cache.colors
    s.bytes(None)   # cache.background
    s.u32(0)        # field2 (tiled | createdBy high bits)
    s.bytes(None)   # chatTheme
    return s.data()


def write_atomic(path: Path, data: bytes) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".w-seed-")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data-dir", required=True, type=Path)
    ap.add_argument("--theme", required=True, type=Path)
    ap.add_argument("--version", required=True, type=int)
    ap.add_argument("--no-app-settings", action="store_true",
                    help="skip the dbiApplicationSettings prefix (Qt window frame stays off)")
    args = ap.parse_args()

    tdata = args.data_dir / "tdata"
    if any((tdata / f"settings{suffix}").exists() for suffix in "s01"):
        print("tdata-seed: tdata already initialised — leaving it alone.")
        return 3
    if not args.theme.is_absolute():
        print("tdata-seed: --theme must be absolute (it becomes pathAbsolute).", file=sys.stderr)
        return 2
    if args.version <= 0:
        print("tdata-seed: --version must be a positive AppVersion.", file=sys.stderr)
        return 2
    try:
        content = args.theme.read_bytes()
    except OSError as e:
        print(f"tdata-seed: cannot read theme: {e}", file=sys.stderr)
        return 2
    if len(content) < 4:
        print("tdata-seed: theme file is empty — refusing to seed.", file=sys.stderr)
        return 2

    tdata.mkdir(parents=True, exist_ok=True)
    salt = os.urandom(SALT_SIZE)
    key = settings_key(salt)
    theme_key = generate_key(tdata)

    record = tdf(args.version, encrypt_local(
        theme_body(content, str(args.theme), args.theme.name), key))
    settings = tdf(args.version, salt, encrypt_local(
        settings_body(theme_key, not args.no_app_settings), key))

    write_atomic(tdata / (file_part(theme_key) + "s"), record)
    write_atomic(tdata / "settingss", settings)
    print(f"tdata-seed: seeded {tdata} (theme record {file_part(theme_key)}s, "
          f"version {args.version}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
