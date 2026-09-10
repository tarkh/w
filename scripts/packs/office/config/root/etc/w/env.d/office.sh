# W Linux — office bundle session env (managed by W-Packs, do not edit).
# Sourced by /etc/xdg/uwsm/env-hyprland at graphical-session-pre (see packs.md).
#
# Pin LibreOffice's VCL toolkit to gtk3. Unpinned, LO auto-detects its UI
# backend and may pick the Qt6 one on this system (qt6-base is installed for
# Quickshell), which costs documented Wayland scroll-lag and styles the suite
# through Kvantum instead of the W GTK theme. The gtk3 backend rides the
# w-style `gtk` axis (adw-gtk3 + W_GTK_* named colours), follows the
# `appearance` axis for dark mode, and LO's automatic icon theme pairs
# colibre/colibre_dark on a generic desktop — see pack-office.md.
#
# Outside a graphical session (bare SSH shell) this file is not sourced and LO
# falls back to auto-detection: a deliberate degradation, not a bug.
export SAL_USE_VCLPLUGIN=gtk3
