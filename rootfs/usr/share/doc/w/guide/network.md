---
title: Network, DNS and the firewall
section: guide
order: 7
summary: Connecting to Wi-Fi and ethernet, the machine's name, encrypted DNS, and switching the firewall zone for an untrusted network.
sources:
  - path: .claude/library/security.md
    sha256: 3ec7c64f94e8053341ba52ded39be6b779d58ea1284c8db81f32c45f0697e12c
  - path: .claude/library/quickshell-bar.md
    sha256: 76dc9b56a2cdf3a879e737a653ea5bc330722c1eb346e64f917765823a1abf5c
---

**Hub → Network** holds the settings you change rarely and want to find without
hunting: the machine's name, the DNS resolver, and the firewall zone. Joining
an actual network is a job for the applet, one click away.

## Connections

Connections are managed by **NetworkManager**. There are three doors to it and
they all lead to the same place:

- the **network applet** in the tray — the interactive one, for picking a Wi-Fi
  network and typing its password;
- the **network block in the bar**, which shows what you are connected through
  and opens the connection editor when clicked;
- **Connections…** in this panel, which opens the same editor.

The bar's block is read-only by design: it tells you whether you are on
ethernet, Wi-Fi, a VPN or nothing at all, and leaves managing to the applet.

Bluetooth has its own tray applet next to it.

## Hostname

**Hostname** is the name this machine answers to on the network and shows in a
terminal prompt. Changing it asks for your password, and W keeps the system's
own host table in step for you.

## DNS

W resolves names through **systemd-resolved with DNS-over-TLS**, so the queries
your machine makes are encrypted rather than readable by anything between you
and the resolver. Two controls:

- **Provider** — Quad9 (the default), Cloudflare, Mullvad, Google or AdGuard.
- **Mode** — *on* is encrypted with a fallback if the network breaks TLS,
  *strict* refuses to resolve at all unless it can do so encrypted, and *off*
  hands DNS back to whatever the network or your VPN hands out.

*on* is the right default: it keeps encryption everywhere it is possible without
leaving you unable to open a page on a hotel network that mangles DNS. Choose
*strict* when you know the network behaves and you would rather fail than leak.

DNS is one setting for the whole machine — there is no per-user resolver. From a
terminal it is `w-dns`.

If every page takes ten seconds to even start loading while the connection itself
is fine, the encrypted resolver is what is stuck: `w-dns off` hands DNS back to
the network right away (unencrypted), and `w-dns status` shows what the machine
is currently using.

On a machine managed by someone else, either control may show *Set by site
policy*; then it is pinned centrally and there is no local way around it.

## Firewall

The firewall is default-deny inbound, and **Zone** picks how strict it is:

- **home** — the default. Allows incoming SSH and local network discovery, which
  is what you want on your own network for file sharing and printers.
- **public** — for café Wi-Fi, hotels, conferences and any other network you do
  not control.

Both zones always allow SSH, so switching cannot lock you out of a machine you
administer remotely. Outgoing connections are never blocked.

For anything finer than the two zones, the `firewall-config` application ships
with W and picks up its theme. From a terminal the zone is `w-firewall`.
