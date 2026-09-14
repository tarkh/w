# w-mcp: skill_linter.py — shared SkillLinter ("Skill / Knowledge Lint" +
# "runtime lint on write"). Two call sites share
# this one report shape ({valid, errors, warnings, info}): the mechanical CI gate
# (lint_shipped_tree, zero LLM, ai-skilllint.bats) and modules/skills.py's
# w_skill_add, which runs lint_skill() on the full file content before it ever
# reaches disk and refuses the write on errors.
#
# System skills (SYS_ROOT) predate the agent-authored format: no shipped
# SKILL.md carries `origin:`/`created:` frontmatter, and at least one
# (hyprland) legitimately ships a helper script (install.sh, refreshes its wiki
# copy on the target — not agent-authored, not subject to the no-executables
# rule). So the strict Этап 6.11 rules (origin required, no executables in the
# skill directory) apply only when root="user" (the shape w_skill_add produces);
# a universal subset — frontmatter parses, name+description present, name ==
# directory name, size cap, internal link integrity, tag shape, an H1/H2 heading
# present — applies to both roots, and is what a CI sweep over SYS_ROOT actually
# exercises (see lint_shipped_tree).
import re
from pathlib import Path

_NAME_RE = re.compile(r"^[a-z0-9-]{2,40}$")
_MAX_CONTENT_BYTES = 32 * 1024
_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
_HEADING_RE = re.compile(r"^#{1,2}\s+\S", re.MULTILINE)
_EXEC_SUFFIXES = (".sh", ".py", ".bin")
# The description is the skill's line in the catalog every host sees at session
# start (bin/w-mcp instructions / native skill lists), so it is budgeted like the
# body: over the cap the catalog stops being an index and starts being the skill.
_MAX_DESCRIPTION_BYTES = 600
_KEY_RE = re.compile(r"^([A-Za-z_][\w-]*):(.*)$")


def parse_frontmatter(text):
    """No-YAML-dependency frontmatter reader shared by the linter, modules/skills.py
    and the catalog (bin/w-mcp). Understands what a SKILL.md actually uses: plain
    `key: value`, block scalars (`>`, `>-`, `|`, `|-` — folded to one line, since
    every consumer wants the description as a single line) and list values
    (`sources:`/`tools:` — skipped: their consumers parse them themselves). Same
    approach as modules/memory.py's _mem_parse; the one parser for the format,
    so a skill reads the same everywhere."""
    fm = {}
    if not text.startswith("---"):
        return fm
    end = text.find("\n---", 3)
    if end == -1:
        return fm
    key, block = None, None
    for line in text[3:end].splitlines():
        if key is not None and (line.startswith((" ", "\t")) or not line.strip()):
            if block is not None and line.strip():
                block.append(line.strip())
            continue
        if block is not None:
            fm[key] = " ".join(block)
        key, block = None, None
        if line.lstrip().startswith("#") or not line.strip():
            continue
        m = _KEY_RE.match(line)
        if not m:
            continue
        key, value = m.group(1), m.group(2).strip()
        if value in (">", ">-", "|", "|-"):
            block = []
        elif value:
            fm[key] = value
        # else: a list (`tools:`) or empty value — left to its own consumer
    if block is not None:
        fm[key] = " ".join(block)
    return fm


_parse_frontmatter = parse_frontmatter  # older call sites


def lint_skill(name, content, dir_files=(), existing_names=(), root="user"):
    """Lint one skill's SKILL.md content. `dir_files` are the sibling filenames
    already in its directory (no-executables rule + link-integrity resolution);
    `existing_names` are every other skill name on the same root (only used for
    the info-level "overwriting" note — the actual name-collision/shadow refusal
    is w_skill_add's job, not re-decided here). `root` is "user" or "system": only
    "user" enforces origin/no-executables (see module docstring).

    Returns {"valid": bool, "errors": [...], "warnings": [...], "info": [...]}."""
    errors, warnings, info = [], [], []

    if not _NAME_RE.fullmatch(name or ""):
        errors.append(f"name '{name}' does not match ^[a-z0-9-]{{2,40}}$")

    fm = _parse_frontmatter(content)
    if not content.startswith("---") or not fm:
        errors.append("frontmatter missing or unparsable (expected a leading --- block)")
    else:
        for field in ("name", "description"):
            if not fm.get(field, "").strip():
                errors.append(f"frontmatter missing required field '{field}'")
        if fm.get("name") and fm["name"] != name:
            errors.append(f"frontmatter name '{fm.get('name')}' != directory name '{name}'")
        dsize = len(fm.get("description", "").encode())
        if dsize > _MAX_DESCRIPTION_BYTES:
            errors.append(f"description too long for the catalog: {dsize} bytes, cap is {_MAX_DESCRIPTION_BYTES}")
        if root == "user":
            for field in ("origin", "created"):
                if not fm.get(field, "").strip():
                    errors.append(f"frontmatter missing required field '{field}' (user-overlay skill)")
            if fm.get("origin") and fm["origin"] != "agent-authored":
                errors.append(f"user-overlay skill must have origin: agent-authored, found '{fm.get('origin')}'")
        elif root == "system" and fm.get("origin") == "agent-authored":
            errors.append("system skill declares origin: agent-authored (origin-enforcement violation)")

    size = len(content.encode())
    if size > _MAX_CONTENT_BYTES:
        errors.append(f"content too large: {size} bytes, cap is {_MAX_CONTENT_BYTES}")

    if root == "user":
        bad_files = [f for f in dir_files if f.lower().endswith(_EXEC_SUFFIXES)]
        if bad_files:
            errors.append(f"executable/script files not allowed in a user skill dir: {', '.join(bad_files)}")

    for m in _LINK_RE.finditer(content):
        target = m.group(1).strip()
        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        base = Path(target).name
        if dir_files and base not in dir_files and target not in dir_files:
            warnings.append(f"possibly broken internal link: '{target}'")

    tags_raw = fm.get("tags", "")
    if tags_raw and not re.fullmatch(r"\[?[\w\- ,]*\]?", tags_raw):
        warnings.append(f"tags field has an unexpected shape: {tags_raw!r}")

    if not _HEADING_RE.search(content):
        warnings.append("no H1/H2 heading found (structural anomaly)")

    if root == "user" and name in existing_names:
        info.append(f"overwriting existing user skill '{name}'")

    return {"valid": not errors, "errors": errors, "warnings": warnings, "info": info}


def lint_shipped_tree(root_path, is_user_root=False):
    """CI sweep (Этап 7.4.2): lint every already-shipped skills/<name>/SKILL.md
    under one KNOWLEDGE_ROOTS root. Returns {skill_name: report}."""
    root_path = Path(root_path)
    reports = {}
    skills_dir = root_path / "skills"
    if not skills_dir.is_dir():
        return reports
    for d in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
        md = d / "SKILL.md"
        if not md.is_file():
            continue
        content = md.read_text(errors="replace")
        dir_files = [f.name for f in d.iterdir() if f.is_file()]
        reports[d.name] = lint_skill(
            d.name, content, dir_files=dir_files,
            root="user" if is_user_root else "system",
        )
    return reports
