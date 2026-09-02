-- W Linux — keyboard layout ring + typing behaviour. Managed by `w-keyboard` (and
-- the W Hub Input panel); hand-edits are overwritten. Data module require()d by
-- hyprland.lua, whose input{} threads these into kb_layout / kb_variant /
-- kb_options / repeat_rate / repeat_delay / numlock_by_default.
--
-- layout  : ordered CSV of XKB layout codes cycled by the group toggle ("us,ru").
-- variant : parallel CSV of variants, one slot per layout ("" = default; ",dvorak").
-- options : XKB options, carrying the grp:*_toggle switch key.
-- repeat_rate  : held-key repeats per second.
-- repeat_delay : ms before a held key starts repeating.
-- numlock      : engage NumLock at login.
return {
  layout = "us,ru",
  variant = "",
  options = "grp:alt_shift_toggle",
  repeat_rate = 25,
  repeat_delay = 600,
  numlock = false,
}
