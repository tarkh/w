# W Linux — virt bundle session env (managed by W-Packs, do not edit).
# Sourced by /etc/xdg/uwsm/env-hyprland at graphical-session-pre (see packs.md).
#
# Point virsh and virt-manager at the SYSTEM libvirt daemon (qemu:///system) by
# default, not the per-user session. The system daemon is the one this bundle
# enables (libvirtd.socket) and the one the `libvirt` group polkit rule governs;
# without this, `virsh` with no URI defaults to qemu:///session, which is a
# separate daemon with no default network and no group access.
export LIBVIRT_DEFAULT_URI="qemu:///system"
