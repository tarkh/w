---
name: w-datetime
description: >-
  Date, time, timezone and NTP on W Linux: the w-time CLI (set the timezone, the
  system clock and network time sync), the Hub "Date & Time" section, and the
  systemd-timesyncd server catalog (layered config, see w-conf). Load this for anything about
  the timezone, the system clock being wrong, enabling/disabling NTP, or which time
  servers are used.
sources:
  - path: .claude/library/w-time.md
    sha256: bc0836bd9c4164b4a3f4e692d93a2115b1fdc715db7d0a8c0eb1cece601eb373
tools:
  - w_time_status
  - w_timezone_set
  - w_ntp_set
---

# W Date & Time

Timezone, the system clock and NTP are fronted by the first-party **`w-time`** CLI (a
thin front over `timedatectl` + `systemd-timesyncd`), with matching UI in the W Hub's
top-level **Date & Time** section. `timedatectl` holds the live state (zone, clock, NTP
flag). Whether NTP is on is the user's/admin's call and W never flips it behind
their back — an apply re-renders which servers to use but leaves the on/off state
alone. Only the NTP *server set* is persisted, in W's layered config — the vendor
catalog in `/usr/share/w/defaults/time.conf` plus this machine's deviations in
`/etc/w/time.conf` (`w-conf cat time` shows the merged result). A fleet may pin the
server set through `/etc/w/policy.d/time.conf`; then the value's layer is `policy` and
the machine cannot change it locally.

## Read state

- `w-time status` — timezone, local + UTC time, RTC, whether NTP is on, and the selected
  server set. (AI tool: `w_time_status`, Tier-0.)
- `w-time list-zones` — every IANA timezone as `<offset>  <Zone>` (offset is ±HH:MM for
  today). Use it to find the exact zone name to pass to `set-zone`; `--porcelain` drops
  the formatting. E.g. `w-time list-zones | grep -i berlin`.

## Change it

- **Timezone**: `sudo w-time set-zone Europe/Moscow` (validated against the zone list).
  AI: `w_timezone_set` (Tier-2, polkit prompt; gated by `W_AI_TOOL_TIMEZONE`).
- **NTP on/off**: `sudo w-time ntp on|off`. AI: `w_ntp_set` (Tier-2; `W_AI_TOOL_NTP`).
- **Manual clock**: `sudo w-time set-time "2026-07-23 14:30:00"` — CLI only, and it
  **requires NTP off** first (`timedatectl` refuses otherwise). With NTP on this is never
  needed. There is no AI tool for it.
- **NTP servers**: `sudo w-time servers <name>` picks a set from the catalog in
  the catalog (add your own as `NTP_<name>="host ..."` in `/etc/w/time.conf` — it
  merges with the vendor entries instead of replacing them — then switch). Rare and
  catalog-bound — done via CLI or the Hub, not an AI tool.

## Notes

- The Hub path and the AI path share the same privileged dispatcher / polkit actions
  (`com.w.hub.actuate` / `com.w.ai.actuate`, caps `timezone-set` / `ntp-toggle` /
  `ntp-servers` in `w-actuate-lib.sh`).
- If the clock is wrong: check `w-time status` — usually NTP is off or timesyncd can't
  reach its servers. Turning NTP on (`w-time ntp on`) fixes most cases; a proxied/offline
  network may need a reachable server set.
- Changing the timezone takes effect immediately; running programs may need a restart to
  pick it up.
