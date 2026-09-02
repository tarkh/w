# w-mcp domain: shared — agent-authored user-overlay skills, the second knowledge
# layer (ai-integration.md/ai-authoring.md "runtime self-extend"). A skill here is
# a single markdown file at ~/.config/w/ai/skills/<name>/SKILL.md; KNOWLEDGE_ROOTS
# (core.py) already makes it findable by w_search_knowledge and servable as an
# MCP resource (bin/w-mcp's register_knowledge()) with zero extra plumbing — user
# root is scanned first, so it also shadows a same-named system skill, which is
# exactly why creating one under a system skill's name is refused here.
#
# Dedup is enforced IN the tool, not left to model discipline: w_skill_add refuses
# to write when an existing user skill looks like a near-duplicate of the
# requested one, by four cheap criteria (exact/substring name, tag overlap,
# keyword top-3 — see _dedup_matches). `overwrite=True` bypasses the check for
# both branches the user can choose: updating the matched skill (call again with
# its name) or creating the new one anyway (call again with the original name).
#
# Lint on write: before the file hits disk, its full
# content is run through the shared skill_linter.lint_skill() — the same check
# CI runs over shipped skills (ai-skilllint.bats). Errors refuse the write;
# warnings are non-blocking and surface in the response.
import datetime
import re

from core import SYS_ROOT, USER_ROOT, tool
from skill_linter import lint_skill

DOMAIN = "shared"

_NAME_RE = re.compile(r"^[a-z0-9-]{2,40}$")
_MAX_CONTENT_BYTES = 32 * 1024
_TOKEN_RE = re.compile(r"[\w-]+")
_STOPWORDS = {
    "a", "an", "the", "to", "of", "in", "is", "on", "for", "and", "or", "with",
    "from", "this", "that", "your", "you", "are", "it", "be", "as", "at", "by",
    "not", "via", "into", "over", "then",
}


def _valid_name(name):
    return bool(_NAME_RE.fullmatch((name or "").strip()))


def _sys_skill_names():
    d = SYS_ROOT / "skills"
    return {p.name for p in d.iterdir() if p.is_dir()} if d.is_dir() else set()


def _user_skill_dir():
    return USER_ROOT / "skills"


def _user_skill_names():
    d = _user_skill_dir()
    return sorted(p.name for p in d.iterdir() if p.is_dir()) if d.is_dir() else []


def _parse_skill_frontmatter(text):
    """Minimal `key: value` frontmatter reader for a SKILL.md — same no-YAML-
    dependency approach as modules/memory.py's _mem_parse, applied to the fields
    w_skill_add itself writes (name/description/origin/tags/created/updated)."""
    fm = {}
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            for line in text[3:end].splitlines():
                if ":" in line and not line.lstrip().startswith("#"):
                    k, v = line.split(":", 1)
                    fm[k.strip()] = v.strip()
    return fm


def _parse_tags(raw):
    """`tags: [a, b, c]` (or a bare `a, b, c`) -> {"a", "b", "c"}, lowercased."""
    s = (raw or "").strip().strip("[]")
    return {t.strip().lower() for t in s.split(",") if t.strip()}


def _load_user_skill(name):
    """Read one user skill's frontmatter + body, or None if missing/unreadable."""
    path = _user_skill_dir() / name / "SKILL.md"
    if not path.is_file():
        return None
    text = path.read_text(errors="replace")
    fm = _parse_skill_frontmatter(text)
    return {
        "name": name,
        "description": fm.get("description", ""),
        "tags": _parse_tags(fm.get("tags", "")),
        "created": fm.get("created", ""),
        "path": path,
    }


def _keyword_terms(*parts):
    """Whole tokens (not raw substrings — a naive `text.count(short_token)` false-
    positives constantly on 1-2 char noise like "a"/"to"/"s3") from the given
    text, lowercased, minus a small stopword list and anything under 3 chars."""
    text = " ".join(parts).lower()
    return {t for t in _TOKEN_RE.findall(text) if len(t) >= 3 and t not in _STOPWORDS}


def _dedup_matches(name, description, tags):
    """The four cheap, deterministic near-duplicate criteria (no embeddings):
    exact name, substring name, tag overlap, and keyword
    closeness — a lightweight whole-token-overlap scorer, the same spirit as
    w_search_knowledge's own scan-and-count approach (not a dedicated SQLite FTS5
    index; the store is a handful of files, so a second index would be pure
    overhead). A skill counts as a "keyword-top3" hit only if it shares at least 2
    distinct terms AND ranks in the top 3 by shared-term count — a plain "any
    overlap" threshold fires on a single incidental shared word between any two
    unrelated skills. Returns a list of {name, criteria: [...]} for every existing
    user skill that trips at least one criterion, most-criteria-first."""
    name = (name or "").strip().lower()
    new_tags = _parse_tags(tags)
    query_terms = _keyword_terms(name, description)

    existing = [s for s in (_load_user_skill(n) for n in _user_skill_names()) if s]
    scored = [(s, len(query_terms & _keyword_terms(s["name"], s["description"]))) for s in existing]
    top3_names = {s["name"] for s, score in sorted(scored, key=lambda p: -p[1])[:3] if score >= 2}

    hits = []
    for s in existing:
        ex_name = s["name"].lower()
        criteria = []
        if ex_name == name:
            criteria.append("exact-name")
        elif ex_name in name or name in ex_name:
            criteria.append("substring-name")
        if new_tags and s["tags"]:
            overlap = new_tags & s["tags"]
            if len(overlap) >= 2 or len(overlap) >= 0.5 * min(len(new_tags), len(s["tags"])):
                criteria.append("tag-overlap")
        if s["name"] in top3_names:
            criteria.append("keyword-top3")
        if criteria:
            hits.append({"name": s["name"], "criteria": criteria})
    hits.sort(key=lambda h: (-len(h["criteria"]), h["name"]))
    return hits


def _skill_add(name, description, content, tags, overwrite):
    name = (name or "").strip()
    if not _valid_name(name):
        return "(invalid name: must match ^[a-z0-9-]{2,40}$, e.g. 'deploy-frontend')"
    if not description.strip():
        return "(description is required — one line, when to load this skill)"
    if not content.strip():
        return "(content is empty — nothing to store)"
    if len(content.encode()) > _MAX_CONTENT_BYTES:
        return f"(content too large: {len(content.encode())} bytes, cap is {_MAX_CONTENT_BYTES})"
    if name in _sys_skill_names():
        return (
            f"(refused: '{name}' shadows a system skill — user skills may never "
            f"reuse a system skill's name; pick a different name)"
        )

    if not overwrite:
        dupes = _dedup_matches(name, description, tags)
        if dupes:
            listing = "; ".join(f"'{h['name']}' [{', '.join(h['criteria'])}]" for h in dupes)
            return (
                f"(possible duplicate of existing user skill(s): {listing}. Ask the "
                f"user: update one of these (call again with name=\"<that name>\", "
                f"overwrite=true) or create '{name}' as a new skill anyway (call "
                f"again with overwrite=true). Not created.)"
            )

    d = _user_skill_dir() / name
    path = d / "SKILL.md"
    existed = path.is_file()
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    created = _parse_skill_frontmatter(path.read_text(errors="replace")).get("created", now) if existed else now
    tag_set = _parse_tags(tags)
    front = (
        f"---\nname: {name}\ndescription: {description.strip()}\n"
        f"origin: agent-authored\ntags: [{', '.join(sorted(tag_set))}]\n"
        f"created: {created}\nupdated: {now}\n---\n\n"
    )
    full_content = front + content.strip() + "\n"

    # Lint on write: the same structural check that
    # gates shipped skills in CI (skill_linter.py), run here BEFORE the file
    # hits disk. In the common case this always passes (the frontmatter above
    # is well-formed by construction) — the real value is a safety net against
    # drift and adversarial input, e.g. a multi-line `description` containing
    # an embedded `\n---` would otherwise silently break the minimal
    # frontmatter parser (the real closing marker gets missed).
    dir_files = [f.name for f in d.iterdir() if f.is_file()] if d.is_dir() else []
    report = lint_skill(name, full_content, dir_files=dir_files, existing_names=_user_skill_names(), root="user")
    if not report["valid"]:
        return "(refused: failed runtime lint — " + "; ".join(report["errors"]) + ")"

    d.mkdir(parents=True, exist_ok=True)
    path.write_text(full_content)
    verb = "updated" if existed else "created"
    msg = f"skill {verb}: '{name}' ({path})"
    if report["warnings"]:
        msg += " (lint warnings: " + "; ".join(report["warnings"]) + ")"
    return msg


def _skill_list():
    sys_names = sorted(_sys_skill_names())
    user_names = _user_skill_names()
    if not sys_names and not user_names:
        return "(no skills found)"
    lines = []
    for n in sys_names:
        lines.append(f"[system] {n}")
    for n in user_names:
        s = _load_user_skill(n)
        desc = f": {s['description']}" if s and s["description"] else ""
        lines.append(f"[user]   {n}{desc}")
    return "\n".join(lines)


def _skill_show(name):
    name = (name or "").strip()
    path = _user_skill_dir() / name / "SKILL.md"
    scope = "user"
    if not path.is_file():
        path = SYS_ROOT / "skills" / name / "SKILL.md"
        scope = "system"
    if not path.is_file():
        return f"(no such skill: {name})"
    return f"[{scope}] {path}\n\n" + path.read_text(errors="replace")


def _skill_rm(name):
    name = (name or "").strip()
    d = _user_skill_dir() / name
    if not (d / "SKILL.md").is_file():
        if name in _sys_skill_names():
            return f"(refused: '{name}' is a system skill — user skills only)"
        return f"(no such user skill: {name})"
    import shutil
    shutil.rmtree(d)
    return f"removed user skill: {name}"


def register(mcp):
    @tool(mcp, domain=DOMAIN)
    def w_skill_add(name: str, description: str, content: str, tags: str = "", overwrite: bool = False) -> str:
        """Author a skill in your user-space knowledge overlay (Tier 1: user-scope,
        reversible) — a markdown file future sessions will find via
        w_search_knowledge and read like any built-in skill. ONLY call this after
        explicit user consent: they asked you to remember/save a workflow, said
        "we often do this", or asked you to create a skill outright — never as a
        proactive suggestion after ordinary Q&A or a one-off task. Only worth
        creating if the content captures user-specific data (paths, hosts, project
        names, commands, env vars) you could not reconstruct from general
        knowledge — "how to install nginx" is not a skill. One skill = one
        repeatable workflow (name a verb or verb+noun, e.g. `deploy-frontend`, not
        a broad `docker`). `name` must match ^[a-z0-9-]{2,40}$ and cannot reuse a
        system skill's name (refused). `tags` is a short comma-separated list you
        fill in from the content, for future search/dedup. This tool refuses by
        itself if an existing user skill looks like a near-duplicate (same/similar
        name, overlapping tags, or a close keyword match) — when that happens, ask
        the user whether to update the matched skill (call again with its name and
        overwrite=true) or create this one anyway (call again with overwrite=true).
        Also refuses (regardless of overwrite) on an invalid name, empty
        description/content, or content over 32KB. Before writing, the file is
        also checked against the same structural lint used to gate shipped
        skills — a malformed result is refused instead of written; a soundly
        formed one with lint warnings (e.g. missing heading) is still created,
        with the warnings noted in the response."""
        return _skill_add(name, description, content, tags, overwrite)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_skill_list() -> str:
        """List every available skill — system (built-in) and user-authored (your
        overlay), scope marked, with a one-line description for user skills. Tier
        0, read-only. Check this (or just call w_skill_add, which dedup-checks on
        its own) before authoring a new skill."""
        return _skill_list()

    @tool(mcp, domain=DOMAIN)
    def w_skill_rm(name: str) -> str:
        """Delete a skill from your user-space overlay by name (Tier 1,
        user-scope). Refuses on a system skill's name — those cannot be removed
        this way. There is no undo beyond re-authoring it."""
        return _skill_rm(name)
