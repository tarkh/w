# w-mcp domain: input — keyboard-layout, keybinding and pointer state (Tier 0,
# read-only). These are user-space (no root): reads ground answers ("which layouts /
# what is bound to X / why doesn't tap-to-click work") and work even on a minimal host
# with no shell. Changing layouts, binds or pointer settings is done through the
# w-keyboard / w-hotkeys / w-pointer CLIs (rootless — the host shell covers actuation),
# so there is no privileged input tool here. The one privileged input action, locale,
# lives in the shared `system` module as w_locale_set (Tier 2).
# See the w-input skill / w-keyboard.md / w-hotkeys.md / w-pointer.md.
from core import run, tool

DOMAIN = "w-input"


def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_keyboard_status() -> str:
        """Keyboard layout ring: the ordered layouts, their variants, and the XKB
        options (including the `grp:*_toggle` layout-switch key). The first layout is
        the login default; the toggle key cycles them. Read-only — change the ring
        with the `w-keyboard` CLI (add/remove/set-toggle/set-default)."""
        return run(["w-keyboard", "status"])

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_hotkeys_status() -> str:
        """Active keybinding profile and its effective bindings: each action token,
        the chord bound to it, and the source (default / profile / custom). Use it to
        answer 'what is bound to X' / 'what does Super+… do'. Read-only — switch
        profiles or rebind with the `w-hotkeys` CLI (use/set/reset/custom-add)."""
        return run(["w-hotkeys", "status"])

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_pointer_status() -> str:
        """Mouse and touchpad settings: speed, acceleration profile, scrolling, and —
        when the machine has a touchpad — tap-to-click, click method, disable-while-
        typing, drag modes and the workspace-swipe gesture, plus whether a touchpad is
        present at all. Read-only — change any of it with the `w-pointer` CLI
        (`w-pointer keys` lists every settable key and its accepted values)."""
        return run(["w-pointer", "status"])
