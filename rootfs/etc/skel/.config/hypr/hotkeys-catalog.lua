-- W Linux — Hotkey action catalog (W-managed; hand-edits are overwritten).
-- Data module require()d by hyprland.lua. Binds are DATA now: this catalog maps stable
-- action TOKENS → Hyprland dispatchers (+ each token's W-default chord), and the active
-- profile (user-owned `hotkeys.lua`, rewritten by `w-hotkeys` / the W Hub) maps those
-- tokens → key chords. `apply(hk)` binds every action to its chord (profile override, else
-- the default here), then the fixed media/mouse binds. `hyprctl reload` re-runs this to
-- apply a profile switch live.
--
-- The token set + default chords here MUST stay in sync with the CLI-side contract
-- /usr/share/w/hotkeys/catalog.tokens (token<TAB>category<TAB>default_chord), which
-- `w-hotkeys` reads. Two representations because two runtimes need them (this Lua module
-- for the compositor, the TSV for the bash CLI / the Hub GUI). Chord STRINGS must be
-- byte-identical between the two (the GUI shows the TSV default, the compositor binds this
-- one) — keep the " + " spacing and modifier order in lockstep.
--
-- Dispatchers are built lazily inside apply() so `hl` is always live. Parametric families
-- (workspaces ws_1..ws_N / move_ws_1..move_ws_N, focus/move directions) are expanded in
-- apply(); the numbered-workspace tokens carry a template label in the GUI (hotkeys.ws /
-- hotkeys.move_ws with %n%), so growing M.workspaces needs no per-workspace i18n string.
-- Media keys + mouse drag/resize + the resize submap's inner keys are FIXED (not rebindable
-- in this phase): apply() always binds them, independent of the profile map.
local M = {}

-- How many workspace tokens to expand (ws_1..ws_N, move_ws_1..move_ws_N). Key for N=10 is
-- the "0" row (SUPER + 0 == workspace 10).
M.workspaces = 10
-- Directional tokens: focus_<d> (SUPER + arrow) and move_<d> (SUPER + SHIFT + arrow).
M.directions = { "left", "right", "up", "down" }

-- Workspace index → its number key ("10" is bound to the 0 key).
local function wskey(i) return i == 10 and "0" or tostring(i) end

-- Ordered catalog of the discrete (non-parametric) rebindable actions.
--   id  : stable token (matches catalog.tokens / profile maps)
--   cat : category, for grouping in the Hub
--   def : W-default chord (the "default" profile == these defaults)
--   dsp : function returning the Hyprland dispatcher (built at apply time)
--   flags (optional) : bind flags table
M.actions = {
  -- Apps / shell surfaces.
  { id = "terminal",     cat = "apps",   def = "SUPER + Return",         dsp = function() return hl.dsp.exec_cmd("w-term") end },
  { id = "terminal_alt", cat = "apps",   def = "SUPER + SHIFT + Return", dsp = function() return hl.dsp.exec_cmd("uwsm app -- foot") end },
  { id = "launcher",     cat = "apps",   def = "SUPER + D",              dsp = function() return hl.dsp.global("quickshell:launcher") end },
  { id = "hub",          cat = "apps",   def = "SUPER + Space",          dsp = function() return hl.dsp.global("quickshell:hub") end },
  { id = "assistant",    cat = "apps",   def = "SUPER + W",              dsp = function() return hl.dsp.global("quickshell:assistant") end },
  { id = "volume",       cat = "apps",   def = "SUPER + A",              dsp = function() return hl.dsp.global("quickshell:volumecontrol") end },
  { id = "powermenu",    cat = "apps",   def = "SUPER + Backspace",      dsp = function() return hl.dsp.global("quickshell:powermenu") end },
  { id = "files",        cat = "apps",   def = "SUPER + E",              dsp = function() return hl.dsp.exec_cmd("uwsm app -- nemo") end },
  { id = "browser",      cat = "apps",   def = "SUPER + B",              dsp = function() return hl.dsp.exec_cmd("uwsm app -- firefox") end },

  -- Window management.
  { id = "close",          cat = "window", def = "SUPER + Q",             dsp = function() return hl.dsp.window.close() end },
  { id = "kill",           cat = "window", def = "SUPER + SHIFT + Q",     dsp = function() return hl.dsp.window.kill() end },
  { id = "fullscreen",     cat = "window", def = "SUPER + F",             dsp = function() return hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }) end },
  { id = "fake_fullscreen",cat = "window", def = "SUPER + SHIFT + F",     dsp = function() return hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }) end },
  { id = "maximize",       cat = "window", def = "SUPER + M",             dsp = function() return hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }) end },
  { id = "float",          cat = "window", def = "SUPER + SHIFT + Space", dsp = function() return hl.dsp.window.float({ action = "toggle" }) end },
  { id = "center",         cat = "window", def = "SUPER + SHIFT + C",     dsp = function() return hl.dsp.window.center() end },
  { id = "pin",            cat = "window", def = "SUPER + P",             dsp = function() return hl.dsp.window.pin() end },
  { id = "group_toggle",   cat = "window", def = "SUPER + G",             dsp = function() return hl.dsp.group.toggle() end },
  { id = "group_next",     cat = "window", def = "SUPER + Tab",           dsp = function() return hl.dsp.group.next() end },
  { id = "group_prev",     cat = "window", def = "SUPER + SHIFT + Tab",   dsp = function() return hl.dsp.group.prev() end },
  { id = "group_into",     cat = "window", def = "SUPER + SHIFT + G",     dsp = function() return hl.dsp.window.move({ into_group = "right" }) end },
  { id = "group_out",      cat = "window", def = "SUPER + CTRL + G",      dsp = function() return hl.dsp.window.move({ out_of_group = true }) end },
  { id = "resize_mode",    cat = "window", def = "SUPER + R",             dsp = function() return hl.dsp.submap("resize") end },

  -- Focus / navigation (directional focus_* added parametrically below).
  { id = "cycle_next",     cat = "focus",  def = "SUPER + CTRL + Tab",    dsp = function() return hl.dsp.window.cycle_next() end },
  { id = "focus_mon_prev", cat = "focus",  def = "SUPER + CTRL + left",   dsp = function() return hl.dsp.focus({ monitor = "-1" }) end },
  { id = "focus_mon_next", cat = "focus",  def = "SUPER + CTRL + right",  dsp = function() return hl.dsp.focus({ monitor = "+1" }) end },

  -- Move (directional move_* added parametrically below; numbered move_ws_* too).
  { id = "move_ws_prev",   cat = "move",   def = "SUPER + CTRL + SHIFT + left",  dsp = function() return hl.dsp.window.move({ workspace = "-1" }) end },
  { id = "move_ws_next",   cat = "move",   def = "SUPER + CTRL + SHIFT + right", dsp = function() return hl.dsp.window.move({ workspace = "+1" }) end },
  { id = "move_mon_prev",  cat = "move",   def = "SUPER + SHIFT + ALT + left",   dsp = function() return hl.dsp.window.move({ monitor = "-1" }) end },
  { id = "move_mon_next",  cat = "move",   def = "SUPER + SHIFT + ALT + right",  dsp = function() return hl.dsp.window.move({ monitor = "+1" }) end },
  { id = "scratchpad_send",   cat = "move", def = "SUPER + SHIFT + S",    dsp = function() return hl.dsp.window.move({ workspace = "special:scratchpad" }) end },
  { id = "scratchpad_return", cat = "move", def = "SUPER + CTRL + S",     dsp = function() return hl.dsp.window.move({ workspace = "+0" }) end },

  -- Workspace (numbered ws_* added parametrically below).
  { id = "ws_next",        cat = "workspace", def = "SUPER + ALT + right", dsp = function() return hl.dsp.focus({ workspace = "e+1" }) end },
  { id = "ws_prev",        cat = "workspace", def = "SUPER + ALT + left",  dsp = function() return hl.dsp.focus({ workspace = "e-1" }) end },
  { id = "scratchpad_toggle", cat = "workspace", def = "SUPER + S",        dsp = function() return hl.dsp.workspace.toggle_special("scratchpad") end },

  -- Dwindle layout.
  { id = "pseudo",         cat = "dwindle", def = "SUPER + SHIFT + P",    dsp = function() return hl.dsp.window.pseudo() end },
  { id = "togglesplit",    cat = "dwindle", def = "SUPER + J",            dsp = function() return hl.dsp.layout("togglesplit") end },

  -- System.
  { id = "lock",              cat = "system", def = "SUPER + L",          dsp = function() return hl.dsp.exec_cmd("loginctl lock-session") end },
  { id = "reload",            cat = "system", def = "SUPER + SHIFT + R",  dsp = function() return hl.dsp.exec_cmd("hyprctl reload") end },
  { id = "clipboard",         cat = "system", def = "SUPER + V",          dsp = function() return hl.dsp.global("quickshell:clipboard") end },
  { id = "layouts",           cat = "system", def = "SUPER + O",          dsp = function() return hl.dsp.global("quickshell:layouts") end },
  { id = "screenshot_screen", cat = "system", def = "SUPER + I",          dsp = function() return hl.dsp.exec_cmd("w-screenshot output") end },
  { id = "screenshot_region", cat = "system", def = "SUPER + SHIFT + I",  dsp = function() return hl.dsp.exec_cmd("w-screenshot region") end },
  { id = "screenshot_window", cat = "system", def = "SUPER + CTRL + I",   dsp = function() return hl.dsp.exec_cmd("w-screenshot window") end },
  { id = "dnd",               cat = "system", def = "SUPER + SHIFT + D",  dsp = function() return hl.dsp.exec_cmd("w-notify dnd toggle") end },
  { id = "nightlight",        cat = "system", def = "SUPER + SHIFT + N",  dsp = function() return hl.dsp.exec_cmd("w-nightlight toggle") end },

  -- NOTE: catalog.tokens also carries a "menu" category (menu_up/down/left/right/confirm/
  -- back/delete) for the keyboard navigation of every Quickshell surface — the W Hub and
  -- its panels, but equally the launcher, clipboard viewer, assistant, layouts panel,
  -- volume/brightness popups, calendar, infobox, file picker and auth prompt.
  -- Deliberately absent from M.actions/apply() below: each of those surfaces holds the
  -- keyboard itself while open, so it reads these chords via `w-hotkeys status
  -- --porcelain` (see core/HubNavKeys.qml) instead of needing a compositor-level bind. This
  -- is the one documented exception to the "these two files stay in lockstep" rule at the
  -- top of this file — catalog.tokens is still authoritative for the token/category/default
  -- triple.
}

-- Resize submap: SUPER+R (the resize_mode token) enters it; arrows resize the active
-- window (repeating), Enter/Escape leave. Inner keys are fixed (not rebindable). Redefined
-- on every apply/reload — harmless.
local function define_submaps()
  hl.define_submap("resize", function()
    hl.bind("right", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
    hl.bind("left",  hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
    hl.bind("down",  hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })
    hl.bind("up",    hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("return", hl.dsp.submap("reset"))
  end)

  -- Chord-capture passthrough submap: the W Hub's Hotkeys rebind UI enters this while
  -- listening for a new chord, so global binds are suspended and the pressed combo (e.g.
  -- SUPER+Return) reaches the keyboard-focused Hub surface instead of firing its action.
  -- It binds nothing except a panic reset (a rare combo) so a Hub crash mid-capture can't
  -- leave the session stuck with no binds; the Hub itself resets the submap when done.
  hl.define_submap("capture", function()
    hl.bind("SUPER + CTRL + ALT + Escape", hl.dsp.submap("reset"))
  end)
end

-- Fixed binds: media keys + mouse drag/resize. Always bound (not part of any profile in
-- this phase), so a profile switch never drops volume/brightness/media/window-drag. Media
-- play/next/prev use playerctl (see packages/pacman.txt).
function M.fixed()
  hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true, locked = true })
  hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { repeating = true, locked = true })
  hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),        { locked = true })
  hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),      { locked = true })
  hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"),                              { locked = true })
  hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),                                    { locked = true })
  hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),                                { locked = true })
  hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"),                             { repeating = true, locked = true })
  hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"),                             { repeating = true, locked = true })
  -- Keyboard backlight. Unlike the screen these go through w-kbdlight, because the
  -- led-class device is vendor-named (smc::/tpacpi::/dell::) and `brightnessctl -c
  -- leds` would grab an indicator LED (numlock) instead. A machine without a
  -- keyboard backlight never emits these keys, so the binds are inert there.
  hl.bind("XF86KbdBrightnessUp",   hl.dsp.exec_cmd("w-kbdlight up"),                                     { repeating = true, locked = true })
  hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("w-kbdlight down"),                                   { repeating = true, locked = true })
  hl.bind("XF86KbdLightOnOff",     hl.dsp.exec_cmd("w-kbdlight toggle"),                                 { locked = true })
  hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
  hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
end

-- Apply the active profile. `hk` = the loaded `hotkeys.lua` fragment:
--   { profile = "<name>", map = { token = "CHORD", ... }, custom = { { chord=, exec= }, ... } }
-- For each action the chord is the profile override (map[token]) if present, else the
-- catalog default. An explicit empty string ("") in the map means "unbound". A nil (token
-- absent from the map) falls back to the default — so an empty map == the W defaults, and
-- the "default" profile is exactly that.
function M.apply(hk)
  local map = (hk and type(hk.map) == "table") and hk.map or {}

  local function bind_tok(tok, def, dsp, flags)
    local chord = map[tok]
    if chord == nil then chord = def end
    if chord and chord ~= "" then hl.bind(chord, dsp, flags) end
  end

  define_submaps()

  for _, a in ipairs(M.actions) do
    bind_tok(a.id, a.def, a.dsp(), a.flags)
  end

  -- Workspaces: focus ws_i (SUPER + key) + move active window move_ws_i (SUPER + SHIFT + key).
  for i = 1, M.workspaces do
    bind_tok("ws_" .. i,      "SUPER + " .. wskey(i),         hl.dsp.focus({ workspace = i }))
    bind_tok("move_ws_" .. i, "SUPER + SHIFT + " .. wskey(i), hl.dsp.window.move({ workspace = i }))
  end

  -- Directional focus (SUPER + arrow) + move (SUPER + SHIFT + arrow).
  for _, d in ipairs(M.directions) do
    bind_tok("focus_" .. d, "SUPER + " .. d,         hl.dsp.focus({ direction = d }))
    bind_tok("move_" .. d,  "SUPER + SHIFT + " .. d, hl.dsp.window.move({ direction = d }))
  end

  -- User custom exec actions (arbitrary chord → shell command), carried by the fragment.
  if hk and type(hk.custom) == "table" then
    for _, c in ipairs(hk.custom) do
      if c.chord and c.chord ~= "" and c.exec and c.exec ~= "" then
        hl.bind(c.chord, hl.dsp.exec_cmd(c.exec))
      end
    end
  end

  M.fixed()
end

return M
