# w-mcp domain: diagnostics — machine state, systemd, journald (Tier 0 read, plus a
# curated Tier-2 slice: restarting/enabling a named unit and vacuuming old journal
# entries are frequent, narrowly-validated, reversible actions — see ai-integration.md
# §2 "default-on tool" criterion.
import os
import re
import shutil
from pathlib import Path
from typing import Annotated, Literal

from core import (
    _actuate,
    _disabled_msg,
    _tool_on,
    conf_get,
    conf_policy_block,
    desc,
    kv_file,
    prompt,
    run,
    tool,
)

DOMAIN = "w-diagnostics"


def register(mcp):
    @prompt(mcp, domain=DOMAIN)
    def diagnose_system() -> str:
        """Guided health check: find what is wrong on this machine and propose fixes."""
        return (
            "Run a systematic, read-only health check of this W machine and report back:\n"
            "1. Call w_system_status for the overall snapshot (OS, kernel, reboot-needed, updates).\n"
            "2. Call w_service_status (no unit) to list failed systemd units.\n"
            "3. For each failed unit, call w_logs(unit=<name>, priority='err') to see why it failed.\n"
            "4. If nothing failed, scan w_logs(priority='err', lines=50) for recent system errors.\n"
            "Then summarize: what is healthy, what is broken, and the most likely fix for each "
            "problem. Change nothing — this is a diagnosis. Propose the next action and wait for the "
            "user's go-ahead before applying it."
        )

    @prompt(mcp, domain=DOMAIN)
    def investigate_symptom(topic: str) -> str:
        """Targeted investigation of a specific complaint (e.g. "wifi keeps
        dropping", "sound crackles", "theme looks half-applied") — point search
        instead of a general health check."""
        return (
            f"The user is complaining about: {topic!r}. Investigate narrowly instead of "
            "dumping whole logs:\n"
            "1. Pick 1-3 keywords/component names from the complaint (service name, "
            "subsystem, error word) and call w_logs(grep=<pattern>, since='1 hour ago') — "
            "widen `since` (e.g. 'today', 'boot') only if that comes back empty.\n"
            "2. If the complaint names or implies a systemd unit, also check "
            "w_service_status(unit=<name>) for its current state.\n"
            "3. If nothing turns up in the current boot, retry with since='-1 boot ago' or "
            "a wider window before concluding there is no trace.\n"
            "4. If the complaint is about theming looking half-applied, read the last line "
            "of ~/.local/state/w-style-apply.log instead (it names the stalled axis).\n"
            "Report only the relevant matches and your interpretation — not raw dumps. "
            "Propose a fix and wait for the user's go-ahead before changing anything."
        )

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_system_status() -> str:
        """Overall machine snapshot: OS identity, kernel, uptime, free disk space on
        /, pending updates, and whether a reboot is required. Start here to ground
        answers in reality."""
        lines = []
        rel = Path("/etc/os-release")
        if rel.is_file():
            kv = dict(
                l.split("=", 1)
                for l in rel.read_text().splitlines()
                if "=" in l and not l.startswith("#")
            )
            name = kv.get("PRETTY_NAME", kv.get("NAME", "?")).strip('"')
            # IMAGE_VERSION is the release (a git tag); W_BUILD_DATE is the day the
            # image was assembled and is empty unless this system came from a stamped
            # ISO. Both matter on a rolling distro — same release, different packages.
            ver = kv.get("IMAGE_VERSION", "").strip('"')
            built = kv.get("W_BUILD_DATE", "").strip('"')
            stamp = f" {ver}" + (f" (built {built})" if built else "") if ver else ""
            lines.append(f"OS: {name}{stamp} (ID={kv.get('ID','?').strip(chr(34))})")
        kernel = run(["uname", "-r"])
        lines.append(f"Kernel: {kernel}")
        # Reboot needed when the running kernel's module dir is gone (in-place upgrade
        # removed it) — same builtin check the updater uses, no root, zero false hits.
        reboot = not Path(f"/usr/lib/modules/{kernel}").is_dir()
        lines.append(f"Reboot required: {'yes' if reboot else 'no'}")
        total, _, free = shutil.disk_usage("/")
        lines.append(f"Disk (/): {free // 2**30}G free of {total // 2**30}G")
        lines.append(f"Uptime:{run(['uptime', '-p']).removeprefix('up')}")
        state = Path(os.path.expanduser("~/.local/state/w/updates.json"))
        if state.is_file():
            # A cached snapshot (last check); may be stale. Flag it so the model does
            # not report it as live — w_updates_check refreshes and returns current.
            lines.append("\nUpdate status (cached snapshot — run w_updates_check for a live count):")
            lines.append(state.read_text().strip())
        else:
            lines.append("\nUpdate status: not checked yet (run w_updates_check).")
        return "\n".join(lines)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_machine_profile() -> str:
        """Hardware and install-time configuration of this machine: hostname, CPU,
        GPU(s), disk encryption + bootloader, locale, keyboard layout, timezone, and
        update channel (edge/stable). Everything is read live on each call — nothing
        here is cached or remembered, so it can never go stale (unlike GPU swaps,
        keymap/locale/timezone changes, which would silently rot a stored fact)."""
        lines = [f"Hostname: {run(['hostname'])}"]

        cpu = "?"
        try:
            for line in Path("/proc/cpuinfo").read_text().splitlines():
                if line.startswith("model name"):
                    cpu = line.split(":", 1)[1].strip()
                    break
        except OSError:
            pass
        lines.append(f"CPU: {cpu}")

        gpu_out = run(["lspci", "-nn"])
        gpus = [
            re.sub(r"^\S+\s+\S.*?controller \[\w+\]: ", "", l, flags=re.IGNORECASE)
            for l in gpu_out.splitlines()
            if re.search(r"VGA compatible controller|3D controller|Display controller", l, re.IGNORECASE)
        ]
        lines.append(f"GPU: {'; '.join(gpus) if gpus else '?'}")

        encrypted = "is active" in run(["cryptsetup", "status", "cryptroot"])
        if encrypted:
            lines.append("Disk/boot: encrypted (LUKS2 + TPM2, Limine)")
        elif Path("/boot/grub/grub.cfg").is_file():
            lines.append("Disk/boot: plain (btrfs, GRUB)")
        else:
            lines.append("Disk/boot: plain (btrfs, bootloader unclear)")

        lines.append(f"Locale: {kv_file('/etc/locale.conf', 'LANG')}")
        lines.append(f"Keymap: {kv_file('/etc/vconsole.conf', 'KEYMAP')}")
        try:
            tz = os.readlink("/etc/localtime")
            lines.append(f"Timezone: {tz.split('zoneinfo/')[-1]}")
        except OSError:
            lines.append("Timezone: ?")
        # /etc/w is W's own layered namespace — read it through the shared reader,
        # never by hand (update-system.md: one reader, four dialects retired).
        lines.append(f"Update channel: {conf_get('update', 'CHANNEL', '?')}")

        return "\n".join(lines)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_service_status(
        unit: Annotated[str, desc("one unit to show; omit to list every failed unit")] = "",
    ) -> str:
        """systemd state (Tier 0, read-only): one unit's status, or all failed units."""
        if unit:
            return run(["systemctl", "status", "--no-pager", "--full", unit])
        return run(["systemctl", "--failed", "--no-pager", "--no-legend"])

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_logs(
        unit: Annotated[str, desc("scope to one systemd unit")] = "",
        lines: Annotated[int, desc("cap on returned lines; applies together with the filters")] = 50,
        priority: Annotated[str, desc("max level: emerg..debug or 0..7")] = "",
        since: Annotated[str, desc("journalctl time: '1 hour ago', 'today', 'boot', '2026-07-24 10:00'")] = "",
        until: Annotated[str, desc("journalctl time, same syntax as since")] = "",
        grep: Annotated[str, desc("case-insensitive regex on the message text — the key noun/error of the complaint, e.g. 'wifi|NetworkManager', 'ALSA|pipewire'")] = "",
    ) -> str:
        """Journald logs (Tier 0, read-only) — the point-search tool for a specific
        complaint, not just a tail. Prefer `grep` plus a narrow `since` over raising
        `lines`: a targeted match stays small and relevant, a bigger tail dumps
        noise. Bound the window before widening it."""
        cmd = ["journalctl", "--no-pager", "-n", str(max(1, min(lines, 1000)))]
        if unit:
            cmd += ["-u", unit]
        if priority:
            cmd += ["-p", priority]
        if since:
            cmd += ["--since", since]
        if until:
            cmd += ["--until", until]
        if grep:
            cmd += ["--grep", grep, "--case-sensitive=false"]
        return run(cmd, timeout=30)

    _UNIT_RE = re.compile(
        r"^[A-Za-z0-9:_.@-]+\.(service|socket|timer|device|mount|automount|swap|target|path|slice|scope)$"
    )

    @tool(mcp, domain=DOMAIN)
    def w_service_restart(
        unit: Annotated[str, desc("full unit name, e.g. 'sshd.service' — find a failed one with w_service_status")],
    ) -> str:
        """Restart one systemd unit (Tier 2: privileged; polkit prompt). Gated by
        W_AI_TOOL_MAINTAIN."""
        if not _tool_on("MAINTAIN"):
            return _disabled_msg("w_service_restart", "W_AI_TOOL_MAINTAIN")
        u = unit.strip()
        if not _UNIT_RE.fullmatch(u):
            return "(unit must be a full name like 'sshd.service' or 'foo.timer')"
        return _actuate("service-restart", u)

    @tool(mcp, domain=DOMAIN)
    def w_service_enable(
        unit: Annotated[str, desc("full unit name, e.g. 'sshd.service' or 'foo.timer'")],
        state: Literal["enable", "disable"],
    ) -> str:
        """Enable or disable one systemd unit, starting/stopping it now (Tier 2:
        privileged; polkit prompt). Gated by W_AI_TOOL_MAINTAIN."""
        if not _tool_on("MAINTAIN"):
            return _disabled_msg("w_service_enable", "W_AI_TOOL_MAINTAIN")
        u = unit.strip()
        if not _UNIT_RE.fullmatch(u):
            return "(unit must be a full name like 'sshd.service' or 'foo.timer')"
        st = state.strip().lower()
        if st not in ("enable", "disable"):
            return "(state must be 'enable' or 'disable')"
        return _actuate("service-enable", u, st)

    @tool(mcp, domain=DOMAIN)
    def w_logs_status() -> str:
        """Log retention overview: how many days W keeps logs and current disk usage
        across all three log nodes — the systemd journal, /var/log flat files
        (logrotate), and W's own logs under /var/log/w/. Read-only. Start here before
        changing retention or vacuuming, to see what is actually using space."""
        return run(["w-logs", "status"], timeout=30)

    @tool(mcp, domain=DOMAIN)
    def w_logs_retention(days: Annotated[int, desc("1..3650")]) -> str:
        """Set how many days W keeps logs, everywhere at once — journal, /var/log,
        /var/log/w/ (Tier 2: privileged; polkit prompt). The durable policy; for a
        one-off trim use w_logs_vacuum. Gated by W_AI_TOOL_MAINTAIN."""
        if not _tool_on("MAINTAIN"):
            return _disabled_msg("w_logs_retention", "W_AI_TOOL_MAINTAIN")
        if not (1 <= days <= 3650):
            return "(days must be between 1 and 3650)"
        blocked = conf_policy_block("logs", "RETENTION_DAYS", "Log retention")
        return blocked or _actuate("logs-retention", str(days))

    @tool(mcp, domain=DOMAIN)
    def w_logs_vacuum(
        value: Annotated[str, desc("how much to KEEP: mode=time → number + s/min/h/d/w/month/y (e.g. '2w', '30d'); mode=size → number + B/K/M/G/T (e.g. '500M')")],
        mode: Literal["time", "size"] = "time",
    ) -> str:
        """Trim old journald entries NOW to free disk (Tier 2: privileged; polkit
        prompt). One-off, journal only — the durable policy is w_logs_retention,
        and /var/log is cleaned by its own timers. Gated by W_AI_TOOL_MAINTAIN."""
        if not _tool_on("MAINTAIN"):
            return _disabled_msg("w_logs_vacuum", "W_AI_TOOL_MAINTAIN")
        m = mode.strip().lower()
        v = value.strip()
        if m == "time":
            if not re.fullmatch(r"[0-9]+(s|min|h|d|w|month|y)", v):
                return "(time value must be a number plus s/min/h/d/w/month/y, e.g. '2w')"
        elif m == "size":
            if not re.fullmatch(r"[0-9]+(B|K|M|G|T)", v):
                return "(size value must be a number plus B/K/M/G/T, e.g. '500M')"
        else:
            return "(mode must be 'time' or 'size')"
        return _actuate("logs-vacuum", m, v)
