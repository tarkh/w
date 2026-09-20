#!/usr/bin/env bash
# graphics bundle — PER-USER layer. Run by `w-pack install` (for the installing
# account) and by `w-pack setup graphics` (for whoever asks, without root), with:
#   BUNDLE_NAME  BUNDLE_DIR  PACK_USER  PACK_HOME  PACK_AS_ROOT (1|0)
#
# Both AI bridges are per account, because both live in the account's home:
#
# 1. mcpinkscape — `uv tool install` into ~/.local/bin (the ddgs/trafilatura
#    idiom of ai-extra). Its config (~/.config/mcpinkscape.conf) is a manifest
#    row and is already seeded when this runs. The mcp.d drop-in the machine
#    layer registered becomes active for this account the moment the binary
#    exists (w-ai checks REQUIRES per launch).
#
# 3. Krita's theme: one key in kritarc pointing at the "W" colour scheme the
#    base qt axis already renders — seeded (manifest) or added while unset.
#
# 2. gimpmcp — a GIMP 3 plug-in + its MCP server half, unpacked from the pinned
#    upstream release into ~/.config/GIMP/3.0/plug-ins/gimpmcp/ (GIMP's plug-in
#    contract: <dir>/<dir>.py, executable). The release zip is pinned by
#    version AND sha256: a changed asset is refused, not installed. The server
#    runs on the system python with python-mcp (pkgs.txt) — no venv, no pip.
#
# Network is expected here (PyPI + GitHub) and may legitimately be absent; each
# step degrades with a named warning and the retry command. Idempotent;
# best-effort. See pack-graphics.md.

set -uo pipefail   # NOT -e: keep going on non-fatal steps

info() { echo -e "  \033[1;35m->\033[0m $*"; }
warn() { echo -e "  \033[1;33mWARN:\033[0m $*" >&2; }

USER_NAME="${PACK_USER:?}"
USER_HOME="${PACK_HOME:?}"
AS_ROOT="${PACK_AS_ROOT:-0}"

# Pinned upstream release of the GIMP bridge (Shriinivas/gimpmcp, AGPL-3.0).
GIMPMCP_VERSION="v1.0.0"
GIMPMCP_URL="https://github.com/Shriinivas/gimpmcp/releases/download/${GIMPMCP_VERSION}/gimpmcp-plugin.zip"
GIMPMCP_SHA256="5e02c660b639d5b946b072f3799bb27273ae010f3fa46f5ebbbc1e4375cec033"
PLUGIN_DIR="$USER_HOME/.config/GIMP/3.0/plug-ins/gimpmcp"

# runuser inherits our cwd; if it is a root-only dir (e.g. /root over sudo/ssh, or
# a service dir at firstboot) the target user cannot chdir there and any spawned
# child fails with EACCES before execve.
cd "$USER_HOME" 2>/dev/null || cd /tmp || true

# Drop to the account when we hold root; run directly when we already are them.
# HOME is passed explicitly — runuser keeps the caller's environment, and uv
# would otherwise install the tool into /root/.local/bin.
as_user() {
  if [[ "$AS_ROOT" == 1 ]]; then runuser -u "$USER_NAME" -- env HOME="$USER_HOME" "$@"
  else "$@"; fi
}

# ── 1. Inkscape MCP server (uv tool) ─────────────────────────────────────────
if command -v uv >/dev/null; then
  info "Installing mcpinkscape for $USER_NAME (uv tool install)..."
  as_user uv tool install mcpinkscape \
    || warn "uv tool install mcpinkscape failed (offline? retry: w-pack setup graphics)"
else
  warn "uv not found — install the 'uv' module first (apply.sh --uv). Skipping mcpinkscape."
fi
# The seeded document root says ~/Pictures, but the account's Pictures folder is
# whatever xdg-user-dirs named it in the user's language (~/Изображения on a
# Russian system). Rewrite the seed value only — a root the user chose is theirs.
# Renames after this point are followed by the w-userdirs hook this bundle ships.
MCPI_CONF="$USER_HOME/.config/mcpinkscape.conf"
if [[ -f "$MCPI_CONF" ]] && grep -q '"document_root": "~/Pictures/mcpinkscape"' "$MCPI_CONF"; then
  pics="$(as_user xdg-user-dir PICTURES 2>/dev/null || true)"
  if [[ -n "$pics" && "$pics" != "$USER_HOME" && "$pics" != "$USER_HOME/Pictures" ]]; then
    as_user sed -i "s|\"document_root\": \"~/Pictures/mcpinkscape\"|\"document_root\": \"~${pics#"$USER_HOME"}/mcpinkscape\"|" "$MCPI_CONF"
    info "mcpinkscape documents: ${pics/#"$USER_HOME"/~}/mcpinkscape"
  fi
fi

# ── 2. GIMP MCP bridge (plug-in + server, pinned release) ────────────────────
if [[ -f "$PLUGIN_DIR/gimpmcp.py" && -f "$PLUGIN_DIR/gimpmcp/gimp_mcp_server.py" ]]; then
  info "GIMP MCP bridge already installed for $USER_NAME ($PLUGIN_DIR)."
else
  info "Installing the GIMP MCP bridge (gimpmcp $GIMPMCP_VERSION) for $USER_NAME..."
  tmp="$(as_user mktemp -d)"
  if as_user curl -fsSL --retry 3 -o "$tmp/gimpmcp.zip" "$GIMPMCP_URL"; then
    if [[ "$(sha256sum "$tmp/gimpmcp.zip" | cut -d' ' -f1)" == "$GIMPMCP_SHA256" ]]; then
      as_user install -d "$(dirname "$PLUGIN_DIR")"
      # The zip's top-level dir IS the plug-in dir (gimpmcp/gimpmcp.py + gimpmcp/gimpmcp/…).
      if as_user bsdtar -xf "$tmp/gimpmcp.zip" -C "$(dirname "$PLUGIN_DIR")"; then
        as_user chmod 755 "$PLUGIN_DIR/gimpmcp.py"     # GIMP loads only executable plug-ins
        info "GIMP MCP bridge installed into $PLUGIN_DIR"
      else
        warn "could not unpack the GIMP MCP bridge (retry: w-pack setup graphics)"
      fi
    else
      warn "gimpmcp-plugin.zip checksum mismatch — upstream asset changed; NOT installed (see pack-graphics.md)"
    fi
  else
    warn "could not download gimpmcp $GIMPMCP_VERSION (offline? retry: w-pack setup graphics)"
  fi
  rm -rf "$tmp"
fi

# ── 3. Krita theme → W (guarded) ─────────────────────────────────────────────
# Krita keeps its theme in ~/.config/kritarc [theme] Theme=<scheme name>; "W" is
# the colour scheme the W qt axis renders (~/.local/share/color-schemes/W.colors).
# A kritarc that does not exist was just seeded from the manifest. One that
# exists (Krita ran before the pack) gets the key only while it has NONE —
# a theme the user picked themselves is their choice and stays (the same
# three-state rule the office bundle applies to Obsidian's snippet switch).
kritarc="$USER_HOME/.config/kritarc"
if [[ -f "$kritarc" ]]; then
  # The key is looked for inside [theme] only — kritarc is one INI with dozens
  # of sections, and a Theme= elsewhere would be a different setting.
  current="$(awk '/^\[/{s=($0=="[theme]")} s && /^Theme=/{sub(/^Theme=/,""); print; exit}' "$kritarc")"
  if [[ -n "$current" ]]; then
    info "Krita theme: already set ($current) — left alone."
  else
    # Add the key inside an existing [theme] section, or append the section.
    if grep -qx '\[theme\]' "$kritarc"; then
      as_user sed -i '/^\[theme\]$/a Theme=W' "$kritarc"
    else
      as_user sh -c 'printf "\n[theme]\nTheme=W\n" >> "$1"' _ "$kritarc"
    fi
    info "Krita theme → W (kritarc [theme] Theme=W; Krita applies it at its next start)."
  fi
else
  warn "kritarc: missing (the manifest seed did not land?) — Krita keeps its default theme"
fi

# ── Offline verification ─────────────────────────────────────────────────────
info "Verifying the graphics user layer for $USER_NAME (offline)..."
[[ -x "$USER_HOME/.local/bin/mcpinkscape" ]] && info "mcpinkscape: OK" || warn "mcpinkscape: not found in ~/.local/bin"
[[ -f "$USER_HOME/.config/mcpinkscape.conf" ]] && info "mcpinkscape.conf: OK" || warn "mcpinkscape.conf: missing"
[[ -x "$PLUGIN_DIR/gimpmcp.py" ]] && info "GIMP MCP plug-in: OK" || warn "GIMP MCP plug-in: not installed"

info "The AI assistant (w-ai) sees both servers from its next launch; the GIMP"
info "bridge answers only while GIMP runs with Filters → Development → MCP D-Bus - Start."
info "graphics user setup complete for $USER_NAME."
exit 0
