# check/qml.sh — qmllint over both Quickshell trees (shell + greeter).
#
# Catches, before a VM run: syntax errors, and any semantic category that
# does NOT depend on resolving Quickshell's own types (duplicate bindings,
# unreachable code, eval/with, JS typos, …). The suite is deny-list based:
# everything qmllint reports stays gating EXCEPT a fixed set of categories
# that are pure noise here because qmllint cannot resolve Quickshell modules
# (`import qs.*`, PanelWindow, singletons) — those imports are a project
# config-root, not an installed QML module, so member/type/import lookups
# all cascade into false positives. Filtering by the JSON `id` field is
# version-stable, unlike the per-category `--<id> <level>` flags.
#
# Needs Qt6 qmllint. The PATH `qmllint` on Arch is qt5's stripped 5.15 (no
# --json); the real one lives under /usr/lib/qt6/bin. Missing → skip (macOS
# only ships it via a heavy `brew install qt`, so this suite is Arch/CI-only).

# Categories suppressed because they are artefacts of unresolvable Quickshell
# types, not real defects (calibrated against the full 84-file tree):
#   import, unqualified, missing-property, unresolved-type, uncreatable-type,
#   signal-handler-parameters (Process.onExited QProcess::ExitStatus enum),
#   required (delegate props set at runtime by the model/loader),
#   unused-imports (import looks unused only because its types are unresolved).
# NOT globally suppressed: property-override — it is resolution-independent and
# catches real shadow bugs, so it stays gating. The handful of deliberate
# `enabled`-shadows (HubRow/Tile/SelectRow/Pill) carry an inline
# `// qmllint disable property-override` at the declaration instead.
QML_SUPPRESS="import unqualified missing-property unresolved-type uncreatable-type signal-handler-parameters required unused-imports"

# Resolve a Qt6 qmllint (>=6): explicit qt6 libexec dirs first, then PATH if it
# is new enough (guards against qt5-declarative shadowing the name).
_qml_bin() {
  local b
  for b in /usr/lib/qt6/bin/qmllint /usr/lib/qt6/libexec/qmllint /opt/homebrew/opt/qt/bin/qmllint; do
    [[ -x "$b" ]] && { echo "$b"; return 0; }
  done
  if command -v qmllint &>/dev/null; then
    [[ "$(qmllint --version 2>/dev/null)" == *"qmllint 6."* ]] && { command -v qmllint; return 0; }
  fi
  return 1
}

chk_qml() {
  local qml_files=()
  local f
  for f in "${ALL_FILES[@]}"; do [[ "$f" == *.qml ]] && qml_files+=("$f"); done
  [[ ${#qml_files[@]} -gt 0 ]] || { echo "  no qml files"; return 0; }

  local bin
  bin="$(_qml_bin)" || {
    warn "Qt6 qmllint not found (pacman -S qt6-declarative)"
    return 0
  }

  local tmp; tmp="$(mktemp)"
  # qmllint exits non-zero on findings/syntax errors; we read the JSON either
  # way, so ignore its status here.
  "$bin" --json "$tmp" "${qml_files[@]}" >/dev/null 2>&1 || true

  local rc=0
  python3 - "$tmp" "$QML_SUPPRESS" <<'PY' || rc=$?
import json, sys
data = json.load(open(sys.argv[1]))
suppress = set(sys.argv[2].split())
files = data.get("files", [])
kept = 0
dropped = 0
for fe in files:
    fn = fe.get("filename", "?")
    for w in fe.get("warnings", []):
        wid = w.get("id", "")
        if wid in suppress:
            dropped += 1
            continue
        kept += 1
        print(f"  {fn}:{w.get('line')}:{w.get('column')} [{wid}] {w.get('message')}")
print(f"  qmllint: {len(files)} files, {kept} findings ({dropped} suppressed as Quickshell-unresolved noise)")
sys.exit(1 if kept else 0)
PY

  rm -f "$tmp"
  return $rc
}
