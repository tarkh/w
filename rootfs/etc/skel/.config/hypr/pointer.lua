-- W Linux — pointer devices (mouse + touchpad + touchpad gestures). Managed by
-- `w-pointer` (and the W Hub Input panel); hand-edits are overwritten. Data module
-- require()d by hyprland.lua, which threads these into input{}, input.touchpad{},
-- gestures{}, per-device hl.device() rules and the workspace-swipe hl.gesture().
--
-- mouse.*     : global pointer settings (they apply to every pointer device).
-- touchpad.*  : input.touchpad keys, plus the three that Hyprland only accepts
--               per-device (enabled / sensitivity / accel_profile) — those are
--               emitted as hl.device() rules for every name in devices.touchpads.
-- gestures.*  : workspace swipe. workspace_fingers = 0 disables the gesture.
-- cursor.*    : idle-hiding timeouts in SECONDS (cursor.inactive_timeout).
--               system_timeout is the session-wide default; menu_timeout is
--               applied while a modal Quickshell popup holds the cursor lease
--               (hyprland.lua's w_cursor_lease watchdog). 0 = never hide.
-- devices.touchpads : Hyprland device names of the touchpads found by
--               `w-pointer detect` (hyprctl devices). Empty on a machine without
--               one — and on a laptop until the first detect inside a session.
return {
  mouse = {
    sensitivity = 0.0,            -- -1.0 .. 1.0 (libinput pointer acceleration)
    accel_profile = "adaptive",   -- adaptive | flat
    natural_scroll = false,
    scroll_factor = 1.0,
    left_handed = false,
  },
  cursor = {
    system_timeout = 0.0,         -- s of pointer inactivity before the cursor hides
    menu_timeout = 0.1,           -- same, while a modal Quickshell popup is open
  },
  touchpad = {
    enabled = true,
    sensitivity = 0.0,            -- -1.0 .. 1.0, applied per-device
    accel_profile = "adaptive",   -- adaptive | flat
    natural_scroll = true,        -- W default since the first Hyprland config
    scroll_factor = 1.0,
    disable_while_typing = true,
    tap_to_click = true,
    tap_button_map = "lrm",       -- lrm: 2 fingers = RMB, 3 = MMB · lmr: swapped
    clickfinger_behavior = false, -- false: physical click zones · true: click by finger count
    middle_button_emulation = false,
    tap_and_drag = true,
    drag_lock = 0,                -- 0 off · 1 with timeout · 2 sticky
    drag_3fg = 0,                 -- 0 off · 1 three-finger drag · 2 four-finger drag
  },
  gestures = {
    workspace_fingers = 3,        -- 0 off · 3 · 4
    swipe_distance = 300,
    swipe_invert = true,          -- natural (content-follows-fingers) direction
    swipe_create_new = true,      -- swiping past the last workspace creates one
  },
  devices = {
    touchpads = {},
  },
}
