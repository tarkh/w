#!/usr/bin/env bash
# telegram bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup telegram` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Two steps. (1) Render the bundle's telegram axis into THIS account right now,
# so the palette file exists before the first launch instead of waiting for the
# next login (which renders all axes anyway — this is the catch-up, and the
# second-account catch-up for a pack installed by someone else). (2) If Telegram
# has never been started for this account, seed its data dir (tdata-seed.py)
# so the FIRST launch already uses W's palette: Telegram keeps the applied theme
# inside its encrypted tdata, which has no external "apply" channel — but a
# tdata that does not exist yet can be written in its own format. An account
# whose Telegram already ran keeps its state untouched and applies the file
# once by hand (Chat settings); after that Telegram re-reads the file at every
# start and watches it live (pack-telegram.md). No root-only steps, so it works
# identically under rootless `w-pack setup`.
#
# Idempotent; best-effort. See pack-telegram.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# runuser inherits our cwd; move to one the account can read (packs.md).
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Drop to the account when we hold root; run directly when we already are them.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── 1. Render the telegram axis for this account ──────────────────────────────
# w-pack already rendered the freshly deployed axis as root (into /etc/skel —
# future accounts); this pass writes the palette into THIS account's home.
if [[ -d "$USER_HOME" ]] && command -v w-style >/dev/null; then
  info "Rendering the Telegram palette for $USER_NAME..."
  as_user w-style apply telegram \
    || warn "w-style apply telegram failed (renders at next login instead)."
else
  info "w-style not available yet — the telegram axis renders at next login."
fi

# ── 2. Seed tdata for a never-started Telegram ────────────────────────────────
# Guards, cheapest first: an initialised tdata (any settings{s,0,1}) means the
# account has history — never touched, its flow is the one click below; a
# running Telegram is about to write its own settings (it does so at first
# start, even on the sign-in screen), so seeding would only race it — the
# process is `Telegram` (the package's binary, not the package name). The header
# version must not exceed the installed app's (a newer header makes tdesktop
# skip the file), so it is read from pacman: M.m.p → M*1000000+m*1000+p.
tg_dir="$USER_HOME/.local/share/TelegramDesktop"
tg_theme="$tg_dir/w.tdesktop-theme"
seeded=0
if compgen -G "$tg_dir/tdata/settings[s01]" >/dev/null; then
  info "Telegram has run before for $USER_NAME — its data is left untouched."
elif pgrep -u "$USER_NAME" -x Telegram >/dev/null; then
  warn "Telegram is running — not seeding its data (quit it and run 'w-pack setup telegram')."
elif [[ ! -s "$tg_theme" ]]; then
  warn "No rendered palette at $tg_theme — not seeding (renders at next login)."
else
  ver="$(pacman -Q telegram-desktop 2>/dev/null | awk '{print $2}')"
  if [[ "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    appver=$(( BASH_REMATCH[1] * 1000000 + BASH_REMATCH[2] * 1000 + BASH_REMATCH[3] ))
    info "Seeding Telegram's data for $USER_NAME (first launch opens in W's palette)..."
    if as_user python3 "$BUNDLE_DIR/tdata-seed.py" --data-dir "$tg_dir" \
         --theme "$tg_theme" --version "$appver"; then
      seeded=1
    else
      warn "tdata seed failed — Telegram starts with its stock look; apply the file once by hand."
    fi
  else
    warn "Cannot read the telegram-desktop version from pacman ('$ver') — not seeding."
  fi
fi

# ── 3. What happens next ──────────────────────────────────────────────────────
if [[ $seeded == 1 ]]; then
  cat <<EOF

  Telegram is installed and W's palette for it is rendered to
    ~/.local/share/TelegramDesktop/w.tdesktop-theme

  Telegram will open in W's colours from its very first launch. From then on it
  is automatic: it re-reads the file at every start and watches it while
  running, so every \`w-theme set\` recolours it live.

EOF
else
  cat <<EOF

  W's palette for Telegram is rendered to
    ~/.local/share/TelegramDesktop/w.tdesktop-theme

  This account's Telegram has already run: its data is not touched, so pick the
  file once in the app, after signing in (Chat settings only exist with an
  account; the sign-in screen's Settings has no theme file option):

    Settings → Chat settings → Chat background → "Choose from file"
      → pick w.tdesktop-theme above → "Keep changes"

  From then on it is automatic: Telegram re-reads the file at every start and
  watches it while running, so every \`w-theme set\` recolours it live. Until
  you do this, Telegram still follows W's light/dark setting on its own
  built-in theme.

EOF
fi

info "telegram user setup complete for $USER_NAME."
exit 0
