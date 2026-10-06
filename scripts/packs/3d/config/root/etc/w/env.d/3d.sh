# W Linux — 3d bundle session env (managed by W-Packs, do not edit).
# Sourced by /etc/xdg/uwsm/env-hyprland at graphical-session-pre (see packs.md).
#
# An extra Blender system-scripts root, added to the bundled one: Blender
# registers its startup/w_integration.py on every launch — the W theme follower
# and the AI-bridge add-on sync (pack-3d.md). Unlike every per-user Blender path
# it does not carry the Blender version, so a Blender upgrade keeps it working.
# Until the next login a session shim covers the installing account
# (setup-user.sh); outside a graphical session Blender runs without W's
# integration.
export BLENDER_SYSTEM_SCRIPTS=/usr/share/w/blender/scripts
