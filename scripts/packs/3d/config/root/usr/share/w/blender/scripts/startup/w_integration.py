# W integration for Blender — shipped by the `3d` W-Pack (managed, do not edit).
#
# Blender finds this file through BLENDER_SYSTEM_SCRIPTS (/etc/w/env.d/3d.sh):
# a system scripts root that is ADDED to the bundled one and, unlike every
# per-user Blender path (~/.config/blender/<version>/…), does not change with the
# Blender version. Modules in its startup/ are registered on every launch. Two
# jobs, both no-ops in background mode (`blender -b` renders and batch scripts
# are never touched):
#
# 1. Theme. The w-style axis `blender` renders ~/.config/w/blender-theme.json —
#    a base ("dark"/"light" = Blender's own presets) plus W colour overrides by
#    RNA path. This module composes them into the user preset "W"
#    (presets/interface_theme/W.xml) and makes it the active theme. Blender
#    records the active preset in preferences.themes[0].filepath, which is the
#    ownership signal: an empty path (no theme ever chosen) or W.xml means W
#    follows — at start and LIVE while Blender runs (the JSON is polled, so
#    `w-theme set` recolours an open Blender); any other preset the user picks
#    stays theirs until they pick "W" again.
#
# 2. The AI bridge add-on. mcp-for-blender (installed per account by the pack's
#    setup-user.sh as a uv tool) bundles the Blender half of the bridge. It is
#    copied into the add-on folder of the RUNNING Blender version whenever it
#    differs (so a `uv tool upgrade` or a new Blender version keeps both halves
#    in step) and enabled once per Blender version — an add-on the user later
#    disables stays disabled. Enabled, it opens its localhost socket at start.

import json
import os
import shutil
from glob import glob
from pathlib import Path

import bpy

HOME = Path.home()
THEME_JSON = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "w" / "blender-theme.json"
STATE_JSON = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local" / "state") / "w" / "blender.json"
UV_TOOLS = Path(os.environ.get("UV_TOOL_DIR") or HOME / ".local" / "share" / "uv" / "tools")
ADDON_GLOB = "mcp-for-blender/lib/python*/site-packages/blender_mcp/bundled/addon.py"
ADDON_MODULE = "blender_mcp"     # the file name upstream's own install-addon uses
PRESET_MENU = "USERPREF_MT_interface_theme_presets"
POLL_SECONDS = 2.0

_theme_mtime = None


def _log(msg):
    print(f"W: {msg}")


def _load_state():
    try:
        return json.loads(STATE_JSON.read_text())
    except (OSError, ValueError):
        return {}


def _save_state(state):
    try:
        STATE_JSON.parent.mkdir(parents=True, exist_ok=True)
        STATE_JSON.write_text(json.dumps(state, indent=1))
    except OSError as e:
        _log(f"cannot write {STATE_JSON}: {e}")


# ── Theme ────────────────────────────────────────────────────────────────────

def _w_preset_path():
    return Path(bpy.utils.user_resource("SCRIPTS", path="presets/interface_theme", create=True)) / "W.xml"


def _theme_is_ours(theme):
    return not theme.filepath or Path(theme.filepath).name == "W.xml"


def _rgba(hexstr):
    h = hexstr.lstrip("#")
    return [int(h[i:i + 2], 16) / 255 for i in range(0, len(h), 2)]


def _targets(theme, path):
    """Resolve 'a.b.c' (or '*.b.c' = every theme section that has b.c) to (owner, attr) pairs."""
    head, *rest = path.split(".")
    roots = ([getattr(theme, p.identifier) for p in theme.bl_rna.properties if p.type == "POINTER"]
             if head == "*" else [getattr(theme, head, None)])
    for obj in roots:
        for part in rest[:-1]:
            obj = getattr(obj, part, None)
        if obj is not None and hasattr(obj, rest[-1]):
            yield obj, rest[-1]


def _write_preset(path):
    # _rna_xml scans every public name on bpy.types as a class; mcp-for-blender
    # parks its server INSTANCE there (bpy.types.blendermcp_server), which makes
    # the scan raise — Blender's own "Save Theme" included. Hide such names for
    # the write and put them back.
    import _rna_xml as rna_xml
    parked = {n: getattr(bpy.types, n) for n in dir(bpy.types)
              if not n.startswith("_") and not isinstance(getattr(bpy.types, n), type)}
    for n in parked:
        delattr(bpy.types, n)
    try:
        rna_xml.xml_file_write(bpy.context, str(path), getattr(bpy.types, PRESET_MENU).preset_xml_map)
    finally:
        for n, v in parked.items():
            setattr(bpy.types, n, v)


def _apply_theme(spec):
    prefs = bpy.context.preferences
    theme = prefs.themes[0]
    bpy.ops.preferences.reset_default_theme()          # = Blender Dark
    if spec.get("base") == "light":
        light = Path(bpy.utils.system_resource("SCRIPTS")) / "presets/interface_theme/Blender_Light.xml"
        bpy.ops.script.execute_preset(filepath=str(light), menu_idname=PRESET_MENU)
    for path, value in spec.get("colors", {}).items():
        rgba = _rgba(value)
        for owner, attr in _targets(theme, path):
            cur = getattr(owner, attr)
            # #rrggbb keeps the slot's own alpha; #rrggbbaa sets it.
            setattr(owner, attr, rgba[:len(cur)] if len(rgba) >= len(cur) else rgba + list(cur)[len(rgba):])
    preset = _w_preset_path()
    _write_preset(preset)
    theme.filepath = str(preset)
    getattr(bpy.types, PRESET_MENU).bl_label = "W"      # what the Quick Setup splash shows
    prefs.is_dirty = True                               # auto-save keeps it across restarts


def _sync_theme(force=False):
    global _theme_mtime
    try:
        mtime = THEME_JSON.stat().st_mtime
    except OSError:
        return
    if mtime == _theme_mtime and not force:
        return
    _theme_mtime = mtime
    if not _theme_is_ours(bpy.context.preferences.themes[0]):
        return
    try:
        _apply_theme(json.loads(THEME_JSON.read_text()))
    except Exception as e:  # noqa: BLE001 — an escaping error would unregister the poll timer for good
        _log(f"theme not applied: {e!r}")


# ── AI bridge add-on ─────────────────────────────────────────────────────────

def _sync_mcp_addon(state):
    hits = sorted(glob(str(UV_TOOLS / ADDON_GLOB)))
    if not hits:
        return False
    import addon_utils
    src = Path(hits[-1])
    dst = Path(bpy.utils.user_resource("SCRIPTS", path="addons", create=True)) / f"{ADDON_MODULE}.py"
    changed = not dst.is_file() or dst.read_bytes() != src.read_bytes()
    if changed:
        shutil.copyfile(src, dst)
        bpy.utils.refresh_script_paths()    # an add-on folder born this session is not on sys.path yet
        addon_utils.modules_refresh()
    version = "{}.{}".format(*bpy.app.version[:2])
    enabled = bpy.context.preferences.addons.find(ADDON_MODULE) != -1
    done = state.setdefault("mcp_enabled", [])
    if version not in done:
        addon_utils.enable(ADDON_MODULE, default_set=True, persistent=True)
        done.append(version)
        # Saved now, not at quit: "enabled once" is recorded in our state, so
        # preferences lost to a crash or a kill would leave the add-on off for good.
        bpy.ops.wm.save_userpref()
        return True
    if changed and enabled:                             # pick up the new add-on code
        addon_utils.disable(ADDON_MODULE, default_set=False)
        addon_utils.enable(ADDON_MODULE, default_set=False, persistent=True)
    return False


# ── Lifecycle ────────────────────────────────────────────────────────────────

def _boot():
    _sync_theme(force=True)
    state = _load_state()
    if _sync_mcp_addon(state):                          # saves preferences — theme included
        _save_state(state)
    bpy.app.timers.register(_poll, first_interval=POLL_SECONDS, persistent=True)
    # Returning None = a one-shot timer.


def _poll():
    _sync_theme()
    return POLL_SECONDS


def register():
    if bpy.app.background:
        return
    # The first-start splash is drawn before _boot runs and names the theme from this label.
    if THEME_JSON.is_file() and _theme_is_ours(bpy.context.preferences.themes[0]):
        getattr(bpy.types, PRESET_MENU).bl_label = "W"
    # After the UI and the user's preferences are up (add-ons enabled, theme loaded).
    bpy.app.timers.register(_boot, first_interval=0.5)


def unregister():
    for fn in (_boot, _poll):
        if bpy.app.timers.is_registered(fn):
            bpy.app.timers.unregister(fn)
