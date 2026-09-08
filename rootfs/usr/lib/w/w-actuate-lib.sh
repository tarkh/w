# w-actuate-lib.sh — W Linux privileged-actuation core (shared, sourced).
#
# The single security boundary on the OS side for privileged (Tier-2) actions,
# shared by every W actuation front-end:
#   • w-ai-actuate   — reached by the OS AI assistant (w-mcp Tier-2 tools)
#   • w-hub-actuate  — reached by the W Hub / Settings GUI (Quickshell tiles)
# Each front-end is a thin shim that runs, as root via pkexec + its own polkit
# action (com.w.ai.actuate / com.w.hub.actuate), `w_actuate_main <tag> "$@"`. The
# polkit action makes the polkit agent (w-authd) prompt the user (fingerprint / password);
# this core validates every argument against a fixed allowlist and audits every
# invocation to journald (authpriv, tag = the caller's own tag) with the caller uid,
# capability and arguments — so there is a record of every privileged thing done,
# and who fronted it. It deliberately does NOT consult ai.conf/hub.json toggles:
# those gate whether a front-end *offers* a capability; here we validate
# independently so even a hand-crafted pkexec call cannot smuggle arbitrary input
# past the arg checks. See ai-integration.md §3 and quickshell-hub.md.
#
# Exit codes (via w_actuate_main): 0 success · 1 runtime/validation error · 2 usage.

# pkexec hands us a minimal, safe environment, and what it hands over depends on
# the caller's — so the PATH the W tools (w-dns, w-firewall) are found on is set
# explicitly here rather than inherited. Since P9 they live in /usr/bin, which
# pkexec's own default already covers; the explicit value stays because "already
# covered by the default" is not the same promise as "we chose it".
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# The package-transaction seam (installer.md §5 layer 2). Every install/upgrade
# capability below runs through w_pac instead of bare pacman: this path is the
# NON-interactive one — the AI and the Hub reach it with nobody watching a
# terminal — so a mirror that stalls mid-download has to be retried against a
# different host here, or it surfaces to the user as "the assistant could not
# install that" with no cause attached. `CMD` is expanded in this very shell, so a
# sourced function is a valid entry (see w_actuate_main's dispatcher).
# shellcheck source=w-pac-lib.sh
source /usr/lib/w/w-pac-lib.sh

# A clean token: no shell metacharacters, spaces, or slashes.
w_actuate_ok_token() { [[ "$1" =~ ^[A-Za-z0-9@._+-]+$ ]]; }

# hostnamectl deliberately never touches /etc/hosts (systemd upstream treats it as a
# hand-edited file it can't safely interpret) — so mirror the change into the
# 127.0.1.1 line ourselves. That line's exact format is our own convention, written
# once by the installer (sys_hosts() in scripts/install/lib/system.sh); if a user
# hand-edited /etc/hosts away from it, the grep guard below just no-ops instead of
# guessing — worst case is a stale `sudo: unable to resolve host` hint, not a
# corrupted hosts file.
w_actuate_set_hostname() {
  local h="$1"
  hostnamectl set-hostname "$h" || return $?
  if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts 2>/dev/null; then
    # Match the installer's own spacing (sys_hosts() in scripts/install/lib/system.sh)
    # instead of tabs, so a live rename doesn't visually diverge from the file it wrote.
    sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1   ${h}.localdomain  ${h}/" /etc/hosts
  fi
}

# w_actuate_main <tag> <capability> [args...]
# Resolves the capability to a concrete allow-listed command, runs it, and audits
# both the request and the result under <tag>.
w_actuate_main() {
  local TAG="$1"; shift
  local CALLER="${PKEXEC_UID:-?}"   # the uid that invoked pkexec (set by pkexec)
  local cap="${1:-}"; shift || true

  local log die
  log() { logger -t "$TAG" -p authpriv.notice -- "$*" 2>/dev/null || true; }
  die() { echo "$TAG: $1" >&2; log "DENY cap=${cap:-?} uid=$CALLER reason=$1"; exit "${2:-1}"; }

  [[ -n "$cap" ]] || { echo "$TAG: usage: $TAG <capability> [args...]" >&2; exit 2; }
  log "REQUEST cap=$cap uid=$CALLER args=$*"

  local -a CMD
  case "$cap" in
    dns-provider)
      local p="${1:-}"; w_actuate_ok_token "$p" || die "invalid provider name"
      CMD=(w-dns provider "$p")
      ;;
    dns-mode)
      local m="${1:-}"
      case "$m" in on|strict|off) CMD=(w-dns "$m") ;; *) die "invalid dns mode (on|strict|off)";; esac
      ;;
    firewall-zone)
      local z="${1:-}"
      case "$z" in home|public) CMD=(w-firewall "$z") ;; *) die "invalid zone (home|public)";; esac
      ;;
    locale-set)
      local loc="${1:-}"; [[ "$loc" =~ ^[A-Za-z0-9@._-]+$ ]] || die "invalid locale name"
      CMD=(w-locale set "$loc")
      ;;
    timezone-set)
      # Timezone names contain slashes (Europe/Moscow), so w_actuate_ok_token (which
      # forbids /) is too strict — validate the zone shape here (w-time re-checks it
      # against `timedatectl list-timezones` before applying).
      local tz="${1:-}"
      [[ "$tz" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]] || die "invalid timezone name"
      CMD=(w-time set-zone "$tz")
      ;;
    ntp-toggle)
      local s="${1:-}"
      case "$s" in on|off) CMD=(w-time ntp "$s") ;; *) die "ntp state must be on or off";; esac
      ;;
    ntp-servers)
      local set="${1:-}"; [[ "$set" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid server-set name"
      CMD=(w-time servers "$set")
      ;;
    service-restart)
      local u="${1:-}"
      [[ "$u" =~ ^[A-Za-z0-9:_.@-]+\.(service|socket|timer|device|mount|automount|swap|target|path|slice|scope)$ ]] \
        || die "invalid unit name (must end in .service/.socket/.timer/...)"
      CMD=(systemctl restart "$u")
      ;;
    service-enable)
      local u="${1:-}" state="${2:-}"
      [[ "$u" =~ ^[A-Za-z0-9:_.@-]+\.(service|socket|timer|device|mount|automount|swap|target|path|slice|scope)$ ]] \
        || die "invalid unit name (must end in .service/.socket/.timer/...)"
      case "$state" in enable|disable) CMD=(systemctl "$state" --now "$u") ;; *) die "state must be enable or disable";; esac
      ;;
    logs-vacuum)
      local mode="${1:-}" v="${2:-}"
      case "$mode" in
        time) [[ "$v" =~ ^[0-9]+(s|min|h|d|w|month|y)$ ]] || die "invalid time span (e.g. 2w, 30d, 6month)" ;;
        size) [[ "$v" =~ ^[0-9]+(B|K|M|G|T)$ ]] || die "invalid size (e.g. 500M, 2G)" ;;
        *) die "mode must be time or size" ;;
      esac
      CMD=(journalctl "--vacuum-$mode=$v")
      ;;
    logs-retention)
      local days="${1:-}"
      [[ "$days" =~ ^[0-9]+$ ]] || die "retention must be a whole number of days"
      ((days >= 1 && days <= 3650)) || die "retention must be 1..3650 days"
      CMD=(w-logs keep "$days")
      ;;
    logs-limit)
      local size="${1:-}"
      [[ "$size" == "off" || "$size" =~ ^[0-9]+[KMG]$ ]] || die "size must be a number plus K/M/G (e.g. 500M) or 'off'"
      CMD=(w-logs limit "$size")
      ;;
    pacman-remove)
      (($#)) || die "no packages given"
      local pkg
      for pkg in "$@"; do w_actuate_ok_token "$pkg" || die "invalid package name: $pkg"; done
      # Removal is local work: no mirror is involved, so there is nothing for the
      # w_pac seam to retry against (same reasoning that keeps `pacman -U` out of
      # the landmines rule).
      CMD=(pacman -Rns --noconfirm "$@")
      ;;
    hostname-set)
      local h="${1:-}"
      [[ "$h" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || die "invalid hostname (letters/digits/hyphens, 1-63 chars)"
      CMD=(w_actuate_set_hostname "$h")
      ;;
    fwupd-refresh)
      CMD=(fwupdmgr refresh --force)
      ;;
    pacman-install)
      (($#)) || die "no packages given"
      local pkg
      for pkg in "$@"; do w_actuate_ok_token "$pkg" || die "invalid package name: $pkg"; done
      CMD=(w_pac -S --needed --noconfirm "$@")
      ;;
    pack-install)
      local b="${1:-}"; [[ "$b" =~ ^[a-z0-9-]+$ ]] || die "invalid bundle name"
      CMD=(w-pack install "$b")
      ;;
    monitor-greeter)
      # One validated dispatcher for the greeter's monitor layout (w-monitor greeter),
      # reached by the future Hub Displays panel's "Экран входа" tab. Re-validates
      # every field independently of w-monitor's own checks (server-side authority —
      # even a hand-crafted pkexec call can't smuggle a bad spec past this).
      local mg_sub="${1:-}"; shift || true
      case "$mg_sub" in
        sync)  (($#)) && die "monitor-greeter sync takes no arguments"; CMD=(w-monitor greeter sync) ;;
        reset) (($#)) && die "monitor-greeter reset takes no arguments"; CMD=(w-monitor greeter reset) ;;
        primary)
          local mgo="${1:-}"; [[ "$mgo" =~ ^[A-Za-z0-9@._-]+$ ]] || die "invalid output name"
          CMD=(w-monitor greeter primary "$mgo")
          ;;
        apply)
          (($#)) || die "no specs given"
          local mgspec
          for mgspec in "$@"; do
            [[ "$mgspec" =~ ^[A-Za-z0-9@._-]+:(([0-9]+x[0-9]+(@[0-9]+)?)|preferred):([0-9]+(\.[0-9]+)?|auto):(0|90|180|270):(right|left|above|below|auto):(on|off|primary)$ ]] \
              || die "invalid spec: $mgspec"
          done
          CMD=(w-monitor greeter apply "$@")
          ;;
        *) die "unknown monitor-greeter subcommand (sync|primary|apply|reset)" ;;
      esac
      ;;
    power-set)
      # One validated dispatcher for every root-domain power knob (w-power), reached by
      # the Hub Power panel and the AI's w_power_* tools. <key> <value>; each key maps to
      # a w-power subcommand with the value enum-checked here (server-side authority).
      local pk="${1:-}" pv="${2:-}" lidacts='suspend|lock|ignore|poweroff|hibernate'
      case "$pk" in
        mode)         [[ "$pv" =~ ^(laptop|desktop|auto)$ ]] || die "mode: laptop|desktop|auto";  CMD=(w-power mode "$pv") ;;
        auto)         [[ "$pv" =~ ^(on|off)$ ]] || die "auto: on|off";                            CMD=(w-power profile auto "$pv") ;;
        charge-limit) [[ "$pv" =~ ^[0-9]+$ ]] && ((pv <= 100)) || die "charge-limit: 0..100";      CMD=(w-power charge-limit "$pv") ;;
        power-key)    [[ "$pv" =~ ^(menu|poweroff|suspend|ignore)$ ]] || die "power-key: menu|poweroff|suspend|ignore"; CMD=(w-power power-key "$pv") ;;
        critical)     [[ "$pv" =~ ^(suspend|hibernate|poweroff|ignore)$ ]] || die "critical: suspend|hibernate|poweroff|ignore"; CMD=(w-power critical "$pv") ;;
        lid-battery)  [[ "$pv" =~ ^($lidacts)$ ]] || die "lid action: $lidacts"; CMD=(w-power lid bat "$pv") ;;
        lid-ac)       [[ "$pv" =~ ^($lidacts)$ ]] || die "lid action: $lidacts"; CMD=(w-power lid ac "$pv") ;;
        lid-docked)   [[ "$pv" =~ ^($lidacts)$ ]] || die "lid action: $lidacts"; CMD=(w-power lid docked "$pv") ;;
        # Idle cascade. These keys are USER-scope today (power.schema), so the Hub
        # and the CLI set them without any of this — the cap exists so the scope
        # declaration is genuinely authoritative: flip AC_LOCK to `system` in the
        # schema and the front-ends route here instead of breaking. Key shape:
        # idle-<ac|bat>-<lock|display|suspend|kbdlight>, value = seconds.
        # kbdlight is in the same family but is not a cascade link — it is an
        # independent "keyboard light goes dark" timer (see w-power's preset_idle).
        idle-*)
          local isrc ilink
          isrc="${pk#idle-}"; ilink="${isrc#*-}"; isrc="${isrc%%-*}"
          [[ "$isrc" =~ ^(ac|bat)$ ]] || die "idle source: ac|bat"
          [[ "$ilink" =~ ^(lock|display|suspend|kbdlight)$ ]] || die "idle link: lock|display|suspend|kbdlight"
          [[ "$pv" =~ ^[0-9]+$ ]] || die "idle: seconds must be a non-negative integer"
          CMD=(w-power idle "$isrc" "$ilink" "$pv")
          ;;
        *) die "unknown power key: $pk (mode|auto|charge-limit|power-key|critical|lid-battery|lid-ac|lid-docked|idle-<src>-<link>)" ;;
      esac
      ;;
    system-upgrade)
      # Full official-repo upgrade, non-interactive. AUR is intentionally NOT here:
      # yay must build as the user, and PKGBUILD review is a human step. snap-pac
      # auto-snapshots the transaction (rollback covered). A conflict pacman won't
      # auto-resolve aborts with a non-zero exit → the AI surfaces it to the user
      # instead of the tool hanging.
      (($#)) && die "system-upgrade takes no arguments"
      CMD=(w_pac -Syu --noconfirm)
      ;;
    apply-module)
      local mod="${1:-}"; [[ "$mod" =~ ^[a-z0-9-]+$ ]] || die "invalid module name"
      local apply="" c
      for c in /var/lib/w/src/scripts/apply.sh /mnt/w-src/scripts/apply.sh; do
        [[ -x "$c" ]] && { apply="$c"; break; }
      done
      [[ -n "$apply" ]] || die "apply.sh not found on this system"
      CMD=("$apply" "--$mod")
      ;;
    sync-update)
      # Edge-channel update: fetch → pre-snapshot home → git pull --ff-only →
      # selective apply.sh. w-sync itself no-ops with a clear message on a non-edge
      # (stable) system, and refuses (die) if it isn't.
      #
      # Two shapes, because the two front-ends differ in exactly one thing — whether
      # a human is watching a terminal:
      #   (no argument)  --yes: skip w-sync's confirmation and never auto-reboot,
      #                  only report. The AI path (w-mcp w_sync_update) has no stdin
      #                  and must not block on a prompt nobody can answer.
      #   interactive    no --yes: the Hub opens this inside w-term, so stdin IS a
      #                  live pty — the incoming-commit confirmation and the reboot
      #                  question survive, exactly as when the owner runs w-sync by
      #                  hand. Dropping them would be a silent UX regression.
      # It stays ONE capability (one audit line, one allowlist entry): the mode is a
      # fixed token, like ntp-toggle's on|off.
      local mode="${1:-}"
      if (($# > 1)); then die "sync-update takes at most one argument"; fi
      case "$mode" in
        "")          CMD=(w-sync update --yes) ;;
        interactive) CMD=(w-sync update) ;;
        *)           die "sync-update takes no argument or 'interactive'" ;;
      esac
      ;;
    secureboot)
      # Secure Boot on/off (Hub Security tile). Always interactive — enable/disable
      # end up asking for the LUKS passphrase once (w-secureboot re-seals the TPM2
      # disk auto-unlock against the new boot chain) — so the Hub always opens this
      # inside w-term for a live pty, the same idiom as sync-update's "interactive".
      local sb="${1:-}"
      case "$sb" in on) CMD=(w-secureboot enable) ;; off) CMD=(w-secureboot disable) ;; *) die "secureboot state must be on or off";; esac
      ;;
    kernel-set)
      # Switch the active kernel (Hub System → General). Long and network-bound —
      # it pulls the kernel + its paired headers and every DKMS module rebuilds
      # behind them — so the Hub runs this inside w-term for live output, the same
      # hybrid model as sync-update/secureboot. w_pac's mirror retry lives inside
      # w-kernel itself, which is where the transaction is.
      local kn="${1:-}"
      case "$kn" in zen|vanilla|lts) CMD=(w-kernel set "$kn") ;; *) die "kernel must be zen, vanilla or lts";; esac
      ;;
    kernel-harden)
      # Kernel hardening profile on/off (Hub System → Security). Instant actuation —
      # renaming three sysctl drop-ins, one `sysctl --system`, a cmdline edit and a
      # bootloader regen — so this one goes through runPrivileged, not a terminal.
      local kh="${1:-}"
      case "$kh" in on|off) CMD=(w-kernel harden "$kh") ;; *) die "hardening state must be on or off";; esac
      ;;
    snapshot-list)
      # Read-only: the Hub's Rollback tab lists the snapshots it can roll back
      # to (w-rollback list --porcelain). Deliberately argument-less — starting
      # a rollback is NOT a silent root call: w-rollback launch is the one
      # definition of "start a rollback from a graphical surface" (terminal,
      # human confirmation, reboot question on a real pty).
      (($#)) && die "snapshot-list takes no arguments"
      CMD=(w-rollback list --porcelain)
      ;;
    run)
      (($#)) || die "no command given"
      CMD=("$@")           # arbitrary command; gated by the polkit prompt + audited
      ;;
    *)
      die "unknown capability: $cap" 2
      ;;
  esac

  local rc
  set +e
  "${CMD[@]}"
  rc=$?
  set -e
  log "DONE cap=$cap uid=$CALLER rc=$rc"
  exit $rc
}
