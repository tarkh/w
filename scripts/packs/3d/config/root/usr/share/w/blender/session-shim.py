# W integration for Blender — session shim of the `3d` W-Pack (managed, do not edit).
#
# BLENDER_SYSTEM_SCRIPTS reaches applications from the next login (env.d): the
# launcher starts apps in its own environment, which predates the pack. So that
# the FIRST Blender launch after `w-pack install 3d` is already W, setup-user.sh
# links this shim into the startup folder of the installed Blender version; it
# loads the W startup module only while that variable is missing, and is inert
# afterwards (the module then comes from the system scripts root itself).
import os
import sys

_STARTUP = "/usr/share/w/blender/scripts/startup"

if os.environ.get("BLENDER_SYSTEM_SCRIPTS") != os.path.dirname(_STARTUP) and os.path.isdir(_STARTUP):
    sys.path.append(_STARTUP)
    from w_integration import register, unregister
else:
    def register():
        pass

    def unregister():
        pass
