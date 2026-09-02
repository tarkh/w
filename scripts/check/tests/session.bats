#!/usr/bin/env bats
# session.bats — w-session: the logic that decides what gets saved and where a
# window goes back.
#
# The valuable half of this subsystem is testable without a compositor, and that
# is not an accident — it is why the split tree is reconstructed from geometry
# in a pure function rather than discovered by poking the running session. What
# can silently be WRONG (a workspace rebuilt with the split on the wrong axis, a
# ratio off by a gap width, a floating window placed by global instead of
# monitor-local coordinates, a command line that breaks the Lua string it is
# interpolated into, a trim that throws away the window you were working in) is
# all reachable from here. What is left needing a live session — the launch, the
# parking and the `preselect`/`splitratio` replay — was verified on the VM.
#
# The script is `w-session`, not `w-session.py`, so it is loaded through
# SourceFileLoader under a module name other than __main__ (its entry guard then
# keeps main() from running on import).

load helpers

setup() {
  command -v python3 &>/dev/null || skip "python3 not installed"
  BIN="$REPO/rootfs/usr/bin/w-session"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  # Named layouts live under XDG_DATA_HOME, and the module resolves it at import
  # time. Without this a test that writes one lands in the real ~/.local/share —
  # which is exactly what happened the first time these tests were run.
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  mkdir -p "$XDG_CONFIG_HOME/w"
}

# Run a python snippet with the module loaded as `ws`.
ws() {
  python3 -c "
import importlib.util
from importlib.machinery import SourceFileLoader
# spec_from_file_location returns None for an extensionless path (no loader is
# registered for it), so the loader is named explicitly.
spec = importlib.util.spec_from_loader('ws', SourceFileLoader('ws', '$BIN'))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
$1
"
}

# ── Lua quoting: the command line is arbitrary input ──────────────────────────

@test "lua_str escapes quotes and backslashes" {
  run ws "print(ws.lua_str('a\"b\\\\c'))"
  [ "$status" -eq 0 ]
  [ "$output" = '"a\"b\\c"' ]
}

@test "lua_str survives a command containing ]] (why long brackets are not used)" {
  # A long-bracket literal would END there, turning the rest of the command into
  # executable Lua — the reason lua_str exists at all.
  run ws "print(ws.lua_str('sh -c echo ]] hi'))"
  [ "$status" -eq 0 ]
  [[ "$output" == '"sh -c echo ]] hi"' ]]
}

# ── Split-tree reconstruction ─────────────────────────────────────────────────
#
# Rectangles below carry realistic gaps (a 10px outer gap, 20px between
# neighbours) precisely because the ratio must NOT depend on them.

@test "two side-by-side windows reconstruct as one horizontal split" {
  run ws "
t = ws.build_tree([(0, (10, 48, 1180, 981)), (1, (1210, 48, 499, 981))])
print(t['split'], t['a']['leaf'], t['b']['leaf'])"
  [ "$status" -eq 0 ]
  [ "$output" = "h 0 1" ]
}

@test "the split ratio is measured across the gap, not from the window widths" {
  # 1180 and 499 px with a 20px gap between them. Dwindle's ratio is where the
  # DIVIDER sits in the usable span, so the answer is 2*(1200-10)/1699 = 1.4008
  # — the value a user who typed `splitratio 1.4` would have set. Dividing the
  # widths instead (2*1180/1679 = 1.4056) charges the whole gap to one side and
  # drifts a little further with every nested split.
  run ws "
t = ws.build_tree([(0, (10, 48, 1180, 981)), (1, (1210, 48, 499, 981))])
print(round(t['ratio'], 3))"
  [ "$status" -eq 0 ]
  [ "$output" = "1.401" ]
}

@test "an even split comes back as ratio 1.0" {
  run ws "
t = ws.build_tree([(0, (10, 48, 845, 981)), (1, (875, 48, 844, 981))])
print(abs(t['ratio'] - 1.0) < 0.01)"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "stacked windows reconstruct as a vertical split" {
  run ws "
t = ws.build_tree([(0, (10, 48, 1699, 485)), (1, (10, 553, 1699, 476))])
print(t['split'])"
  [ "$status" -eq 0 ]
  [ "$output" = "v" ]
}

@test "three in a column nest to the right, in top-to-bottom order" {
  run ws "
t = ws.build_tree([(0,(10,48,1699,320)), (1,(10,388,1699,320)), (2,(10,728,1699,301))])
print(t['split'], t['a']['leaf'], t['b']['split'], t['b']['a']['leaf'], t['b']['b']['leaf'])"
  [ "$status" -eq 0 ]
  [ "$output" = "v 0 v 1 2" ]
}

@test "a 2x2 grid resolves by the fixed axis priority (columns first)" {
  # Genuinely ambiguous: the same picture is "two columns, each halved" and "two
  # rows, each halved". Both replay identically, so the tie is broken by a rule
  # rather than left to chance.
  run ws "
t = ws.build_tree([(0,(10,48,845,485)), (1,(10,553,845,476)),
                   (2,(875,48,844,485)), (3,(875,553,844,476))])
print(t['split'], t['a']['split'], t['b']['split'])
print(ws.tree_leaves(t))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "h v v" ]
  [ "${lines[1]}" = "[0, 1, 2, 3]" ]
}

@test "one window is a bare leaf and no windows is nothing" {
  run ws "
print(ws.build_tree([(7, (10, 48, 100, 100))]))
print(ws.build_tree([]))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "{'leaf': 7}" ]
  [ "${lines[1]}" = "None" ]
}

@test "an arrangement with no straight cut returns None instead of a wrong tree" {
  # A pinwheel: no vertical or horizontal line separates it into two groups.
  # Saying so lets the caller fall back to order; inventing a tree would place
  # windows confidently in the wrong slots.
  run ws "
print(ws.build_tree([(0,(0,0,60,40)), (1,(60,0,40,60)), (2,(40,40,60,40)), (3,(0,60,40,40))]))"
  [ "$status" -eq 0 ]
  [ "$output" = "None" ]
}

@test "first_leaf walks to the anchor the replay starts from" {
  run ws "
t = ws.build_tree([(5,(10,48,845,981)), (6,(875,48,844,981))])
print(ws.first_leaf(t), ws.first_leaf({'leaf': 3}), ws.first_leaf(None))"
  [ "$status" -eq 0 ]
  [ "$output" = "5 3 None" ]
}

@test "a window that never came back costs its own slot and nothing else" {
  # Its sibling takes the parent's place; leaving the hole would anchor every
  # later window against something that does not exist.
  run ws "
t = ws.build_tree([(0,(10,48,1699,320)), (1,(10,388,1699,320)), (2,(10,728,1699,301))])
p = ws.prune_tree(t, {0, 2})
print(ws.tree_leaves(p), 'leaf' in p or p['split'])
print(ws.prune_tree(t, set()))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "[0, 2] v" ]
  [ "${lines[1]}" = "None" ]
}

# ── The launch expression ─────────────────────────────────────────────────────

@test "every relaunch goes through uwsm app onto the hidden staging workspace" {
  # uwsm app is the app-graphical.slice contract; the staging workspace is what
  # keeps phase 1 invisible.
  run ws "
print(ws.park_expr({'cmd': 'foot', 'cwd': ''}))"
  [ "$status" -eq 0 ]
  [[ "$output" == *'uwsm app -- foot'* ]]
  [[ "$output" == *'workspace = "special:w-restore silent"'* ]]
  [[ "$output" == *'no_initial_focus = true'* ]]
}

@test "no geometry rides on the launch — placement is phase 2's business alone" {
  run ws "
e = ws.park_expr({'cmd': 'foot', 'cwd': ''})
print(any(k in e for k in ('float', 'move', 'size', 'pin', 'fullscreen')))"
  [ "$status" -eq 0 ]
  [ "$output" = "False" ]
}

@test "a saved cwd is entered, and a stale one is ignored rather than failing the launch" {
  run ws "
print('live:', ws.park_expr({'cmd': 'foot', 'cwd': '$BATS_TEST_TMPDIR'}).split('\"')[1])
print('dead:', ws.park_expr({'cmd': 'foot', 'cwd': '/nonexistent-$$'}).split('\"')[1])"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "live: cd $BATS_TEST_TMPDIR && exec uwsm app -- foot" ]]
  [[ "${lines[1]}" == "dead: uwsm app -- foot" ]]
}

# ── Exclusions ────────────────────────────────────────────────────────────────

@test "exclude patterns are anchored — foot does not silence footclient" {
  # Unanchored, one entry would quietly take out a whole family of windows.
  run ws "
p = ws.exclude_patterns({'EXCLUDE_CLASSES': 'foot'})
print(bool(p[0].match('foot')), bool(p[0].match('footclient')))"
  [ "$status" -eq 0 ]
  [ "$output" = "True False" ]
}

@test "a malformed exclude pattern is dropped with a warning, not fatal" {
  # One typo in a config file must not blind the whole subsystem.
  run ws "
p = ws.exclude_patterns({'EXCLUDE_CLASSES': '*bad ok'})
print(len(p), bool(p[0].match('ok')))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 True"* ]]
}

# ── The relaunch override table ───────────────────────────────────────────────

@test "the user's relaunch table wins over the vendor one, and '-' means never" {
  # Both tables are supplied here rather than relying on the installed vendor
  # file — the dev host running these tests is not a W machine.
  cat > "$BATS_TEST_TMPDIR/vendor.tsv" <<'EOF'
# vendor: what W ships
foot	w-term
firefox	firefox
EOF
  cat > "$XDG_CONFIG_HOME/w/session-apps.tsv" <<'EOF'
# personal overrides
foot	my-terminal
steam_app_.*	-
EOF
  run ws "
ws.VENDOR_APPS = '$BATS_TEST_TMPDIR/vendor.tsv'
m = ws.app_map()
print(ws.mapped_command(m, 'foot'))        # user entry beats the vendor's w-term
print(ws.mapped_command(m, 'firefox'))     # vendor-only entry still applies
print(ws.mapped_command(m, 'steam_app_570'))
print(ws.mapped_command(m, 'unlisted'))    # no entry: fall back to /proc/cmdline"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "my-terminal" ]
  [ "${lines[1]}" = "firefox" ]
  [ "${lines[2]}" = "-" ]
  [ "${lines[3]}" = "None" ]
}

# ── Programs running inside a terminal ────────────────────────────────────────

@test "an allowlisted terminal program is reopened through w-term, in its own cwd" {
  # The cwd recorded is the PROGRAM's, not the terminal's — that is the whole
  # value of looking inside.
  cat > "$XDG_CONFIG_HOME/w/session-terminal.list" <<'EOF'
helix
EOF
  run ws "
ws.VENDOR_TERMINAL = '/nonexistent'
ws.terminal_payload = lambda pid, title: 4242
ws.proc_cmdline = lambda pid: ['helix', 'src/main.rs']
ws.prog_name = lambda pid: 'helix'
ws.proc_cwd = lambda pid: '/home/w/src'
cmd, cwd, remapped, term = ws.resolve_relaunch(
    {'pid': 1, 'initialClass': 'foot', 'title': 'helix'}, [], ws.terminal_allowlist(), 'allowlist')
print(cmd); print(cwd); print(remapped, term)"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "w-term -e helix src/main.rs" ]
  [ "${lines[1]}" = "/home/w/src" ]
  [ "${lines[2]}" = "True helix" ]
}

@test "a program off the allowlist gets its terminal back, never re-executed" {
  # This is the safety property: `make` was on screen, `make` does not re-run.
  cat > "$XDG_CONFIG_HOME/w/session-terminal.list" <<'EOF'
helix
EOF
  run ws "
ws.VENDOR_TERMINAL = '/nonexistent'
ws.terminal_payload = lambda pid, title: 4242
ws.proc_cmdline = lambda pid: ['make', '-j8'] if pid == 4242 else ['foot']
ws.prog_name = lambda pid: 'make'
ws.proc_cwd = lambda pid: '/home/w/src'
cmd, _, _, term = ws.resolve_relaunch(
    {'pid': 1, 'initialClass': 'foot', 'title': 'make'}, [], ws.terminal_allowlist(), 'allowlist')
print(cmd, '|', term)"
  [ "$status" -eq 0 ]
  [ "$output" = "foot | " ]
}

@test "TERMINAL_APPS=all reopens what the allowlist would have refused" {
  run ws "
ws.VENDOR_TERMINAL = '/nonexistent'
ws.terminal_payload = lambda pid, title: 4242
ws.proc_cmdline = lambda pid: ['make', '-j8']
ws.prog_name = lambda pid: 'make'
ws.proc_cwd = lambda pid: '/home/w/src'
print(ws.resolve_relaunch({'pid': 1, 'initialClass': 'foot', 'title': 'make'}, [], [], 'all')[0])"
  [ "$status" -eq 0 ]
  [ "$output" = "w-term -e make -j8" ]
}

@test "TERMINAL_APPS=off never even looks inside the window" {
  run ws "
def boom(pid, title): raise AssertionError('looked inside with TERMINAL_APPS=off')
ws.terminal_payload = boom
ws.proc_cmdline = lambda pid: ['foot']
print(ws.resolve_relaunch({'pid': 1, 'initialClass': 'foot', 'title': 'x'}, [], [], 'off')[0])"
  [ "$status" -eq 0 ]
  [ "$output" = "foot" ]
}

@test "a window title identifies its program even when the program renamed the window" {
  # Measured on ghostty, which titles a window after its foreground process for
  # as long as that process leaves the title alone (btop/helix/less/man) — and
  # after whatever the process asks for the moment it sets one (yazi:
  # `Yazi: <cwd>`). Equality here cost a real, silent bug: the yazi window came
  # back as an empty shell while its neighbours came back whole.
  run ws "
cases = [
    ('btop', 'btop', True),            # terminal's own title = process name
    ('Yazi: w', 'yazi', True),         # measured: name + cwd, and a different case
    ('src/main.rs - NVIM', 'nvim', True),
    ('ranger:/etc', 'ranger', True),
    ('useless.rs - helix', 'less', False),   # a substring is not a name
    ('lazygit', 'git', False),               # nor is a prefix of one
    ('w-term', 'term', False),               # a hyphen still bounds a word
    ('~', 'zsh', False),                     # a bare shell names nothing
    ('', 'yazi', False),
]
print(all(ws.title_names(t, n) is e for t, n, e in cases))"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "under a single-instance terminal the title picks the window's own program" {
  # One pid for every window (ghostty --gtk-single-instance), one pty child per
  # window, nothing linking the two but the title.
  run ws "
ws.proc_children = lambda pid: [10, 20] if pid == 1 else []
ws.proc_stat = lambda pid: {'comm': 'x', 'pgrp': pid, 'tty': 34816 + pid, 'tpgid': pid}
ws.prog_name = lambda pid: {10: 'yazi', 20: 'btop'}[pid]
print(ws.terminal_payload(1, 'Yazi: w'))
print(ws.terminal_payload(1, 'btop'))
print(ws.terminal_payload(1, 'Ghostty'))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "10" ]
  [ "${lines[1]}" = "20" ]
  [ "${lines[2]}" = "None" ]   # names neither: an empty terminal beats a wrong guess
}

@test "a title naming two live programs resolves to neither" {
  # yazi sitting in a directory called `less`, with a real `less` next to it.
  # Both candidates match, so the coincidence costs an empty terminal — never
  # the wrong program in the wrong window.
  run ws "
ws.proc_children = lambda pid: [10, 20] if pid == 1 else []
ws.proc_stat = lambda pid: {'comm': 'x', 'pgrp': pid, 'tty': 34816 + pid, 'tpgid': pid}
ws.prog_name = lambda pid: {10: 'yazi', 20: 'less'}[pid]
print(ws.terminal_payload(1, 'Yazi: less'))"
  [ "$status" -eq 0 ]
  [ "$output" = "None" ]
}

@test "proc_stat survives an executable whose name contains parentheses" {
  # /proc/<pid>/stat is not splittable on spaces: comm is raw and unescaped, so
  # the parse has to anchor on the LAST ')'. A binary named like this is rare
  # and the failure it causes — a misread tpgid — is silent.
  cp "$(command -v sleep)" "$BATS_TEST_TMPDIR/sl(ee p)x"
  "$BATS_TEST_TMPDIR/sl(ee p)x" 5 &
  local pid=$!
  run ws "
st = ws.proc_stat($pid)
print(st['comm'])
print(isinstance(st['pgrp'], int) and isinstance(st['tpgid'], int))"
  kill "$pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "sl(ee p)x" ]
  [ "${lines[1]}" = "True" ]
}

# ── Snapshot shape ────────────────────────────────────────────────────────────

# Drive take_snapshot against a fixed client list instead of a compositor.
fake_hypr() {
  cat <<'EOF'
CLIENTS = [
  {"mapped": True, "initialClass": "a", "class": "a", "pid": 1, "workspace": {"id": 2, "name": "2"},
   "monitor": 0, "at": [875, 48],  "size": [844, 981], "focusHistoryID": 3},
  {"mapped": True, "initialClass": "b", "class": "b", "pid": 2, "workspace": {"id": 2, "name": "2"},
   "monitor": 0, "at": [10, 48],   "size": [845, 981], "focusHistoryID": 0},
  {"mapped": True, "initialClass": "c", "class": "c", "pid": 3, "workspace": {"id": 1, "name": "1"},
   "monitor": 0, "at": [10, 48],   "size": [1699, 981], "focusHistoryID": 1},
  {"mapped": False, "initialClass": "d", "class": "d", "pid": 4, "workspace": {"id": 1, "name": "1"},
   "monitor": 0, "at": [0, 0],     "size": [10, 10], "focusHistoryID": 2},
]
MONITORS = [{"id": 0, "name": "eDP-1", "x": 0, "y": 0, "focused": True,
             "activeWorkspace": {"id": 1}}]
def fake(*args):
    if args[-1] == "clients":  return CLIENTS
    if args[-1] == "monitors": return MONITORS
    if args[-1] == "general:layout": return {"str": "dwindle"}
    return {}
ws.hypr_json = fake
ws.proc_cmdline = lambda pid: ["prog%d" % pid]
ws.proc_cwd = lambda pid: "/tmp"
ws.terminal_payload = lambda pid, title: None
EOF
}

@test "unmapped windows are not recorded" {
  run ws "$(fake_hypr)
s = ws.take_snapshot({'MAX_WINDOWS': '40'})
print([w['class'] for w in s['windows']])"
  [ "$status" -eq 0 ]
  [[ "$output" != *"'d'"* ]]
}

@test "windows are ordered by workspace then left-to-right" {
  run ws "$(fake_hypr)
s = ws.take_snapshot({'MAX_WINDOWS': '40'})
print([w['class'] for w in s['windows']])"
  [ "$status" -eq 0 ]
  [ "$output" = "['c', 'b', 'a']" ]
}

@test "each workspace carries its own split tree, over tiled windows only" {
  run ws "$(fake_hypr)
s = ws.take_snapshot({'MAX_WINDOWS': '40'})
byname = {w['name']: w for w in s['workspaces']}
print(byname['1']['tree'])
print(byname['2']['tree']['split'], ws.tree_leaves(byname['2']['tree']))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "{'leaf': 0}" ]
  [ "${lines[1]}" = "h [1, 2]" ]
}

@test "over MAX_WINDOWS the least recently focused windows are dropped" {
  # Trimming by list order would throw away whatever the user was working in.
  run ws "$(fake_hypr)
s = ws.take_snapshot({'MAX_WINDOWS': '2'})
print(sorted(w['class'] for w in s['windows']))"
  [ "$status" -eq 0 ]
  [ "$output" = "['b', 'c']" ]
}

@test "the focused window and the per-monitor active workspace are recorded" {
  run ws "$(fake_hypr)
s = ws.take_snapshot({'MAX_WINDOWS': '40'})
print(s['windows'][s['focused']]['class'], s['monitors'][0]['monitor'], s['monitors'][0]['workspace'])
print(s['layout'])"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "b eDP-1 1" ]
  [ "${lines[1]}" = "dwindle" ]
}

@test "a window with no recoverable command line is skipped, not saved as unlaunchable" {
  run ws "$(fake_hypr)
ws.proc_cmdline = lambda pid: None
s = ws.take_snapshot({'MAX_WINDOWS': '40'})
print(len(s['windows']))"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ── Snapshot file ─────────────────────────────────────────────────────────────

@test "the snapshot is written 0600 and leaves no temp file behind" {
  # It records command lines and working directories — other accounts have no
  # business reading them.
  run ws "$(fake_hypr)
ws.write_snapshot(ws.take_snapshot({'MAX_WINDOWS': '40'}))
import os, stat
print(oct(stat.S_IMODE(os.stat(ws.SNAPSHOT).st_mode)))
print(sorted(os.listdir(ws.STATE_DIR)))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "0o600" ]
  [ "${lines[1]}" = "['session.json']" ]
}

@test "a snapshot from an incompatible version is ignored, not half-read" {
  run ws "
import json, os
os.makedirs(ws.STATE_DIR, exist_ok=True)
open(ws.SNAPSHOT, 'w').write(json.dumps({'version': 1, 'windows': [{'class': 'x'}]}))
print(ws.read_snapshot())"
  [ "$status" -eq 0 ]
  [[ "$output" == *"None"* ]]
}

# ── Named layouts: the key, and what a scope actually contains ────────────────
#
# Everything below is the half of the layouts feature that can be wrong without
# anything crashing: a name that silently collides with another one, a workspace
# layout that quietly keeps the number it was saved from, a filter that drops the
# split tree it was supposed to carry. The live half — closing windows, the
# detach, the replay — was verified on the VM.

@test "slugify keeps unicode letters, so a Cyrillic name stays readable" {
  run ws "print(ws.slugify('Работа'), ws.slugify('Моя Сессия'))"
  [ "$status" -eq 0 ]
  [ "$output" = "работа моя-сессия" ]
}

@test "slugify cannot escape the layouts directory" {
  # The result is a bare file name whatever it is handed: no separators, no dots,
  # nothing that resolves upward.
  run ws "
for name in ['../../etc/passwd', 'a/b', '..', '.', 'x\\\\y']:
    s = ws.slugify(name)
    assert '/' not in s and '\\\\' not in s and s not in ('.', '..'), (name, s)
    print(s)"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "etc-passwd" ]
}

@test "a name with no letter or digit has no key, rather than a made-up one" {
  # Two such names would otherwise collide and overwrite each other silently.
  run ws "print(repr(ws.slugify('...')), repr(ws.slugify('  ')), repr(ws.slugify('!!!')))"
  [ "$status" -eq 0 ]
  [ "$output" = "'' '' ''" ]
}

@test "slugify caps the length and never ends on a separator" {
  run ws "
s = ws.slugify('x' * 200)
print(len(s))
print(repr(ws.slugify('a' + '-' * 80 + 'b')[-1]))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "64" ]
  [ "${lines[1]}" = "'b'" ]
}

@test "only_workspace keeps one workspace's windows, tree and all" {
  run ws "$(fake_hypr)
snap = ws.take_snapshot({'MAX_WINDOWS': '40'})
one = ws.only_workspace(snap, '1')
print(len(one['workspaces']))
print(sorted(w['workspace']['name'] for w in snap['windows']) != ['1'])
print(all(w['workspace']['name'] == '1' for w in one['windows']))
print(one['workspaces'][0]['tree'] == [w for w in snap['workspaces'] if w['name'] == '1'][0]['tree'])"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1" ]
  [ "${lines[2]}" = "True" ]
  [ "${lines[3]}" = "True" ]
}

@test "a workspace layout forgets which workspace it came from" {
  # This is what makes it applicable onto any workspace later: no name, no id, no
  # monitor, and no saved active-workspace list to drag the user back.
  run ws "$(fake_hypr)
one = ws.only_workspace(ws.take_snapshot({'MAX_WINDOWS': '40'}), '1')
w = one['workspaces'][0]
print(repr(w['name']), w['id'], repr(w['monitor']), one['monitors'])"
  [ "$status" -eq 0 ]
  [ "$output" = "'' None '' []" ]
}

@test "only_workspace drops a focused id that did not survive the filter" {
  # by_id lookups would otherwise point at a window that is no longer there.
  run ws "$(fake_hypr)
snap = ws.take_snapshot({'MAX_WINDOWS': '40'})
snap['focused'] = 999
print(ws.only_workspace(snap, '1')['focused'])"
  [ "$status" -eq 0 ]
  [ "$output" = "None" ]
}

@test "retarget points every window and workspace at the given workspace" {
  run ws "$(fake_hypr)
one = ws.only_workspace(ws.take_snapshot({'MAX_WINDOWS': '40'}), '1')
r = ws.retarget(one, '7')
print(sorted({w['workspace']['name'] for w in r['windows']}))
print(sorted({x['name'] for x in r['workspaces']}))
print(r['monitors'])"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "['7']" ]
  [ "${lines[1]}" = "['7']" ]
  [ "${lines[2]}" = "[]" ]
}

@test "retarget leaves the source snapshot untouched" {
  # do_restore retargets a layout read from disk; mutating it in place would make
  # a second apply in the same process see the first one's target.
  run ws "$(fake_hypr)
one = ws.only_workspace(ws.take_snapshot({'MAX_WINDOWS': '40'}), '1')
ws.retarget(one, '7')
print(repr(one['workspaces'][0]['name']))
print(sorted({w['workspace']['name'] for w in one['windows']}))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "''" ]
  [ "${lines[1]}" = "['1']" ]
}

@test "a layout file is written 0600 and read back only if it is one" {
  # The directory is somewhere a user can drop files, and what comes out of it is
  # relaunched as commands — so a stray json must not be read as a layout.
  # Asserted by label, not by line number: rejecting a file warns on stderr, and
  # bats folds that into $output.
  run ws "$(fake_hypr)
import json, os, stat
snap = ws.take_snapshot({'MAX_WINDOWS': '40'})
snap['name'] = 'X'; snap['scope'] = 'layout'
ws.layout_write('x', snap)
print('mode=' + oct(stat.S_IMODE(os.stat(ws.layout_path('x')).st_mode)))
print('name=' + ws.layout_read('x')['name'])
open(ws.layout_path('noscope'), 'w').write('{\"version\": 2}')
print('noscope=' + repr(ws.layout_read('noscope')))
open(ws.layout_path('old'), 'w').write('{\"version\": 1, \"scope\": \"layout\"}')
print('old=' + repr(ws.layout_read('old')))
print('missing=' + repr(ws.layout_read('missing')))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=0o600"* ]]
  [[ "$output" == *"name=X"* ]]
  [[ "$output" == *"noscope=None"* ]]
  [[ "$output" == *"old=None"* ]]
  [[ "$output" == *"missing=None"* ]]
}

@test "the layouts directory is 0700, and nothing is written outside it" {
  run ws "$(fake_hypr)
import os, stat
snap = ws.take_snapshot({'MAX_WINDOWS': '40'})
snap['name'] = 'X'; snap['scope'] = 'layout'
ws.layout_write('x', snap)
print('dirmode=' + oct(stat.S_IMODE(os.stat(ws.LAYOUTS_DIR).st_mode)))
print('files=' + repr(sorted(os.listdir(ws.LAYOUTS_DIR))))
print('under_data=' + repr(ws.LAYOUTS_DIR.startswith(os.environ['XDG_DATA_HOME'])))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirmode=0o700"* ]]
  # No leftover temp file from the atomic write.
  [[ "$output" == *"files=['x.json']"* ]]
  [[ "$output" == *"under_data=True"* ]]
}
