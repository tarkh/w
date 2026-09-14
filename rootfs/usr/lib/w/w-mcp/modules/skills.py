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
from typing import Annotated

from core import SYS_ROOT, USER_ROOT, desc, tool
from skill_linter import lint_skill, parse_frontmatter

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
    """One parser for the format (skill_linter.parse_frontmatter): block-scalar
    descriptions of shipped skills and the single-line ones w_skill_add writes
    read the same way here, in the linter and in the catalog."""
    return parse_frontmatter(text)


def catalog():
    """Every skill the assistant can open, in KNOWLEDGE_ROOTS precedence (user
    overlay first, so a same-named user skill shadows the system one): a list of
    {name, description, scope, path}. THE index of the knowledge layer — the
    session-start catalog (bin/w-mcp instructions), w_skill_list, the resource
    descriptions and the CLI all render this one list, generated from the
    SKILL.md frontmatter, so no hand-written copy of it exists to drift."""
    out, seen = [], set()
    for root, scope in ((USER_ROOT, "user"), (SYS_ROOT, "system")):
        d = root / "skills"
        if not d.is_dir():
            continue
        for sk in sorted(p for p in d.iterdir() if p.is_dir()):
            md = sk / "SKILL.md"
            if sk.name in seen or not md.is_file():
                continue
            seen.add(sk.name)
            fm = parse_frontmatter(md.read_text(errors="replace"))
            out.append({"name": sk.name, "description": fm.get("description", "").strip(),
                        "scope": scope, "path": md})
    return out


def render_catalog(entries=None):
    """The catalog as the text block a host folds into its system prompt (bin/w-mcp
    `instructions`, unless the host loads SKILL.md natively — see there). Name +
    description per skill, nothing else: this is the progressive-disclosure index,
    the bodies come one at a time through w_skill_read."""
    entries = catalog() if entries is None else entries
    if not entries:
        return ""
    lines = ["## Skill catalog",
             "Detailed W knowledge is split into skills. Pick the ONE whose description "
             "matches the task and read it with w_skill_read(name) before acting — never "
             "read them all, never guess what a skill says. `[user]` marks skills authored "
             "for this user's own workflows (w_skill_add)."]
    for e in entries:
        tag = "[user] " if e["scope"] == "user" else ""
        lines.append(f"- {tag}{e['name']}: {e['description']}")
    return "\n".join(lines)


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
    entries = catalog()
    if not entries:
        return "(no skills found)"
    return "\n".join(f"[{e['scope']:<6}] {e['name']}: {e['description']}" for e in entries)


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
    def w_skill_add(
        name: Annotated[str, desc("^[a-z0-9-]{2,40}$, a verb or verb+noun (`deploy-frontend`, not `docker`); a system skill's name is refused")],
        description: Annotated[str, desc("one line, when to use it")],
        content: Annotated[str, desc("the workflow, markdown, under 32KB")],
        tags: Annotated[str, desc("short comma-separated list drawn from the content, for search/dedup")] = "",
        overwrite: Annotated[bool, desc("update the same-named skill, or create despite a near-duplicate")] = False,
    ) -> str:
        """Author a skill in your user-space overlay (Tier 1: user-scope,
        reversible) — future sessions find it in the catalog like a built-in one.
        ONLY after explicit user consent (they asked to save a workflow, said "we
        often do this"), never proactively; and only for user-specific knowledge
        (paths, hosts, commands) you could not reconstruct — "how to install
        nginx" is not a skill. Refuses a
        near-duplicate of an existing user skill: ask the user whether to update
        it (its name + overwrite=true) or create anyway (overwrite=true). A
        malformed file is refused; lint warnings are reported, not fatal."""
        return _skill_add(name, description, content, tags, overwrite)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_skill_read(name: str) -> str:
        """Read one skill's full text (Tier 0) — the step after the catalog: pick
        the single skill whose description matches the task, read it, act. System
        and user skills alike (a user skill shadows a same-named system one). Do
        not page through skills to "look around"; when no catalog entry fits, use
        w_search_knowledge."""
        return _skill_show(name)

    @tool(mcp, domain=DOMAIN)
    def w_skill_list() -> str:
        """The skill catalog — every skill you can w_skill_read, one description
        each (Tier 0). Usually already in your context; call it again after
        w_skill_add or once the context was compacted."""
        return _skill_list()

    @tool(mcp, domain=DOMAIN)
    def w_skill_rm(name: Annotated[str, desc("a user-overlay skill; system skills are refused")]) -> str:
        """Delete a skill from your user-space overlay (Tier 1, user-scope). No
        undo beyond re-authoring it."""
        return _skill_rm(name)
