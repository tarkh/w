# w-style module: obsidian (user-scope) — Obsidian markdown editor palette.
#
# Ships INSIDE the office W-Pack (source of truth); w-pack install drops this
# axis into the w-style modules.d drop-in root, w-pack remove takes it back.
# Core w-style carries no reference to Obsidian → the axis exists iff the
# bundle is installed: no pack, no axis, and `w-theme set` generates nothing
# (packs.md "bundle self-containment", pack-office.md).
#
# Obsidian is Electron — its look is driven by CSS custom properties, delivered
# per-vault as a "CSS snippet" (<vault>/.obsidian/snippets/*.css, enabled in
# Settings → Appearance → CSS snippets). Vault paths are user data with unknown
# locations, so the ONLY discovery channel is Obsidian's own registry
# ~/.config/obsidian/obsidian.json; this axis renders W's tokens into
# snippets/w.css for every vault it lists. The file is W's alone (Obsidian never
# writes into snippets/).
#
# appearance.json — where Obsidian records which snippets are enabled — gets ONE
# guarded write per vault under a three-state rule: no enabledCssSnippets key at
# all → W introduces it with "w" (enabled by default, jq-merge preserving every
# other key); "w" already present → nothing; key present without "w" → the
# user's own curation — including "had w and turned it off" (Obsidian keeps the
# key with an empty array, verified live) — and is NEVER touched, so the in-app
# toggle stays a real opt-out that no re-render overrides. The write is safe
# under a RUNNING Obsidian too (verified live): the app never re-reads the file,
# only writes its own in-memory state, and that state either already contains
# "w" (loaded from our write at vault open) or lacks the key altogether — in
# which case a rewrite merely returns the vault to "fresh", healed by the next
# render. It never manufactures a curated list, so no guard is needed; the one
# the axis used to carry (`pgrep -x obsidian`) matched nothing anyway — the
# Arch package runs under the system Electron and the process is "electron".
#
# Both .theme-dark and .theme-light carry the SAME values: a W theme has one
# appearance (the same call as the gtk twins), and Obsidian's "adaptive" base
# theme follows the system colour scheme — whichever mode it lands in, it reads
# the current W palette.
#
# LIVE once enabled: Obsidian detects saves of an enabled snippet and applies
# them without a restart, so `w-theme set` recolours a running Obsidian. Writes
# are in-place (same inode), the idiom that keeps Zed live.
#
# A vault created AFTER a render is reached by the registry watcher the bundle
# ships (w-obsidian-vaults.path → `w-style apply obsidian` on every write to
# obsidian.json, i.e. every vault create/open) — on a fresh install the first
# vault appears well after the login render, and without the watcher it would
# sit on Obsidian's default theme until the next login. The window that vault
# opened in still shows the default until the app restarts (Obsidian reads
# appearance.json at vault load only); the snippet is already listed, so a
# manual toggle applies it at once.
#
# As root this axis is a no-op: /etc/skel holds no vaults. Per-account renders
# happen at every login (env-hyprland → w-style apply user), immediately at
# bundle install (setup-user.sh) and on every registry change (the watcher).
# Band 400 = per-app GUI config.
DESC="Obsidian markdown editor palette"

OBSIDIAN_REGISTRY_REL=".config/obsidian/obsidian.json"

# <hex> → "r,g,b" for the rgba() composites (hover fills, selection, scrollbar).
_obs_rgb() {
  local h="${1#\#}"
  printf '%d,%d,%d' "$((16#${h:0:2}))" "$((16#${h:2:2}))" "$((16#${h:4:2}))"
}

render_user() {
  # Root render = skel prep, and there are no vaults in /etc/skel; live homes are
  # reached per account at login. Also avoids scanning root's own ~/.config.
  if [[ $EUID -eq 0 ]]; then
    echo "w-style: obsidian — root render is a no-op (vaults render per account at login)."
    return 0
  fi

  local theme_dir; theme_dir="$(w_userscope_theme_dir)"
  load_conf "$theme_dir"
  echo "w-style: rendering obsidian snippet..."

  # Vault discovery — Obsidian's registry: {"vaults":{"<id>":{"path":"…",…}}}.
  # No registry → this account never ran Obsidian → a friendly skip, not an
  # error: the pack is machine-wide, the app need not be everyone's.
  local reg="$HOME/$OBSIDIAN_REGISTRY_REL"
  if [[ ! -r "$reg" ]]; then
    echo "w-style: obsidian — no vault registry (~/$OBSIDIAN_REGISTRY_REL), skipping."
    return 0
  fi
  local -a vaults=()
  local v
  while IFS= read -r v; do
    [[ -n "$v" && -d "$v" ]] && vaults+=("$v")
  done < <(jq -r '.vaults[]?.path // empty' "$reg" 2>/dev/null)
  if (( ${#vaults[@]} == 0 )); then
    echo "w-style: obsidian — registry lists no vaults on disk, skipping."
    return 0
  fi

  local p_rgb o_rgb g_rgb d_rgb
  p_rgb="$(_obs_rgb "$W_PRIMARY")"
  o_rgb="$(_obs_rgb "$W_ON_SURFACE")"
  g_rgb="$(_obs_rgb "$W_TERM_ANSI_GREEN")"
  d_rgb="$(_obs_rgb "$W_DANGER")"

  local css
  css=$(cat <<EOF
/* W Linux — generated by the w-style axis 400-obsidian. Do not edit; the palette
   comes from the active theme's theme.conf. Enable once per vault:
   Settings → Appearance → CSS snippets → toggle "w". Once enabled, Obsidian
   hot-reloads this file, so every theme switch recolours it without a restart. */

.theme-dark, .theme-light {
    /* ── Core backgrounds — the W surface ramp ─────────────────────────── */
    --background-primary:         $W_APP_BG;
    --background-primary-alt:     $W_SURFACE_DIM;
    --background-secondary:       $W_SURFACE;
    --background-secondary-alt:   $W_SURFACE_VARIANT;

    /* ── Titlebar ───────────────────────────────────────────────────────── */
    --titlebar-background:         $W_SURFACE_DIM;
    --titlebar-background-focused: $W_SURFACE;
    --titlebar-text-color:         $W_ON_SURFACE;

    /* ── Borders & dividers (hairline = the faintest ink; focus = accent,
          the same "focused carries the brand" language as window borders) ── */
    --background-modifier-border:       $W_ON_SURFACE_FAINT;
    --background-modifier-border-focus: $W_PRIMARY;
    --background-modifier-border-hover:  $W_ON_SURFACE_VARIANT;

    /* ── Text ───────────────────────────────────────────────────────────── */
    --text-normal:    $W_ON_SURFACE;
    --text-muted:     $W_ON_SURFACE_VARIANT;
    --text-faint:     $W_ON_SURFACE_FAINT;
    --text-on-accent: $W_ON_PRIMARY;
    --text-selection: rgba($p_rgb, 0.30);

    /* ── Accent & interactive — fill and ink kept apart, as everywhere in W ── */
    --interactive-accent:       $W_PRIMARY;
    --interactive-accent-hover: $W_PRIMARY_CONTAINER;
    --interactive-accent-rgb:   $p_rgb;
    --text-accent:              $W_ON_SURFACE_ACCENT;
    --text-accent-hover:        $W_ON_SURFACE_VIVID;

    /* ── Hover & active modifiers ───────────────────────────────────────── */
    --background-modifier-hover:        rgba($o_rgb, 0.06);
    --background-modifier-active-hover: rgba($p_rgb, 0.15);
    --background-modifier-success:      rgba($g_rgb, 0.15);
    --background-modifier-error:        $W_DANGER_CONTAINER;
    --background-modifier-error-hover:  rgba($d_rgb, 0.40);

    /* ── Obsidian greyscale ramp (--color-base-XX) over the W ramp + text
          tones; adjacent slots share a value, the ramp has four real steps ── */
    --color-base-00:  $W_APP_BG;
    --color-base-05:  $W_SURFACE_DIM;
    --color-base-10:  $W_SURFACE_DIM;
    --color-base-20:  $W_SURFACE;
    --color-base-25:  $W_SURFACE;
    --color-base-30:  $W_SURFACE_VARIANT;
    --color-base-35:  $W_SURFACE_VARIANT;
    --color-base-40:  $W_ON_SURFACE_FAINT;
    --color-base-50:  $W_ON_SURFACE_VARIANT;
    --color-base-60:  $W_ON_SURFACE_VARIANT;
    --color-base-70:  $W_ON_SURFACE;
    --color-base-100: $W_ON_SURFACE_BRIGHT;

    /* ── Semantic colours — the ANSI hue wheel, the same roles the terminal
          and every other editor in W use ────────────────────────────────── */
    --color-red:    $W_TERM_ANSI_RED;
    --color-orange: $W_TERM_ANSI_BRIGHT_YELLOW;
    --color-yellow: $W_TERM_ANSI_YELLOW;
    --color-green:  $W_TERM_ANSI_GREEN;
    --color-cyan:   $W_TERM_ANSI_CYAN;
    --color-blue:   $W_TERM_ANSI_BLUE;
    --color-purple: $W_TERM_ANSI_MAGENTA;
    --color-pink:   $W_TERM_ANSI_BRIGHT_MAGENTA;

    /* ── Headings — accent as INK (contrast-safe), de-emphasising down the
          scale ──────────────────────────────────────────────────────────── */
    --h1-color: $W_ON_SURFACE_ACCENT;
    --h2-color: $W_ON_SURFACE_ACCENT;
    --h3-color: $W_ON_SURFACE_VIVID;
    --h4-color: $W_ON_SURFACE_VARIANT;
    --h5-color: $W_ON_SURFACE_VARIANT;
    --h6-color: $W_ON_SURFACE_FAINT;

    /* ── Links ───────────────────────────────────────────────────────────── */
    --link-color:            $W_ON_SURFACE_ACCENT;
    --link-color-hover:      $W_ON_SURFACE_VIVID;
    --link-external-color:   $W_TERM_ANSI_CYAN;
    --link-unresolved-color: $W_ON_SURFACE_FAINT;

    /* ── Tags ────────────────────────────────────────────────────────────── */
    --tag-color:            $W_ON_PRIMARY_CONTAINER;
    --tag-background:       $W_PRIMARY_CONTAINER;
    --tag-border-color:     $W_ON_SURFACE_ACCENT;
    --tag-color-hover:      $W_ON_PRIMARY;
    --tag-background-hover: $W_PRIMARY;

    /* ── Checkboxes ──────────────────────────────────────────────────────── */
    --checkbox-color:        $W_PRIMARY;
    --checkbox-color-hover:  $W_PRIMARY_CONTAINER;
    --checkbox-border-color: $W_ON_SURFACE_FAINT;
    --checkbox-marker-color: $W_ON_PRIMARY;

    /* ── Code blocks — the same roles that colour helix/zed syntax (one
          theme.conf colours every editor) ───────────────────────────────── */
    --code-background: $W_SURFACE;
    --code-normal:      $W_ON_SURFACE;
    --code-comment:     $W_ON_SURFACE_VARIANT;
    --code-function:    $W_TERM_ANSI_BLUE;
    --code-important:   $W_TERM_ANSI_RED;
    --code-keyword:     $W_PRIMARY;
    --code-operator:    $W_ON_SURFACE_VARIANT;
    --code-property:    $W_TERM_ANSI_YELLOW;
    --code-punctuation: $W_ON_SURFACE_VARIANT;
    --code-string:      $W_TERM_ANSI_GREEN;
    --code-tag:         $W_TERM_ANSI_RED;
    --code-value:       $W_TERM_ANSI_CYAN;

    /* ── Scrollbar ───────────────────────────────────────────────────────── */
    --scrollbar-thumb-bg:        rgba($o_rgb, 0.12);
    --scrollbar-active-thumb-bg: rgba($o_rgb, 0.25);
    --scrollbar-bg:              transparent;

    /* ── Inputs ──────────────────────────────────────────────────────────── */
    --input-shadow:       none;
    --input-shadow-hover: 0 0 0 2px $W_PRIMARY;

    /* ── Graph view ──────────────────────────────────────────────────────── */
    --graph-node:            $W_PRIMARY;
    --graph-node-unresolved: $W_ON_SURFACE_FAINT;
    --graph-node-focused:    $W_ON_SURFACE_VIVID;
    --graph-node-tag:        $W_TERM_ANSI_MAGENTA;
    --graph-node-attachment: $W_TERM_ANSI_YELLOW;
    --graph-line:            $W_ON_SURFACE_FAINT;
    --graph-background:      $W_APP_BG;
}

/* Active line highlight */
.cm-active {
    background-color: rgba($o_rgb, 0.04) !important;
}
EOF
)

  # In-place write (same inode) for every vault: the save-detection that makes
  # an enabled snippet live watches the file, and rename would swap the inode
  # out from under it. New file → plain create.
  #
  # Sentinel first: under `set -u` a typo'd token name kills the css command
  # substitution INSIDE its subshell, the assignment survives empty, and the
  # loop below would happily ship a blank file into every vault. Refuse to.
  if [[ -z "$css" || ! "$css" == *"--background-primary:"* ]]; then
    echo "w-style: obsidian — rendered CSS is empty/malformed (token typo?), refusing to write." >&2
    return 1
  fi
  for v in "${vaults[@]}"; do
    local target="$v/.obsidian/snippets/w.css"
    if [[ ! -d "$v/.obsidian/snippets" ]]; then
      mkdir -p "$v/.obsidian/snippets" || { echo "w-style: obsidian — cannot create snippets dir in $v, skipped." >&2; continue; }
    fi
    if printf '%s\n' "$css" >"$target"; then
      chmod 644 "$target" 2>/dev/null || true
      echo "w-style: obsidian — themed $(basename "$v")"
    else
      echo "w-style: obsidian — cannot write $target, skipped." >&2
    fi
  done

  # ── Guarded auto-enable (the one deliberate write into Obsidian's file) ────
  # Three states, one action — see the header. The key observation that makes
  # "curated" trustworthy: after a toggle-off Obsidian KEEPS the key with an
  # empty array, so "key exists" reliably means "a human has curated snippets
  # here", never "fresh". Missing/unreadable file → fresh. Runs whether or not
  # the app is open (header: why that is safe).
  local ap state
  for v in "${vaults[@]}"; do
    ap="$v/.obsidian/appearance.json"
    if [[ ! -f "$ap" ]]; then
      printf '%s\n' '{"enabledCssSnippets":["w"]}' >"$ap" \
        && chmod 644 "$ap" 2>/dev/null \
        && echo "w-style: obsidian — snippet enabled by default in $(basename "$v")"
      continue
    fi
    state="$(jq -r 'if ((.enabledCssSnippets // []) | index("w")) != null then "on"
                   elif has("enabledCssSnippets") then "curated"
                   else "fresh" end' "$ap" 2>/dev/null)" || state="err"
    case "$state" in
      on) ;;  # already enabled — the css refresh above is all it needs
      curated)
        echo "w-style: obsidian — $(basename "$v"): snippet list is user-curated, toggle is yours"
        ;;
      fresh)
        if jq '.enabledCssSnippets = ["w"]' "$ap" >"$ap.tmp" 2>/dev/null && mv -f "$ap.tmp" "$ap"; then
          echo "w-style: obsidian — snippet enabled by default in $(basename "$v")"
        else
          rm -f "$ap.tmp"
          echo "w-style: obsidian — cannot update $ap, skipped." >&2
        fi
        ;;
      *)
        echo "w-style: obsidian — $ap unreadable, skipped." >&2
        ;;
    esac
  done

  echo "w-style: obsidian done (snippet refreshed; enable state follows the three-state rule)."
}
