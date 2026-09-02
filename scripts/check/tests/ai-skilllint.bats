#!/usr/bin/env bats
# ai-skilllint.bats — skill_linter.py: Skill/Knowledge Lint. Built
# now for the mechanical CI gate; the runtime hook inside w_skill_add (validate-
# before-write) is a follow-up — see skill_linter.py's
# module docstring for why the strict rules (origin, no-executables) only apply
# to root="user".

load helpers

setup() {
  LIB="$REPO/rootfs/usr/lib/w/w-mcp"
}

lint_py() {  # lint_py <python expr using `sl`>
  PYTHONPATH="$LIB" python3 -c "
import skill_linter as sl
$1
"
}

@test "lint_shipped_tree: every real shipped system skill passes with zero errors" {
  result="$(lint_py "
reports = sl.lint_shipped_tree('$REPO/rootfs/usr/share/w/ai', is_user_root=False)
bad = {k: v for k, v in reports.items() if v['errors']}
print(len(reports), len(bad), bad)
")"
  [[ "$result" == "20 0 {}" ]]
}

@test "lint_skill: rejects an invalid name" {
  result="$(lint_py "print(sl.lint_skill('Not Valid!', '---\nname: x\ndescription: d\n---\n\n# H\nbody'))")"
  [[ "$result" == *"'valid': False"* ]]
  [[ "$result" == *"does not match"* ]]
}

@test "lint_skill: rejects unparsable frontmatter" {
  result="$(lint_py "print(sl.lint_skill('deploy-frontend', 'no frontmatter here'))")"
  [[ "$result" == *"frontmatter missing or unparsable"* ]]
}

@test "lint_skill: rejects a name/frontmatter mismatch" {
  content='---
name: other-name
description: d
---

# H
body'
  result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content'''))")"
  [[ "$result" == *"!= directory name"* ]]
}

@test "lint_skill: user root requires origin+created, system root does not" {
  content='---
name: deploy-frontend
description: d
---

# H
body'
  user_result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content''', root='user'))")"
  [[ "$user_result" == *"missing required field 'origin'"* ]]
  [[ "$user_result" == *"missing required field 'created'"* ]]

  sys_result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content''', root='system'))")"
  [[ "$sys_result" == *"'valid': True"* ]]
}

@test "lint_skill: system skill declaring origin: agent-authored is an error" {
  content='---
name: deploy-frontend
description: d
origin: agent-authored
---

# H
body'
  result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content''', root='system'))")"
  [[ "$result" == *"origin-enforcement violation"* ]]
}

@test "lint_skill: user root rejects executable files in the skill directory" {
  content='---
name: deploy-frontend
description: d
origin: agent-authored
created: 2026-01-01
---

# H
body'
  result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content''', dir_files=['SKILL.md', 'run.sh'], root='user'))")"
  [[ "$result" == *"executable/script files not allowed"* ]]
  [[ "$result" == *"run.sh"* ]]
}

@test "lint_skill: system root tolerates a helper script (hyprland/install.sh precedent)" {
  content='---
name: hyprland
description: d
---

# H
body'
  result="$(lint_py "print(sl.lint_skill('hyprland', '''$content''', dir_files=['SKILL.md', 'install.sh'], root='system'))")"
  [[ "$result" == *"'valid': True"* ]]
}

@test "lint_skill: rejects content over the 32KB cap" {
  result="$(lint_py "
big = '---\nname: big-skill\ndescription: d\n---\n\n# H\n' + 'x' * 33000
print(sl.lint_skill('big-skill', big))
")"
  [[ "$result" == *"too large"* ]]
}

@test "lint_skill: warns on a broken internal link" {
  content='---
name: deploy-frontend
description: d
---

# H
See [setup](setup.md) for details.'
  result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content''', dir_files=['SKILL.md'], root='system'))")"
  [[ "$result" == *"possibly broken internal link: 'setup.md'"* ]]
  [[ "$result" == *"'valid': True"* ]]

  ok_result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content''', dir_files=['SKILL.md', 'setup.md'], root='system'))")"
  [[ "$ok_result" != *"broken internal link"* ]]
}

@test "lint_skill: warns on a missing H1/H2 heading" {
  content='---
name: deploy-frontend
description: d
---

just a body, no heading'
  result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content'''))")"
  [[ "$result" == *"no H1/H2 heading"* ]]
}

@test "lint_skill: info-notes an overwrite of an existing user skill name" {
  content='---
name: deploy-frontend
description: d
origin: agent-authored
created: 2026-01-01
---

# H
body'
  result="$(lint_py "print(sl.lint_skill('deploy-frontend', '''$content''', existing_names=['deploy-frontend'], root='user'))")"
  [[ "$result" == *"overwriting existing user skill 'deploy-frontend'"* ]]
}
