-- W Linux — virtio-GPU (QEMU/KVM guest) quirk. Not a window rule: it lives in this
-- vendor drop-in dir because both the user session (hyprland.lua's rules.d glob) and
-- the greeter (an explicit require) load it, and W keeps it current on every machine.
--
-- Hyprland 0.57 turned quirks.skip_non_kms_dmabuf_formats on by default. Under virgl
-- that hides the implicit-modifier ARGB8888 format Qt's GL path renders into, so
-- every translucent layer-shell surface (Quickshell's full-screen notification layer,
-- the greeter) comes out opaque black over the wallpaper, bar and windows. Real GPUs
-- keep the upstream default (it serves direct scanout); a VM gets the 0.56 behaviour.
for i = 0, 7 do
  local f = io.open("/sys/class/drm/card" .. i .. "/device/vendor")
  local vendor = f and f:read("l")
  if f then f:close() end
  if vendor == "0x1af4" then
    hl.config({ quirks = { skip_non_kms_dmabuf_formats = false } })
    break
  end
end
