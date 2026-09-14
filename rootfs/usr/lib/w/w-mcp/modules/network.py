# w-mcp domain: network — NetworkManager/DNS/firewall state (Tier 0) + the
# privileged DoT / firewall-zone / hostname actuation (Tier 2, via com.w.ai.actuate).
import re
from typing import Annotated, Literal

from core import _actuate, _disabled_msg, _tool_on, conf_policy_block, desc, run, tool

DOMAIN = "w-network"


def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_network_status() -> str:
        """Network state: NetworkManager general status, active connections, the
        default route, and the resolver."""
        parts = [
            "== NetworkManager ==",
            run(["nmcli", "-t", "general", "status"]),
            "\n== Active connections ==",
            run(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"]),
            "\n== Default route ==",
            run(["ip", "route", "get", "1.1.1.1"]),
        ]
        return "\n".join(parts)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_firewall_status() -> str:
        """firewalld zone and rule summary (via `w-firewall status`)."""
        return run(["w-firewall", "status"])

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_dns_status() -> str:
        """DNS-over-TLS provider and resolver state (via `w-dns status`)."""
        return run(["w-dns", "status"])

    # ── Tier 2 — privileged, actuated through polkit (com.w.ai.actuate) ──────
    @tool(mcp, domain=DOMAIN)
    def w_dns_provider(
        provider: Annotated[str, desc("catalog name: quad9, cloudflare, mullvad, google, adguard (see w_dns_status)")],
    ) -> str:
        """Switch the system DNS-over-TLS resolver (Tier 2: privileged; polkit
        prompt). Reversible."""
        if not _tool_on("DNS"):
            return _disabled_msg("w_dns_provider", "W_AI_TOOL_DNS")
        if not provider.strip():
            return "(provide a provider name; see w_dns_status or `w-dns list`)"
        blocked = conf_policy_block("dns", "PROVIDER", "The DNS resolver")
        return blocked or _actuate("dns-provider", provider.strip())

    @tool(mcp, domain=DOMAIN)
    def w_dns_mode(
        mode: Annotated[Literal["on", "strict", "off"], desc("on = opportunistic DoT; strict = DoT required, fails closed if the resolver is unreachable; off = plain DNS")],
    ) -> str:
        """Set the DNS-over-TLS enforcement mode (Tier 2: privileged; polkit
        prompt). Reversible; w_dns_provider changes *which* resolver."""
        if not _tool_on("DNS"):
            return _disabled_msg("w_dns_mode", "W_AI_TOOL_DNS")
        m = mode.strip().lower()
        if m not in ("on", "strict", "off"):
            return "(mode must be 'on', 'strict', or 'off')"
        blocked = conf_policy_block("dns", "DOT", "The DoT enforcement mode")
        return blocked or _actuate("dns-mode", m)

    @tool(mcp, domain=DOMAIN)
    def w_firewall_zone(
        zone: Annotated[Literal["home", "public"], desc("home = W baseline, inbound ssh + mdns; public = untrusted networks, inbound ssh only")],
    ) -> str:
        """Set the firewalld default zone (Tier 2: privileged; polkit prompt).
        Reversible."""
        if not _tool_on("FIREWALL"):
            return _disabled_msg("w_firewall_zone", "W_AI_TOOL_FIREWALL")
        z = zone.strip().lower()
        if z not in ("home", "public"):
            return "(zone must be 'home' or 'public')"
        return _actuate("firewall-zone", z)

    @tool(mcp, domain=DOMAIN)
    def w_hostname_set(
        hostname: Annotated[str, desc("letters/digits/hyphens, 1-63 chars, e.g. 'my-laptop'")],
    ) -> str:
        """Set the machine's hostname via hostnamectl, mirrored into /etc/hosts
        (Tier 2: privileged; polkit prompt). Reversible. Gated by
        W_AI_TOOL_HOSTNAME."""
        if not _tool_on("HOSTNAME"):
            return _disabled_msg("w_hostname_set", "W_AI_TOOL_HOSTNAME")
        h = hostname.strip()
        if not re.fullmatch(r"[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?", h):
            return "(hostname must be letters/digits/hyphens, 1-63 chars)"
        return _actuate("hostname-set", h)
