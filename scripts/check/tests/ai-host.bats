#!/usr/bin/env bats
# ai-host.bats — w-ai's host contract: the pure resolvers that decide WHICH
# provider a host authenticates with and WHETHER W has to hand it a key.
#
# This is the layer where a mistake is expensive rather than merely wrong: with
# ANTHROPIC_API_KEY exported, Claude Code silently bills the API instead of the
# user's subscription. So the regression guarded here is not "the function
# returns the right string" but "a subscription profile exports nothing".
#
# w-ai is source-guarded (BASH_SOURCE vs $0) and takes W_CONF_LIB, the same pair
# w-conf carries — so this needs no W installation on the machine.

load helpers

setup() {
  W_CONF_LIB="$REPO/rootfs/usr/lib/w/w-conf-lib.sh"
  export W_CONF_LIB
  source "$REPO/rootfs/usr/bin/w-ai"
  # -u and pipefail off, -e deliberately ON: bats reports a failed assertion through
  # errexit, so `set +e` here would make every test in the file pass regardless.
  set +u; set +o pipefail

  # Resolve presets out of the repo, with no user overlay in the way.
  SYS_ROOT="$REPO/rootfs/usr/share/w/ai"
  USER_ROOT="$BATS_TEST_TMPDIR/absent"

  # Auth stamps and the generated user plugin land in the test's own tmpdir, so
  # neither this suite's caching tests nor a stray wrapper touch the real ones.
  CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"

  # The vendor provider catalog, as load_conf would have materialised it.
  PROVIDER_ENV_openrouter=OPENROUTER_API_KEY
  PROVIDER_ENV_anthropic=ANTHROPIC_API_KEY
  PROVIDER_ENV_openai=OPENAI_API_KEY
  PROVIDER_ENV_google=GOOGLE_API_KEY
  PROVIDER_ENV_ollama=
  PROVIDER_ENV_subscription=
}

# ── The contract loads at all ────────────────────────────────────────────────
@test "host_field: reads every shipped host's manifest" {
  [[ "$(host_field goose BIN)"    == goose    ]]
  [[ "$(host_field local BIN)"    == goose    ]]
  [[ "$(host_field claude BIN)"   == claude   ]]
  [[ "$(host_field codex BIN)"    == codex    ]]
  [[ "$(host_field opencode BIN)" == opencode ]]
}

@test "host_field: a missing host yields empty, not an error" {
  run host_field nosuchhost BIN
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "known_host: only shipped hosts are known" {
  known_host claude
  ! known_host nosuchhost
}

@test "host manifests: only goose-backed hosts require a MODEL" {
  [[ "$(host_field goose    NEEDS_MODEL)" == yes ]]
  [[ "$(host_field local    NEEDS_MODEL)" == yes ]]
  [[ "$(host_field claude   NEEDS_MODEL)" == no  ]]
  [[ "$(host_field codex    NEEDS_MODEL)" == no  ]]
  [[ "$(host_field opencode NEEDS_MODEL)" == no  ]]
}

@test "host manifests: recipes stay a goose capability" {
  [[ "$(host_field goose    CAPABILITIES)" == *recipes* ]]
  [[ "$(host_field local    CAPABILITIES)" == *recipes* ]]
  [[ "$(host_field claude   CAPABILITIES)" != *recipes* ]]
  [[ "$(host_field opencode CAPABILITIES)" != *recipes* ]]
}

# ── effective_provider: closed AUTH_MODES lists ──────────────────────────────
@test "effective_provider: an open list (goose) passes PROVIDER through" {
  [[ "$(effective_provider goose openrouter)" == openrouter ]]
  [[ "$(effective_provider goose anthropic)"  == anthropic  ]]
  [[ -z "$(effective_provider goose '')" ]]
}

@test "effective_provider: local always resolves to ollama" {
  [[ "$(effective_provider local openrouter)" == ollama ]]
  [[ "$(effective_provider local '')"         == ollama ]]
}

@test "effective_provider: claude defaults to its own subscription" {
  [[ "$(effective_provider claude '')"           == subscription ]]
  [[ "$(effective_provider claude subscription)" == subscription ]]
}

@test "effective_provider: claude honours an explicit API provider" {
  [[ "$(effective_provider claude anthropic)" == anthropic ]]
}

@test "effective_provider: codex defaults to its own subscription, honours openai" {
  [[ "$(effective_provider codex '')"       == subscription ]]
  [[ "$(effective_provider codex openai)"   == openai ]]
}

# OpenCode is the one host with BOTH an open AUTH_MODES (goose-like — any
# models.dev provider) and a native login (claude/codex-like — its own Zen
# subscription). Unlike claude/codex, there is no closed-list fallback: a
# provider W's own catalog has never heard of (mistral, groq, …) passes
# through unchanged instead of collapsing to "subscription" — the user is
# expected to have set it up directly in OpenCode itself (see host.conf).
@test "effective_provider: opencode (open list) passes any provider through, including its own subscription" {
  [[ "$(effective_provider opencode subscription)" == subscription ]]
  [[ "$(effective_provider opencode anthropic)"     == anthropic    ]]
  [[ "$(effective_provider opencode mistral)"       == mistral      ]]
  [[ -z "$(effective_provider opencode '')" ]]
}

# A profile copied from a goose one carries PROVIDER=openrouter. Falling back to
# the first AUTH_MODE (rather than passing it through) is what keeps `w-ai
# status` and the Hub from claiming an OpenRouter key is missing for Claude Code.
@test "effective_provider: an inherited foreign provider falls back, not through" {
  [[ "$(effective_provider claude openrouter)" == subscription ]]
  [[ "$(effective_provider codex  openrouter)" == subscription ]]
}

# ── The billing guard ────────────────────────────────────────────────────────
@test "provider_declared: distinguishes 'declared empty' from 'absent'" {
  provider_declared ollama          # declared, empty
  provider_declared subscription    # declared, empty
  provider_declared anthropic
  ! provider_declared nosuchprovider
}

@test "provider_needs_key: only providers with an env var need one" {
  provider_needs_key openrouter
  provider_needs_key anthropic
  ! provider_needs_key ollama
  ! provider_needs_key subscription
  ! provider_needs_key ''
}

@test "export_provider_key: a subscription exports NOTHING (API-billing guard)" {
  unset ANTHROPIC_API_KEY
  run export_provider_key subscription
  [ "$status" -eq 0 ]
  [ -z "$output" ]                  # not even a "no API key in the keyring" nag
  export_provider_key subscription
  [ -z "${ANTHROPIC_API_KEY:-}" ]
}

@test "export_provider_key: ollama exports nothing either" {
  run export_provider_key ollama
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "export_provider_key: never clobbers a key already in the environment" {
  ANTHROPIC_API_KEY=preset export_provider_key anthropic
  [[ "$(ANTHROPIC_API_KEY=preset; export_provider_key anthropic; echo "$ANTHROPIC_API_KEY")" == preset ]]
}

@test "export_provider_key: an undeclared provider is reported, not silent" {
  run export_provider_key nosuchprovider
  [[ "$output" == *"no PROVIDER_ENV_nosuchprovider"* ]]
}

# ── ai_ready: contract-driven readiness ──────────────────────────────────────
# A missing binary must be caught here, before the Super+W palette opens a
# terminal on a CLI that isn't installed.
@test "ai_ready: an unknown host is bad-host" {
  run ai_ready nosuchhost
  [ "$status" -eq 1 ]
  [[ "$output" == bad-host ]]
}

@test "ai_ready: a missing host binary is no-host-bin" {
  # A host whose BIN cannot exist on PATH.
  USER_ROOT="$BATS_TEST_TMPDIR/overlay"
  mkdir -p "$USER_ROOT/hosts/ghost"
  cat > "$USER_ROOT/hosts/ghost/host.conf" <<'EOF'
BIN="w-ai-no-such-binary"
AUTH_MODES="subscription"
AUTH_NATIVE="subscription"
NEEDS_MODEL="no"
EOF
  run ai_ready ghost
  [ "$status" -eq 1 ]
  [[ "$output" == no-host-bin ]]
}

@test "ai_ready: a provider-native host with a failing AUTH_CHECK is not-logged-in" {
  USER_ROOT="$BATS_TEST_TMPDIR/overlay"
  mkdir -p "$USER_ROOT/hosts/ghost"
  cat > "$USER_ROOT/hosts/ghost/host.conf" <<'EOF'
BIN="true"
AUTH_MODES="subscription"
AUTH_NATIVE="subscription"
AUTH_CHECK="false"
NEEDS_MODEL="no"
EOF
  run ai_ready ghost
  [ "$status" -eq 1 ]
  [[ "$output" == not-logged-in ]]
}

# "We can't tell" must never harden into "not signed in", or a renamed upstream
# subcommand would block the assistant entirely.
@test "ai_ready: no AUTH_CHECK means logged in, never blocked" {
  USER_ROOT="$BATS_TEST_TMPDIR/overlay"
  mkdir -p "$USER_ROOT/hosts/ghost"
  cat > "$USER_ROOT/hosts/ghost/host.conf" <<'EOF'
BIN="true"
AUTH_MODES="subscription"
AUTH_NATIVE="subscription"
AUTH_CHECK=""
NEEDS_MODEL="no"
EOF
  run ai_ready ghost
  [ "$status" -eq 0 ]
}

@test "ai_ready: NEEDS_MODEL=no does not demand a MODEL" {
  USER_ROOT="$BATS_TEST_TMPDIR/overlay"
  mkdir -p "$USER_ROOT/hosts/ghost"
  cat > "$USER_ROOT/hosts/ghost/host.conf" <<'EOF'
BIN="true"
AUTH_MODES="subscription"
AUTH_NATIVE="subscription"
NEEDS_MODEL="no"
EOF
  MODEL=""
  run ai_ready ghost
  [ "$status" -eq 0 ]
}

@test "ai_ready: NEEDS_MODEL=yes with an empty MODEL is no-model" {
  USER_ROOT="$BATS_TEST_TMPDIR/overlay"
  mkdir -p "$USER_ROOT/hosts/ghost"
  cat > "$USER_ROOT/hosts/ghost/host.conf" <<'EOF'
BIN="true"
AUTH_MODES="ollama"
NEEDS_MODEL="yes"
EOF
  MODEL=""
  run ai_ready ghost
  [ "$status" -eq 1 ]
  [[ "$output" == no-model ]]
}

# ── A MODEL pin belongs to the profile's own host ────────────────────────────
# Caught on the VM: `w-ai --host claude` from a goose/openrouter profile reported
# (and would have passed) MODEL=minimax/minimax-m3 — a model id Claude Code has
# never heard of. Where MODEL is optional, a pin left by a profile for a different
# host is dropped; where the host truly needs one (goose), it is still carried,
# because dropping it would turn the override into a guaranteed no-model failure.
_model_for_launch() {   # mirrors the guard in launch_host's claude branch
  local host="$1"
  [[ -n "${MODEL:-}" && "$host" == "${HOST_CONFIGURED:-$host}" ]] && echo "$MODEL"
}

@test "MODEL pin: not carried to an overridden optional-model host" {
  HOST_CONFIGURED=goose MODEL=minimax/minimax-m3
  [ -z "$(_model_for_launch claude)" ]
}

@test "MODEL pin: honoured when the profile is about that host" {
  HOST_CONFIGURED=claude MODEL=opus
  [[ "$(_model_for_launch claude)" == opus ]]
}

# ── The shipped profile ──────────────────────────────────────────────────────
@test "profiles/claude.conf: subscription host, no model pinned" {
  local f="$REPO/rootfs/usr/share/w/ai/profiles/claude.conf"
  grep -qx 'HOST=claude' "$f"
  grep -qx 'PROVIDER=subscription' "$f"
  grep -qx 'MODEL=' "$f"
}

@test "profiles/codex.conf: subscription host, no model pinned" {
  local f="$REPO/rootfs/usr/share/w/ai/profiles/codex.conf"
  grep -qx 'HOST=codex' "$f"
  grep -qx 'PROVIDER=subscription' "$f"
  grep -qx 'MODEL=' "$f"
}

@test "profiles/opencode.conf: subscription host, no model pinned" {
  local f="$REPO/rootfs/usr/share/w/ai/profiles/opencode.conf"
  grep -qx 'HOST=opencode' "$f"
  grep -qx 'PROVIDER=subscription' "$f"
  grep -qx 'MODEL=' "$f"
}

# ── The Claude Code preset the launcher passes as flags ──────────────────────
@test "claude preset: the plugin's skills resolve to W's shipped skills" {
  local link="$REPO/rootfs/usr/share/w/ai/hosts/claude/plugin/skills"
  [ -L "$link" ]
  [[ "$(readlink -f "$link")" == "$(readlink -f "$REPO/rootfs/usr/share/w/ai/skills")" ]]
  [ -f "$link/w-overview/SKILL.md" ]
}

@test "claude preset: mcp.json registers w-mcp under its plain name" {
  local f="$REPO/rootfs/usr/share/w/ai/hosts/claude/mcp.json"
  python3 -c "
import json, sys
d = json.load(open('$f'))
assert list(d['mcpServers']) == ['w-mcp'], d
assert d['mcpServers']['w-mcp']['command'] == 'w-mcp', d
"
}

@test "claude preset: the plugin manifest is valid JSON with a stable name" {
  python3 -c "
import json
d = json.load(open('$REPO/rootfs/usr/share/w/ai/hosts/claude/plugin/.claude-plugin/plugin.json'))
assert d['name'] == 'w', d
"
}

# ── The Codex preset the launcher passes as flags ────────────────────────────
# Codex takes no config file for one run, so both layers ride `-c key=value`,
# and the identity layer is AGENTS.md itself as a TOML string. The escaping is
# what a real TOML parser has to accept back, byte for byte — a stray quote
# would otherwise turn the whole identity into a parse error (or, worse, into
# a literal string with the quotes still on).
@test "codex preset: installed by the vendor's own installer, per user" {
  [[ "$(host_field codex INSTALL_CMD)" == *chatgpt.com/codex/install.sh* ]]
  [[ "$(host_field codex INSTALL_SCOPE)" == user ]]
  [[ "$(host_field codex AUTH_CHECK)" == "codex login status" ]]
}

@test "codex preset: the manual config.toml preset is gone — flags replaced it" {
  [ ! -e "$REPO/rootfs/usr/share/w/ai/hosts/codex/config.toml" ]
  [ -f "$REPO/rootfs/usr/share/w/ai/hosts/codex/README.md" ]
}

# ── The OpenCode preset the launcher passes as flags ─────────────────────────
# OpenCode takes no config file for one run either, but unlike Codex it has a
# real env-var config layer (OPENCODE_CONFIG_CONTENT): one inline-JSON blob
# covers actions (mcp), approval (permission.mcp) and identity (instructions,
# a PATH — OpenCode reads AGENTS.md itself, so this only adds to that, never
# replaces it) instead of three separate `-c key=value` flags.
@test "opencode preset: installed by the vendor's own installer, per user" {
  [[ "$(host_field opencode INSTALL_CMD)" == *opencode.ai/install* ]]
  [[ "$(host_field opencode INSTALL_SCOPE)" == user ]]
  [[ "$(host_field opencode AUTH_NATIVE)" == subscription ]]
}

@test "opencode_config_content: registers w-mcp, allows it, and points at AGENTS.md" {
  opencode_config_content | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['mcp']['w-mcp'] == {'type': 'local', 'command': ['w-mcp'], 'enabled': True}, d
assert d['permission']['mcp']['w-mcp_*'] == 'allow', d
assert d['instructions'] == ['$SYS_ROOT/AGENTS.md'], d
"
}

@test "opencode_config_content: an active mcp.d drop-in gets its own entry and allow-wildcard" {
  _mcp_fixture
  opencode_config_content | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['mcp']['present'] == {'type': 'local', 'command': ['true', '--stdio', '-v'], 'enabled': True}, d
assert d['permission']['mcp']['present_*'] == 'allow', d
assert 'absent' not in d['mcp'], d
"
}

@test "toml_string: AGENTS.md survives a TOML round trip byte for byte" {
  local src="$REPO/rootfs/usr/share/w/ai/AGENTS.md" out="$BATS_TEST_TMPDIR/dev.toml"
  toml_string < "$src" > "$out"
  python3 -c "
import tomllib
v = tomllib.loads('developer_instructions=' + open('$out').read())['developer_instructions']
assert v == open('$src').read(), 'round trip differs'
"
}

@test "toml_string: backslash, quote, tab and CR are escaped, not dropped" {
  local out="$BATS_TEST_TMPDIR/edge.toml"
  printf 'a\\b "q"\tx\r\n' | toml_string > "$out"
  python3 -c "
import tomllib
v = tomllib.loads('k=' + open('$out').read())['k']
assert v == 'a\\\\b \"q\"\\tx\\r\\n', repr(v)
"
}

# ── The agent-authored overlay as a second plugin root ───────────────────────
# w_skill_add writes to $USER_ROOT/skills, which the shipped plugin does not
# cover — so those skills used to reach Claude Code only through
# w_search_knowledge, never as native skills. claude_user_plugin() wraps the
# overlay in its own plugin root; launch_host passes it as a second --plugin-dir.
_seed_user_skill() {   # $1 = skill name
  USER_ROOT="$BATS_TEST_TMPDIR/overlay"
  mkdir -p "$USER_ROOT/skills/$1"
  printf -- '---\nname: %s\ndescription: seeded by the test suite.\n---\n\nBody.\n' \
    "$1" > "$USER_ROOT/skills/$1/SKILL.md"
}

@test "claude_user_plugin: an empty overlay produces no wrapper at all" {
  USER_ROOT="$BATS_TEST_TMPDIR/overlay"
  mkdir -p "$USER_ROOT/skills"           # present but holding no skill
  run claude_user_plugin
  [ "$status" -eq 1 ]
  [ ! -e "$XDG_RUNTIME_DIR/w-ai/user-plugin" ]
}

@test "claude_user_plugin: a written skill yields a w-user plugin root" {
  _seed_user_skill my-note-skill
  run claude_user_plugin
  [ "$status" -eq 0 ]
  local dir="$output"
  # A plugin root CC accepts: manifest with a name distinct from the system tree's
  # `w`, so the overlay loads as w-user:<skill> instead of shadowing it.
  python3 -c "
import json
d = json.load(open('$dir/.claude-plugin/plugin.json'))
assert d['name'] == 'w-user', d
"
  # skills/ is a symlink onto the overlay itself — nothing is copied, so a skill
  # added later is live on the next launch without regenerating anything.
  [ -L "$dir/skills" ]
  [ -f "$dir/skills/my-note-skill/SKILL.md" ]
}

@test "claude_user_plugin: the wrapper follows the overlay, never a stale copy" {
  _seed_user_skill first-skill
  claude_user_plugin >/dev/null
  _seed_user_skill second-skill
  local dir; dir="$(claude_user_plugin)"
  [ -f "$dir/skills/second-skill/SKILL.md" ]
}

# ── AUTH_CHECK caching: the Super+W gate only ────────────────────────────────
# `w-ai ready` fires on every Super+W and AUTH_CHECK is a whole CLI start. The
# stamp is positives-only and read on that path alone: a cached "not signed in"
# would keep refusing for hours after a successful login, and a diagnostic that
# answers from a stamp lies.
_ghost_host() {   # $1 = AUTH_CHECK command
  USER_ROOT="$BATS_TEST_TMPDIR/overlay"
  mkdir -p "$USER_ROOT/hosts/ghost"
  cat > "$USER_ROOT/hosts/ghost/host.conf" <<EOF
BIN="true"
AUTH_MODES="subscription"
AUTH_NATIVE="subscription"
AUTH_CHECK="$1"
NEEDS_MODEL="no"
EOF
}

@test "auth cache: a live check is never answered from the stamp" {
  _ghost_host true
  host_logged_in ghost                    # stamps
  _ghost_host false                       # the CLI now says no
  ! host_logged_in ghost
}

@test "auth cache: a cached check skips the CLI while the stamp is fresh" {
  _ghost_host true
  host_logged_in ghost cached
  [ -f "$CACHE_DIR/auth-ghost" ]
  _ghost_host false
  host_logged_in ghost cached
}

@test "auth cache: a failing check is never stamped" {
  _ghost_host false
  ! host_logged_in ghost cached
  [ ! -e "$CACHE_DIR/auth-ghost" ]
}

@test "auth cache: an expired stamp falls back to the CLI" {
  _ghost_host false
  install -d -m700 "$CACHE_DIR"
  printf '%s' "$(( $(date +%s) - AUTH_TTL - 1 ))" > "$CACHE_DIR/auth-ghost"
  ! host_logged_in ghost cached
}

@test "auth cache: a garbage stamp is not trusted" {
  _ghost_host false
  install -d -m700 "$CACHE_DIR"
  printf 'not-a-timestamp' > "$CACHE_DIR/auth-ghost"
  ! host_logged_in ghost cached
}

@test "auth cache: host login drops the stamp before handing over the terminal" {
  _ghost_host true
  host_logged_in ghost cached
  auth_cache_clear ghost
  [ ! -e "$CACHE_DIR/auth-ghost" ]
}

@test "auth cache: a host with no AUTH_CHECK is never stamped" {
  _ghost_host ""
  host_logged_in ghost cached
  [ ! -e "$CACHE_DIR/auth-ghost" ]
}

# ── mcp.d: pack MCP servers reach every host as launch flags ─────────────────
# The drop-in is a machine file but the servers packs ship are per-user, so the
# one promise worth a test is the presence guard: an account without the
# bundle's user layer must not be handed a command that dies at spawn.
_mcp_fixture() {
  US=$'\x1f'
  SYS_ROOT="$BATS_TEST_TMPDIR/sys"; USER_ROOT="$BATS_TEST_TMPDIR/user"
  HOME="$BATS_TEST_TMPDIR/home"; export HOME
  mkdir -p "$SYS_ROOT/mcp.d" "$SYS_ROOT/hosts/claude" "$HOME"
  cp "$REPO/rootfs/usr/share/w/ai/hosts/claude/mcp.json" "$SYS_ROOT/hosts/claude/"
  # present: a PATH command; absent: a per-user file that setup-user.sh would
  # have created; path-form: COMMAND is a ~-path, ARGS carry a ~-path too.
  printf 'COMMAND="true"\nARGS="--stdio -v"\n' > "$SYS_ROOT/mcp.d/present.conf"
  printf 'COMMAND="python3"\nARGS="~/.local/share/w/x/server.py"\nREQUIRES="~/.local/share/w/x/server.py"\n' \
    > "$SYS_ROOT/mcp.d/absent.conf"
}

@test "mcp.d: a drop-in whose REQUIRES is missing is not offered, but is listed" {
  _mcp_fixture
  run mcp_dropins
  [[ "$output" == "present${US}true${US}--stdio -v${US}ok" ]]
  run mcp_dropins all
  [[ "$output" == *"absent${US}python3${US}$HOME/.local/share/w/x/server.py${US}missing"* ]]
}

@test "mcp.d: the per-user file appearing activates the drop-in, tilde expanded" {
  _mcp_fixture
  mkdir -p "$HOME/.local/share/w/x"; : > "$HOME/.local/share/w/x/server.py"
  run mcp_dropins
  [[ "$output" == *"absent${US}python3${US}$HOME/.local/share/w/x/server.py${US}ok"* ]]
}

@test "mcp.d: the user overlay wins by file name" {
  _mcp_fixture
  mkdir -p "$USER_ROOT/mcp.d"
  printf 'COMMAND="false"\n' > "$USER_ROOT/mcp.d/present.conf"
  run mcp_dropins
  [[ "$output" == "present${US}false${US}${US}ok" ]]
}

@test "mcp.d: a bad name or an empty COMMAND is invalid, never offered" {
  _mcp_fixture
  printf 'COMMAND="true"\n' > "$SYS_ROOT/mcp.d/Bad_Name.conf"
  printf 'ARGS="x"\n'       > "$SYS_ROOT/mcp.d/nocmd.conf"
  run mcp_dropins all
  [[ "$output" == *"Bad_Name${US}true${US}${US}invalid"* ]]
  [[ "$output" == *"nocmd${US}${US}x${US}invalid"* ]]
  run mcp_dropins
  [[ "$output" == "present${US}true${US}--stdio -v${US}ok" ]]
}

@test "mcp.d: goose gets one --with-extension per active server" {
  _mcp_fixture
  run goose_mcp_args
  [[ "$output" == $'--with-extension\ntrue --stdio -v' ]]
}

@test "mcp.d: a server with no ARGS gets no stray argument (goose + codex)" {
  _mcp_fixture
  printf 'COMMAND="true"\n' > "$SYS_ROOT/mcp.d/present.conf"
  run goose_mcp_args
  [[ "$output" == $'--with-extension\ntrue' ]]
  run codex_mcp_args
  [[ "$output" == $'-c\nmcp_servers.present.command="true"\n-c\nmcp_servers.present.args=[]\n-c\nmcp_servers.present.default_tools_approval_mode="approve"' ]]
}

@test "mcp.d: codex gets dotted keys with TOML values" {
  _mcp_fixture
  run codex_mcp_args
  [[ "$output" == $'-c\nmcp_servers.present.command="true"\n-c\nmcp_servers.present.args=["--stdio", "-v"]\n-c\nmcp_servers.present.default_tools_approval_mode="approve"' ]]
}

@test "mcp.d: claude gets the preset merged with the active servers, w-mcp kept" {
  _mcp_fixture
  cfg="$(claude_mcp_config)"
  [[ "$cfg" == "$XDG_RUNTIME_DIR/w-ai/mcp.json" ]]
  python3 -c '
import json,sys; s=json.load(open(sys.argv[1]))["mcpServers"]
assert s["w-mcp"]["command"]=="w-mcp", s
assert s["present"]=={"command":"true","args":["--stdio","-v"]}, s
assert "absent" not in s, s' "$cfg"
}

@test "mcp.d: no drop-ins — claude launches with the untouched preset" {
  _mcp_fixture
  rm "$SYS_ROOT"/mcp.d/*.conf
  cfg="$(claude_mcp_config)"
  [[ "$cfg" == "$SYS_ROOT/hosts/claude/mcp.json" ]]
  [[ ! -e "$XDG_RUNTIME_DIR/w-ai/mcp.json" ]]
}

# ── Host approval policy: W's own servers are never host-gated ────────────────
# The OS is the boundary (polkit, Tier-2), so a host-side confirm on top of
# W-curated tools is double-gating. What each host gets: goose — a seeded
# permission.yaml; codex — per-server default_tools_approval_mode="approve";
# claude — server-wide allow rules. Foreign, hand-registered servers keep each
# host's own approval flow.

@test "approval: claude allow rules cover w-mcp and active pack servers only" {
  _mcp_fixture
  run claude_allowed_tools
  [[ "${lines[0]}" == "mcp__w-mcp" ]]
  [[ "${lines[1]}" == "mcp__present" ]]
  [[ "${#lines[@]}" -eq 2 ]]   # 'absent' (missing REQUIRES) is not offered
}

# A fake w-mcp answering --selftest with the real output shape (PATH seam: the
# dev machine and CI have no W installed, the target machine has).
_wmcp_fixture() {
  HOME="$BATS_TEST_TMPDIR/permhome"; export HOME
  mkdir -p "$HOME/.config/goose" "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "w-mcp self-test OK"\necho "profile: full (2/2 tools offered)"\necho "tools (2): w_alpha, w_beta"\n' \
    > "$BATS_TEST_TMPDIR/bin/w-mcp"
  chmod +x "$BATS_TEST_TMPDIR/bin/w-mcp"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"; export PATH
}

@test "approval: goose permission.yaml is seeded from w-mcp's own tool list" {
  _wmcp_fixture
  _goose_seed_permissions
  local f="$HOME/.config/goose/permission.yaml"
  [[ -f "$f" ]]
  grep -q '^user:' "$f"
  grep -qxF '  always_allow:' "$f"
  grep -qxF '  - w-mcp__w_alpha' "$f"
  grep -qxF '  - w-mcp__w_beta' "$f"
  grep -qxF '  ask_before: []' "$f"      # goose's serde needs all three lists
  grep -qxF '  never_allow: []' "$f"
}

@test "approval: an existing permission.yaml is never rewritten" {
  _wmcp_fixture
  printf 'user:\n  always_allow:\n  - developer__shell\n  ask_before: []\n  never_allow: []\n' \
    > "$HOME/.config/goose/permission.yaml"
  _goose_seed_permissions
  grep -qxF '  - developer__shell' "$HOME/.config/goose/permission.yaml"
  ! grep -q 'w-mcp__' "$HOME/.config/goose/permission.yaml"
}

@test "approval: no goose config dir or no w-mcp — silent no-op" {
  HOME="$BATS_TEST_TMPDIR/emptyhome"; export HOME
  _goose_seed_permissions
  [[ ! -e "$HOME/.config/goose/permission.yaml" ]]
}

@test "approval: seed_goose answers goose's telemetry question in advance" {
  # A config predating the preset key: the first-run consent prompt would block
  # the session until answered; W appends the answer (upsert-if-absent only).
  HOME="$BATS_TEST_TMPDIR/telhome"; export HOME
  mkdir -p "$HOME/.config/goose"
  printf 'GOOSE_PROVIDER: openai\nGOOSE_MODEL: m\n' > "$HOME/.config/goose/config.yaml"
  seed_goose
  grep -q '^GOOSE_TELEMETRY_ENABLED: false$' "$HOME/.config/goose/config.yaml"
  # The user's own answer is never touched — a second run must not append again.
  printf 'GOOSE_TELEMETRY_ENABLED: true\n' > "$HOME/.config/goose/config.yaml"
  seed_goose
  [[ "$(grep -c '^GOOSE_TELEMETRY_ENABLED:' "$HOME/.config/goose/config.yaml")" -eq 1 ]]
  grep -q '^GOOSE_TELEMETRY_ENABLED: true$' "$HOME/.config/goose/config.yaml"
}
