-- W Linux — keep alpha-capable dmabuf formats where the display has no ARGB plane.
-- Not a window rule: it lives in this vendor drop-in dir because both the user session
-- (hyprland.lua's rules.d glob) and the greeter (an explicit require) load it, and W
-- keeps it current on every machine. A user rules.d file loads later and can override.
--
-- Hyprland 0.57 turned quirks.skip_non_kms_dmabuf_formats on by default (hyprwm/Hyprland
-- #15803): clients are offered only formats a KMS plane can scan out. Where no primary or
-- overlay plane takes ARGB8888, Mesa then renders translucent surfaces without alpha, and
-- Quickshell's full-screen layers (notifications, the greeter) cover everything in black:
--   virtio-gpu  scans out XRGB8888 only (QEMU, virgl or not)
--   Intel display gen <= 8 (i8xx..Broadwell, not VLV/CHV, whose sprites take ARGB)
-- Everywhere else the upstream default stays: it fixes direct-scanout black screens in
-- native-Wayland games (hyprwm/Hyprland discussions 14843) on AMD and NVIDIA alike.
-- Drop this file once Hyprland offers alpha formats on such hardware again — re-check on
-- every Hyprland update (package-hyprland.md).

-- PCI device IDs from the kernel's include/drm/intel/pciids.h (frozen hardware).
local legacy_intel = " " ..
  "0042 0046 0102 0106 010a 0112 0116 0122 0126 0152 0156 015a 0162 0166 016a 0402 0406 " ..
  "040a 040b 040e 0412 0416 041a 041b 041e 0422 0426 042a 042b 042e 0a02 0a06 0a0a 0a0b " ..
  "0a0e 0a12 0a16 0a1a 0a1b 0a1e 0a22 0a26 0a2a 0a2b 0a2e 0c02 0c06 0c0a 0c0b 0c0e 0c12 " ..
  "0c16 0c1a 0c1b 0c1e 0c22 0c26 0c2a 0c2b 0c2e 0d02 0d06 0d0a 0d0b 0d0e 0d12 0d16 0d1a " ..
  "0d1b 0d1e 0d22 0d26 0d2a 0d2b 0d2e 1132 1602 1606 160a 160b 160d 160e 1612 1616 161a " ..
  "161b 161d 161e 1622 1626 162a 162b 162d 162e 1632 1636 163a 163b 163d 163e 2562 2572 " ..
  "2582 258a 2592 2772 27a2 27ae 2972 2982 2992 29a2 29b2 29c2 29d2 2a02 2a12 2a42 2e02 " ..
  "2e12 2e22 2e32 2e42 2e92 3577 3582 358e 7121 7123 7125 a001 a011 "

local function read(path)
  local f = io.open(path)
  local v = f and f:read("l")
  if f then f:close() end
  return v
end

for i = 0, 7 do
  local dev = "/sys/class/drm/card" .. i .. "/device/"
  local vendor, device = read(dev .. "vendor"), read(dev .. "device")
  if vendor == "0x1af4"
     or (vendor == "0x8086" and device and legacy_intel:find(" " .. device:sub(3) .. " ", 1, true)) then
    hl.config({ quirks = { skip_non_kms_dmabuf_formats = false } })
    break
  end
end
