# w-mcp domain: audio — PipeWire/WirePlumber state (Tier 0, read-only).
# The "no sound" question is W's top support case; this grounds the diagnosis in
# the real graph instead of guessing. See package-audio.md / the w-audio skill.
from core import run, tool

DOMAIN = "w-audio"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_audio_status() -> str:
        """Audio state (PipeWire + WirePlumber). Shows the WirePlumber session
        manager status, the full node graph (`wpctl status` — default sink/source
        marked `*`, devices, streams), and the default sink/source volume + mute
        flag. Use this first to diagnose 'no sound': check WirePlumber is running,
        a default sink exists and is marked `*`, and it is not [MUTED] / at 0%."""
        parts = [
            "== WirePlumber (session manager) ==",
            run(["systemctl", "--user", "--no-pager", "is-active", "wireplumber"]),
            "\n== Graph (wpctl status) ==",
            run(["wpctl", "status"]),
            "\n== Default sink volume ==",
            run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]),
            "\n== Default source volume ==",
            run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]),
        ]
        return "\n".join(parts)
