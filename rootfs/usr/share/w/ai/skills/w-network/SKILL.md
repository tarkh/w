---
name: w-network
description: >-
  How networking is managed on W Linux: NetworkManager for connections, the w-dns
  tool for DNS-over-TLS, the w-firewall tool for firewalld zones, and the bar's
  network block and tray applets. Load this for anything about Wi-Fi/ethernet
  connections, DNS privacy, the firewall, or the network status indicator.
sources:
  - path: .claude/library/security.md
    sha256: f406324ae9e0c67ff4c0e72a0439ad46f79368a92ae7ad58b928e69db0f3f486
  - path: .claude/library/quickshell-bar.md
    sha256: 172fcf47c0789b0b684968235fb741ff9c0de3cd09887d2a0648c5ba66c335ed
tools:
  - w_network_status
  - w_firewall_status
  - w_dns_status
  - w_dns_provider
  - w_dns_mode
  - w_firewall_zone
  - w_hostname_set
---

# W Network

Connections are managed by **NetworkManager**. DNS privacy and the firewall have their
own first-party `w-*` tools. The bar shows live status; heavy interaction happens through
tray applets and GUI editors.

## Connections (NetworkManager)

- CLI: `nmcli` (e.g. `nmcli device wifi list`, `nmcli device wifi connect <ssid>`,
  `nmcli connection show`).
- GUI editor: `nm-connection-editor` (this is W's connection GUI; the bar's network block
  left-click opens it).
- Tray applet: `nm-applet` runs in the tray (installed with the tray-applets module) and
  handles the interactive connection menu. Note: as an SNI/AppIndicator applet it exposes
  a single right-click menu. Bluetooth uses the same applets module (`blueman-applet` +
  `blueman-manager`).

## DNS privacy — `w-dns`

DNS runs through **systemd-resolved with DNS-over-TLS (DoT)**. The default provider is
**Quad9**, opportunistic mode, with a global routing domain so per-link DHCP/ISP DNS does
not shadow it.

- `w-dns status` — show current provider and mode.
- `w-dns list` — list available DoT providers (Quad9, Cloudflare, Mullvad, Google,
  AdGuard).
- `w-dns provider <name>` — switch provider.
- `w-dns on` — global encrypted DoT resolver; `w-dns strict` — strict DoT (require
  encryption; use when you know the network allows it); `w-dns off` — fall back to
  per-link DHCP/VPN DNS.
- `w-dns apply` — re-render after editing the config by hand.

The config is layered: W's resolver catalog and default selection live in
`/usr/share/w/defaults/dns.conf` (updates overwrite it, so new resolvers arrive on
their own), and this machine's choices in `/etc/w/dns.conf` — catalogs merge per key,
so a `DNS_<name>` added there sits beside the vendor ones and survives updates. Every
key is system-scope: a value in a user file is ignored, and the setter refuses to
write one there (one resolver per machine). On a machine that belongs to a fleet,
`/etc/w/policy.d/dns.conf` can pin the resolver or the DoT mode outright — then
`w-conf origin` reports layer `policy`, `w_dns_*` says so instead of prompting, and
there is no local workaround to offer.
`w-conf cat dns` shows the merged result with each value's origin. `w-dns` renders the actual
`resolved.conf.d/` drop-in and reloads resolved (no resolver interruption). DNS is a
single system-wide daemon, so there is no per-user DNS.

## Firewall — `w-firewall`

The firewall is **firewalld** (nftables backend), default-deny inbound. It integrates
with NetworkManager automatically. The default zone is **`home`** (allows inbound `ssh`
and mDNS); use **`public`** on untrusted networks (e.g. a café Wi-Fi on a laptop).

- `w-firewall status` — show the active default zone.
- `w-firewall home` — switch to the home zone.
- `w-firewall public` — switch to the public zone.

For detailed rules use raw `firewall-cmd` or the GUI **`firewall-config`** (which inherits
the W theme). Both zones always permit the `ssh` service (lockout guard); outbound is open
in all zones.

## Hostname

`hostnamectl` sets the machine name; W has no dedicated `w-hostname` CLI (Hub's
Network panel calls `hostnamectl` directly and mirrors the change into the
`/etc/hosts` `127.0.1.1` line). The AI's curated equivalent is `w_hostname_set`
(Tier 2, polkit prompt, on by default — reversible by setting it again).

## The bar's network block

The bar has a lightweight, read-only **network** block. It derives connection type from
the default route (ethernet / wifi / vpn / disconnected) and updates live. Left-click
opens `nm-connection-editor`. It does not manage connections itself — that is the applet's
job.
