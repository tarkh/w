-- W Linux — greeter-only Hyprland config (greetd default session), Lua format
-- (the config language since Hyprland 0.55). Minimal and locked down: it exists
-- solely to host the Quickshell greeter, which does one thing — authenticate a
-- user. There are deliberately NO keybinds, NO exec dispatchers beyond the greeter
-- wrapper and NO global shortcuts. The session starts black (background_color) so
-- the fade-in from Plymouth and the fade-out into the user session are seamless
-- (the greeter draws the wallpaper and animates it itself).

-- Writable HOME for the whole greeter session (compositor + shell + w-wallpaper):
-- the greeter user otherwise has no usable home, so Qt/Hyprland caches have nowhere
-- to go and fall back to software rendering (the regreet HOME=/ → 126% CPU lesson).
hl.env("HOME", "/var/lib/w-greeter")
hl.env("QT_QPA_PLATFORM", "wayland")

hl.config({
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    background_color = 0xff000000,
    -- No "Hyprland was updated" popup in the greeter — it has no business here and
    -- the hyprland-update-screen helper (hyprland-guiutils) SIGABRTs in this session.
    disable_hyprland_guiutils_check = true,
  },

  general = {
    border_size = 0,
    gaps_in = 0,
    gaps_out = 0,
  },

  decoration = {
    rounding = 0,
    rounding_power = 0,
    -- Enabled so the compositor can blur the wallpaper behind a translucent login
    -- card (greeter.json cardOpacity < 1). Same settings as the user session.
    blur = {
      enabled = true,
      size = 1,
      passes = 3,
      new_optimizations = true,
    },
    shadow = { enabled = false },
  },

  ecosystem = {
    no_update_news = true,
    no_donation_nag = true,
  },
})

-- Fallback rule first: catches any output with no saved w-monitor rule
-- (unconfigured / freshly hotplugged). Explicit whitelist below — mirrors the
-- session's hyprland.lua (see rootfs/etc/skel/.config/hypr/hyprland.lua); this
-- scope's layout is written by `w-monitor greeter` (see w-monitor.md §Этап 4),
-- never by hand.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
local ok, greeter_mons = pcall(require, "/etc/w/monitors-greeter.lua")
-- Every output name our own rules mention — used ONLY as a static list for the
-- best-effort boot safety net below (hyprland.start), never as a runtime query.
-- ⚠️ KNOWN INCOMPLETE (see w-monitor.md §Отложено/known bugs, VM-verified
-- 2026-07-31): this recovers a monitor that got disabled while at least one OTHER
-- real output stayed enabled and reached a real modeset at boot. It does NOT
-- recover the worse case — every configured output disabled from the very first
-- modeset — because Hyprland then falls back to its own internal synthetic
-- "FALLBACK" pseudo-monitor, and its renderer never bootstraps a real one after
-- that; a later hl.monitor(disabled=false) call is accepted (no error) but never
-- reaches the hardware (confirmed live: screen stays black, IPC stays responsive,
-- even after hyprctl reload). No in-Lua API exists to detect "connected but
-- disabled" ahead of that point either (hl.get_monitors() only reports currently-
-- ENABLED outputs, and monitor.added never fires for a connector that starts out
-- disabled=true) — re-declaring disabled=false for a name that isn't connected is
-- a harmless no-op, so this blind retry is still worth keeping for the case it
-- does cover.
--
-- The worse case IS covered now, just not from here: greetd runs `w-monitor greeter
-- sanity` as ExecStartPre, before this file is parsed, and it re-enables one
-- connected output if every one of them would start disabled. Outside the compositor
-- it can read /sys/class/drm, which is the piece no in-Lua API offers. See w-monitor.
local configured_names = {}
if ok and type(greeter_mons) == "table" and type(greeter_mons.outputs) == "table" then
  for _, m in ipairs(greeter_mons.outputs) do
    if type(m) == "table" and type(m.output) == "string" and m.output ~= "" then
      table.insert(configured_names, m.output)
      if m.disabled then
        hl.monitor({ output = m.output, disabled = true })
      else
        hl.monitor({ output = m.output, mode = m.mode or "preferred",
                     position = m.position or "auto", scale = m.scale or "auto",
                     transform = m.transform or 0 })
      end
    end
  end
end

-- Animations: fade only (no window movement) for a calm login surface.
hl.config({ animations = { enabled = true } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.animation({ leaf = "windows", enabled = false })
hl.animation({ leaf = "fade",    enabled = true, speed = 3, bezier = "easeInOutCubic" })
hl.animation({ leaf = "layers",  enabled = true, speed = 4, bezier = "easeInOutCubic", style = "fade" })

-- Blur the wallpaper behind the (translucent) login card. ignore_alpha keeps blur
-- out of the fully-transparent backdrop AND couples it to the card's fade: blur is
-- skipped where surface alpha < 0.3, so it tracks the fade instead of popping in
-- before / lingering after the card (the desync seen without this rule).
hl.layer_rule({ match = { namespace = "^(w-greeter)$" }, blur = true, ignore_alpha = 0.3 })

-- Autostart. hyprland.start fires once at compositor start.
hl.on("hyprland.start", function()
  -- Boot safety net: see configured_names' comment above for why this is a blind
  -- retry rather than a targeted one. The layout above is a static snapshot that
  -- can go stale (a monitor unplugged since it was last written, leaving only a
  -- disabled=true rule pointing at whatever IS still connected) — Hyprland has no
  -- built-in "keep at least one real monitor alive" guard.
  local any_configured_live = false
  for _, m in ipairs(hl.get_monitors()) do
    for _, name in ipairs(configured_names) do
      if m.name == name then any_configured_live = true end
    end
  end
  if not any_configured_live then
    for _, name in ipairs(configured_names) do
      hl.monitor({ output = name, disabled = false, mode = "preferred", position = "auto", scale = "auto" })
    end
  end

  hl.exec_cmd("/etc/greetd/w-greeter-wrapper.sh")
  -- Idle display power management for the login screen, with its own config
  -- (separate from the user session's hypridle). It only blanks the screen on idle
  -- — there is nothing to lock here. hypridle's --config flag is broken in this
  -- build, so point it at the config via XDG_CONFIG_HOME (it then reads
  -- $XDG_CONFIG_HOME/hypr/hypridle.conf) — scoped to hypridle alone.
  hl.exec_cmd("env XDG_CONFIG_HOME=/etc/greetd hypridle")
end)
