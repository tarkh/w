-- W Linux — active hotkey profile. Managed by `w-hotkeys` (and the W Hub Hotkeys
-- panel); hand-edits are overwritten. Data module require()d by hyprland.lua, whose
-- keybinding section threads it through the action catalog (hotkeys-catalog.lua).
--
-- profile : name of the active profile ("default" = the W defaults, "i3-vim" = i3 legacy,
--           or a user profile from ~/.config/hypr/hotkeys.d/).
-- map     : token → key chord overrides. An empty map means "use the catalog defaults"
--           (so the shipped "default" profile carries no overrides). `w-hotkeys use i3-vim`
--           writes the full i3-vim map here; `set`/`reset` edit single entries.
-- custom  : user-defined actions, each { chord = "SUPER + ...", exec = "shell command" }.
return {
  profile = "default",
  map = {},
  custom = {},
}
