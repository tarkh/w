#!/usr/bin/env python3
"""Point Heroic Games Launcher at W's rendered custom theme, before its first run.

Heroic's theming is a two-key affair, and the keys live in two different files
(verified against the upstream sources, `main` branch, 2026-09-25):

  * ``customThemesPath`` — a GlobalConfig setting in ``~/.config/heroic/config.json``
    under ``defaultSettings``. The backend lists ``*.css`` from that directory
    (``getCustomThemes``) and reads the selected one (``getThemeCSS``).
  * ``theme`` — a top-level key in ``~/.config/heroic/store/config.json``
    (electron-store, ``cwd: 'store'``). It holds the FILE NAME, extension
    included; the frontend strips ``.css`` to build the ``<body>`` class, which
    is why the rendered stylesheet is scoped ``body.w`` and named ``w.css``.

Neither key has an external "apply" channel, but both files are plain JSON that
Heroic merges over its own defaults — so an account whose Heroic has never run
can be pointed at W's theme in advance, and the very first launch comes up in
W's colours. The stylesheet itself is NOT written here: it belongs to the
``400-heroic`` w-style axis, which re-renders it on every ``w-theme set``.

One upstream trap drives the shape of the seed (``src/backend/config.ts``,
``GlobalConfigV0.getSettings``)::

    if (!defaultSettings.defaultWinePrefixDir)
      defaultSettings.defaultWinePrefixDir = defaultSettings.defaultWinePrefix
    const winePrefix = defaultSettings?.winePrefix?.replace('~', userHome)
    settings = { ...this.getFactoryDefaults(), ...defaultSettings, winePrefix }

A config.json we create from scratch therefore may not carry ONLY our key: both
``defaultWinePrefixDir`` and ``winePrefix`` would end up spread over the factory
defaults as ``undefined`` (the first is assigned unconditionally inside the
``if``, the second is computed off a missing key), leaving Heroic with no Wine
prefix at all. So a fresh seed also writes the two prefix paths Heroic itself
would have derived. Merging into an existing config.json has no such problem and
touches exactly one key.

``--revert`` is the teardown half: it clears both keys, but only where the value
is still the one this script wrote.

Exit codes (same convention as the telegram bundle's tdata seeder):
  0 — something was changed
  3 — nothing to do (already in the wanted state)
  4 — the account has selected a different theme; W's is on disk but unused
  2 — error
"""

import argparse
import json
import os
import sys
import tempfile

STORE_SUBDIR = "store"
STORE_NAME = "config.json"
CONFIG_NAME = "config.json"


def warn(msg: str) -> None:
    print(f"  heroic-seed: {msg}", file=sys.stderr)


def read_json(path: str):
    """Return the parsed object, or None when the file is absent/unusable."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as err:
        raise RuntimeError(f"{path}: cannot read as JSON ({err})") from err
    if not isinstance(data, dict):
        raise TypeError(f"{path}: expected a JSON object")
    return data


def write_json(path: str, data, indent) -> None:
    """Replace `path` atomically, preserving its mode when it already exists."""
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    try:
        mode = os.stat(path).st_mode & 0o777
    except FileNotFoundError:
        mode = 0o644
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".heroic-seed.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=indent)
            fh.write("\n")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def seed_themes_path(config_dir: str, themes_dir: str) -> bool:
    """Set defaultSettings.customThemesPath. Returns True when changed."""
    path = os.path.join(config_dir, CONFIG_NAME)
    data = read_json(path)

    if data is None:
        # Heroic never ran: write the minimum that is SAFE to write (see the
        # module docstring — a lone customThemesPath would strip the Wine
        # prefixes). The two prefix values are the ones Heroic's own
        # constants/paths.ts derives from $HOME.
        home = os.path.dirname(os.path.dirname(config_dir))
        prefixes = os.path.join(home, "Games", "Heroic", "Prefixes")
        write_json(
            path,
            {
                "defaultSettings": {
                    "customThemesPath": themes_dir,
                    "defaultWinePrefix": prefixes,
                    "winePrefix": os.path.join(prefixes, "shared"),
                },
                "version": "v0",
            },
            indent=2,
        )
        return True

    settings = data.get("defaultSettings")
    if not isinstance(settings, dict):
        raise TypeError(f"{path}: 'defaultSettings' is not an object")

    current = settings.get("customThemesPath")
    if isinstance(current, str) and current.strip() and current != themes_dir:
        warn(f"customThemesPath is already set to {current!r} — left untouched.")
        return False
    if current == themes_dir:
        return False

    settings["customThemesPath"] = themes_dir
    write_json(path, data, indent=2)
    return True


def seed_theme_choice(config_dir: str, theme_name: str) -> str:
    """Set the top-level `theme` key in store/config.json.

    Returns "set" (we just selected W's theme), "already" (it was already
    selected) or "foreign" — the account has picked a different theme, which is
    its call to make and which the caller must report differently: the palette
    is on disk and listed in Heroic's dropdown, it is simply not in use.
    """
    path = os.path.join(config_dir, STORE_SUBDIR, STORE_NAME)
    data = read_json(path)
    if data is None:
        data = {}

    current = data.get("theme")
    if current == theme_name:
        return "already"
    if isinstance(current, str) and current.strip():
        warn(f"Heroic's theme is set to {current!r} — that choice is yours, left as-is.")
        return "foreign"

    data["theme"] = theme_name
    # electron-store writes with tabs; match it so Heroic's own rewrites do not
    # reformat the whole file on the first setting change.
    write_json(path, data, indent="\t")
    return "set"


def revert(config_dir: str, themes_dir: str, theme_name: str) -> bool:
    """Undo the seed, but only where the value is still ours.

    ``theme`` is DELETED rather than set to a literal: the frontend reads it as
    ``configStore.get('theme', DEFAULT_THEME)``, so an absent key is exactly
    "Heroic's own default" and W does not have to name (and re-pin) it. A value
    the user has since changed is left alone in both files.
    """
    changed = False

    store = os.path.join(config_dir, STORE_SUBDIR, STORE_NAME)
    data = read_json(store)
    if data is not None:
        if data.get("theme") == theme_name:
            del data["theme"]
            write_json(store, data, indent="\t")
            changed = True
        elif "theme" in data:
            warn(f"Heroic's theme is {data['theme']!r}, not ours — left untouched.")

    path = os.path.join(config_dir, CONFIG_NAME)
    data = read_json(path)
    if data is not None:
        settings = data.get("defaultSettings")
        if isinstance(settings, dict) and settings.get("customThemesPath") == themes_dir:
            settings["customThemesPath"] = ""
            write_json(path, data, indent=2)
            changed = True

    return changed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--config-dir",
        required=True,
        help="Heroic's config directory (~/.config/heroic)",
    )
    ap.add_argument(
        "--theme",
        required=True,
        help="path to the stylesheet rendered by the 400-heroic axis "
        "(need not exist with --revert)",
    )
    ap.add_argument(
        "--revert",
        action="store_true",
        help="undo the seed instead of applying it (teardown-user.sh)",
    )
    args = ap.parse_args()

    config_dir = os.path.abspath(args.config_dir)
    theme = os.path.abspath(args.theme)
    themes_dir = os.path.dirname(theme)
    theme_name = os.path.basename(theme)

    if not theme_name.endswith(".css"):
        warn(f"{theme_name}: not a .css file — Heroic only lists *.css.")
        return 2

    try:
        if args.revert:
            changed = revert(config_dir, themes_dir, theme_name)
        else:
            try:
                if os.path.getsize(theme) == 0:
                    warn(f"{theme}: empty stylesheet — refusing to select it.")
                    return 2
            except OSError as err:
                warn(f"{theme}: not readable ({err}).")
                return 2
            changed = seed_themes_path(config_dir, themes_dir)
            choice = seed_theme_choice(config_dir, theme_name)
            if choice == "foreign":
                return 4
            changed = changed or choice == "set"
    except (RuntimeError, TypeError) as err:
        warn(str(err))
        return 2
    except OSError as err:
        warn(f"cannot write Heroic's config ({err}).")
        return 2

    return 0 if changed else 3


if __name__ == "__main__":
    sys.exit(main())
