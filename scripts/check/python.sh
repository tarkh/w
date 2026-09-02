# check/python.sh — ruff over the python inventory (w-mcp, w-authd).
#
# The pair `w-ai-actuate` (bash, root) + `w-mcp` (python, user) is the most
# security-sensitive code in the project (audit §3.4) — this is its bug net.
# Config/rationale for ignored rules: ruff.toml at the repo root.

chk_python() {
  [[ ${#PY_FILES[@]} -gt 0 ]] || { echo "  no python files"; return 0; }
  if ! command -v ruff &>/dev/null; then
    warn "ruff not installed (pacman -S ruff / brew install ruff)"
    return 0
  fi
  echo "  ruff: ${PY_FILES[*]}"
  ruff check --quiet "${PY_FILES[@]}"
}
