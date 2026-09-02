# w-mcp domain: shared — the agent's persistent, cross-host memory. Facts are
# markdown files (one per file); a SQLite FTS5 table indexes them for token-cheap
# recall. Files are the source of truth; the db is a rebuildable mtime-synced
# index. The store lives here so both the w_memory_* tools and the orchestrator's
# `w-mcp memory` CLI share one implementation. See ai-integration.md §8.
import array
import datetime
import hashlib
import json
import re
import sqlite3
import urllib.error
import urllib.request

from core import MEM_TYPES, MEMORY_DB, MEMORY_DIR, _ai_conf, tool

DOMAIN = "shared"

# ── Semantic (vector) recall — opt-in ─────────────────────────────────────────
# Off by default (W_AI_EMBED=off): every function below is only ever reached
# from _mem_sync/_mem_search when the feature is on, so the FTS5-only path stays
# exactly the fast path it always was — no import, no extra file reads, no
# network call. See ai-integration.md §8.
_EMBED_TIMEOUT = 10       # seconds — ollama's /api/embed, local daemon, generous
_COSINE_THRESHOLD = 0.35  # cuts noise on near-empty vector overlaps
_RRF_K = 60               # reciprocal-rank-fusion constant (score = Σ 1/(K+rank))


# ── Memory store internals ────────────────────────────────────────────────────
def _slugify(text, fallback="fact"):
    s = re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")
    return s[:60].strip("-") or fallback


def _mem_parse(text):
    """Split a fact file into (frontmatter dict, body). Minimal `key: value`
    frontmatter between `---` fences — no YAML dependency."""
    fm, body = {}, text
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            for line in text[3:end].splitlines():
                if ":" in line and not line.lstrip().startswith("#"):
                    k, v = line.split(":", 1)
                    fm[k.strip()] = v.strip()
            body = text[end + 4:].lstrip("\n")
    return fm, body


def _mem_conn():
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(MEMORY_DB, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")     # tolerate concurrent hosts
    conn.execute("PRAGMA busy_timeout=5000")
    try:                                         # schema migration: status/due added
        conn.execute("SELECT status, due FROM mem LIMIT 1")
    except sqlite3.OperationalError:
        conn.execute("DROP TABLE IF EXISTS mem")  # files are the source of truth
    conn.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS mem USING fts5("
        "slug UNINDEXED, description, type UNINDEXED, body, mtime UNINDEXED, "
        "status UNINDEXED, due UNINDEXED, tokenize='porter unicode61')"
    )
    # Opt-in vector store (Stage 3): `kind` is always 'memory' today, reserved for
    # future kinds (skill/webcache — not implemented, schema-only headroom).
    # Migration path if the corpus ever crosses ~100k chunks: swap _VecIndex below
    # for a sqlite-vec (AUR)-backed one; nothing outside this module touches `vec`.
    conn.execute(
        "CREATE TABLE IF NOT EXISTS vec("
        "kind TEXT, ref TEXT, content_hash TEXT, dim INT, vector BLOB, "
        "PRIMARY KEY(kind, ref))"
    )
    return conn


def _mem_sync(conn):
    """Reconcile the FTS index with memory/*.md on disk (files are the source of
    truth; this catches edits from any host or the user's own hand). Also drives
    the opt-in vector-embedding pass (_vec_sync) — a no-op when W_AI_EMBED=off, so
    this stays exactly the fast path it always was."""
    have = {row[0]: row[1] for row in conn.execute("SELECT slug, mtime FROM mem")}
    seen = set()
    for path in sorted(MEMORY_DIR.glob("*.md")):
        slug = path.stem
        seen.add(slug)
        mtime = path.stat().st_mtime
        if have.get(slug) == mtime:
            continue
        fm, body = _mem_parse(path.read_text(errors="replace"))
        conn.execute("DELETE FROM mem WHERE slug=?", (slug,))
        conn.execute(
            "INSERT INTO mem(slug, description, type, body, mtime, status, due) "
            "VALUES(?,?,?,?,?,?,?)",
            (slug, fm.get("description", ""), fm.get("type", "reference"), body, mtime,
             fm.get("status", ""), fm.get("due", "")),
        )
    for slug in set(have) - seen:                # deleted on disk → drop from index
        conn.execute("DELETE FROM mem WHERE slug=?", (slug,))
    conn.commit()
    _vec_sync(conn)


class _VecIndex:
    """Thin interface over the `vec` table: BLOB float32 vectors, brute-force
    cosine similarity. `numpy` is imported lazily inside search() only — an
    absent numpy degrades to an empty result (caller falls back to FTS5-only),
    never an exception. Migration seam: if the corpus ever crosses ~100k chunks,
    swap this class for a sqlite-vec (AUR)-backed one; nothing outside this
    module talks to `vec` directly."""

    def __init__(self, conn):
        self._conn = conn

    def upsert(self, kind, ref, content_hash, vector):
        blob = array.array("f", vector).tobytes()
        self._conn.execute(
            "INSERT INTO vec(kind, ref, content_hash, dim, vector) VALUES(?,?,?,?,?) "
            "ON CONFLICT(kind, ref) DO UPDATE SET "
            "content_hash=excluded.content_hash, dim=excluded.dim, vector=excluded.vector",
            (kind, ref, content_hash, len(vector), blob),
        )

    def delete(self, kind, ref):
        self._conn.execute("DELETE FROM vec WHERE kind=? AND ref=?", (kind, ref))

    def count(self, kind="memory"):
        row = self._conn.execute("SELECT COUNT(*) FROM vec WHERE kind=?", (kind,)).fetchone()
        return row[0] if row else 0

    def search(self, query_vector, kind="memory", top_k=20, threshold=_COSINE_THRESHOLD):
        """Brute-force cosine top-K against every stored vector of `kind`, above
        `threshold`. Returns [] (never raises) if numpy is missing, the table is
        empty, or the query vector is degenerate."""
        try:
            import numpy as np
        except ImportError:
            return []
        rows = self._conn.execute(
            "SELECT ref, dim, vector FROM vec WHERE kind=?", (kind,)
        ).fetchall()
        if not rows:
            return []
        q = np.asarray(query_vector, dtype=np.float32)
        qnorm = np.linalg.norm(q)
        if qnorm == 0:
            return []
        scored = []
        for ref, dim, blob in rows:
            if dim != q.shape[0]:          # stale vector from a different embed model
                continue
            v = np.frombuffer(blob, dtype=np.float32)
            vnorm = np.linalg.norm(v)
            if vnorm == 0:
                continue
            cosine = float(np.dot(q, v) / (qnorm * vnorm))
            if cosine >= threshold:
                scored.append((ref, cosine))
        scored.sort(key=lambda r: r[1], reverse=True)
        return scored[:top_k]


def _embed(texts, conf):
    """Call ollama's /api/embed for a batch of texts. Returns a list of vectors
    aligned with `texts`, or None on any degradation (no model configured, ollama
    unreachable, malformed response) — callers fall back to FTS5-only, never
    raise. `keep_alive` is scoped to W_AI_EMBED_MODEL only: ollama ties it to the
    `model` field of this same request, so any other model the user runs (e.g. a
    HOST=local chat model) keeps its own independent VRAM lifecycle."""
    model = conf.get("W_AI_EMBED_MODEL", "").strip()
    if not model or not texts:
        return None
    url = (conf.get("W_AI_EMBED_URL", "").strip() or "http://127.0.0.1:11434").rstrip("/")
    keep_alive = conf.get("W_AI_EMBED_KEEPALIVE", "").strip() or "5m"
    body = json.dumps({"model": model, "input": texts, "keep_alive": keep_alive}).encode()
    req = urllib.request.Request(
        f"{url}/api/embed", data=body, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=_EMBED_TIMEOUT) as resp:
            data = json.loads(resp.read())
    except (urllib.error.URLError, OSError, TimeoutError, ValueError):
        return None
    vectors = data.get("embeddings")
    if not vectors or len(vectors) != len(texts):
        return None
    return vectors


def _vec_sync(conn):
    """Opt-in embedding pass: for every current fact whose sha256(model+
    description+body) changed since it was last embedded, (re)embed it via
    ollama and upsert the vector; drop vectors for facts no longer in `mem`.
    A no-op — zero extra queries, zero network — unless W_AI_EMBED=ollama."""
    conf = _ai_conf()
    if conf.get("W_AI_EMBED", "off").strip().lower() != "ollama":
        return
    model = conf.get("W_AI_EMBED_MODEL", "").strip()
    if not model:
        return
    vec = _VecIndex(conn)
    known_hash = {
        row[0]: row[1]
        for row in conn.execute("SELECT ref, content_hash FROM vec WHERE kind='memory'")
    }
    current = {row[0]: (row[1], row[2]) for row in conn.execute("SELECT slug, description, body FROM mem")}
    for ref in set(known_hash) - set(current):    # fact removed from disk
        vec.delete("memory", ref)
    pending = []  # (slug, hash, embed_text)
    for slug, (desc, fbody) in current.items():
        h = hashlib.sha256(f"{model}\n{desc}\n{fbody}".encode()).hexdigest()
        if known_hash.get(slug) != h:
            pending.append((slug, h, f"{desc}\n{fbody}"))
    if not pending:
        conn.commit()
        return
    vectors = _embed([t for _, _, t in pending], conf)
    if vectors is None:                            # ollama unreachable → skip quietly
        conn.commit()
        return
    for (slug, h, _), vector in zip(pending, vectors):
        vec.upsert("memory", slug, h, vector)
    conn.commit()


def _mem_unique_slug(base, is_same):
    """Disambiguate `base` against existing fact files with a numeric suffix.
    `is_same(frontmatter)` decides whether an existing file at a candidate slug is
    actually the same record (reuse it — idempotent update) or a different one
    (bump to `base-2`, `base-3`, …). Shared by the task writer and _mem_write_fact
    — see _mem_unique_task_slug for the motivating collision (non-ASCII text
    collapsing to the same fallback slug)."""
    slug = base
    n = 2
    while (MEMORY_DIR / f"{slug}.md").is_file():
        fm, _ = _mem_parse((MEMORY_DIR / f"{slug}.md").read_text(errors="replace"))
        if is_same(fm):
            break
        slug = f"{base}-{n}"
        n += 1
    return slug


def _mem_resolve_slug(name, description):
    """Resolve the slug a fact write will target. Explicit `name` names the file
    directly (the caller's intent to update that specific record); without it, the
    slug is auto-derived from `description` and disambiguated against collisions
    (see _mem_unique_slug) — otherwise non-ASCII descriptions, which `_slugify`
    collapses to the same fallback slug "fact", would silently overwrite unrelated
    facts. Callable before the actual write to preview the target (e.g. for a
    collision warning)."""
    if name:
        return _slugify(name)
    desc = description.strip()
    return _mem_unique_slug(_slugify(description), lambda fm: fm.get("description", "") == desc)


def _mem_write_fact(name, description, type_, body):
    """Write/overwrite a fact file (frontmatter + body) and reindex it."""
    slug = _mem_resolve_slug(name, description)
    if type_ not in MEM_TYPES:
        type_ = "reference"
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    path = MEMORY_DIR / f"{slug}.md"
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    created = now
    if path.is_file():                           # preserve original creation stamp
        created = _mem_parse(path.read_text(errors="replace"))[0].get("created", now)
    front = (
        f"---\nname: {slug}\ndescription: {description.strip()}\n"
        f"type: {type_}\ncreated: {created}\nupdated: {now}\n---\n\n"
    )
    path.write_text(front + body.strip() + "\n")
    with _mem_conn() as conn:
        _mem_sync(conn)
    return slug, path


def _mem_collision_warning(slug, type_):
    """If a fact with this slug already exists under a different type, return a
    one-line warning to surface in the tool response (guards against a silent
    overwrite — e.g. storing a `project` fact over an existing `task`)."""
    path = MEMORY_DIR / f"{slug}.md"
    if not path.is_file():
        return ""
    old_type = _mem_parse(path.read_text(errors="replace"))[0].get("type", "")
    if old_type and old_type != type_:
        return f" (warning: overwrote existing fact '{slug}' — was type={old_type}, now type={type_})"
    return ""


# ── Tasks (type=task, own writer: status/due live outside the plain-fact schema
# that _mem_write_fact preserves for user/feedback/project/reference) ──────────
def _mem_task_frontmatter(slug, description, status, due, created, now):
    front = (
        f"---\nname: {slug}\ndescription: {description.strip()}\n"
        f"type: task\ncreated: {created}\nupdated: {now}\nstatus: {status}\n"
    )
    if due:
        front += f"due: {due}\n"
    return front + "---\n\n"


def _mem_unique_task_slug(description):
    """Slugify a task description, disambiguating collisions with a numeric suffix.
    `_slugify` strips non-ASCII entirely, so two different task descriptions in the
    same non-Latin language (e.g. Russian) can both degrade to the same fallback
    slug "fact" — without this, the second w_task_add would silently overwrite the
    first task instead of adding a new one. Re-adding the exact same description
    reuses its existing slug (idempotent), rather than growing a new file forever."""
    desc = description.strip()
    return _mem_unique_slug(
        _slugify(description),
        lambda fm: fm.get("type") == "task" and fm.get("description", "") == desc,
    )


def _mem_task_add(content, due=""):
    if not content.strip():
        return "(nothing to store: content is empty)"
    desc = content.strip().splitlines()[0][:80]
    slug = _mem_unique_task_slug(desc)
    due = due.strip()
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    path = MEMORY_DIR / f"{slug}.md"
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    front = _mem_task_frontmatter(slug, desc, "open", due, now, now)
    path.write_text(front + content.strip() + "\n")
    with _mem_conn() as conn:
        _mem_sync(conn)
    return f"task added '{slug}' ({path})" + (f", due {due}" if due else "")


def _mem_task_list(status="open"):
    if not MEMORY_DIR.is_dir() or not any(MEMORY_DIR.glob("*.md")):
        return "(no tasks stored yet)"
    with _mem_conn() as conn:
        _mem_sync(conn)
        if status in ("", "all"):
            rows = conn.execute(
                "SELECT slug, description, status, due FROM mem WHERE type='task' "
                "ORDER BY slug"
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT slug, description, status, due FROM mem WHERE type='task' "
                "AND status=? ORDER BY slug",
                (status,),
            ).fetchall()
    if not rows:
        return f"(no tasks with status={status or 'all'})"
    out = []
    for slug, desc, st, due in rows:
        line = f"[{st}] {slug}: {desc}"
        if due:
            line += f" (due {due})"
        out.append(line)
    return "\n".join(out)


def _mem_task_done(slug):
    slug = _slugify(slug)
    path = MEMORY_DIR / f"{slug}.md"
    if not path.is_file():
        return f"(no such task: {slug})"
    fm, body = _mem_parse(path.read_text(errors="replace"))
    if fm.get("type") != "task":
        return f"(not a task: {slug}, type={fm.get('type', '?')})"
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    front = _mem_task_frontmatter(
        slug, fm.get("description", ""), "done", fm.get("due", ""), fm.get("created", now), now
    )
    path.write_text(front + body.strip() + "\n")
    with _mem_conn() as conn:
        _mem_sync(conn)
    return f"task done: {slug}"


def _render_search_results(rows):
    out = [f"{len(rows)} match(es):"]
    for slug, desc, type_, snip in rows:
        out.append(f"\n• [{type_}] {slug}: {desc}\n  … {snip}")
    return "\n".join(out)


def _rrf_merge(conn, fts_rows, vec_hits, max_results):
    """Reciprocal-rank fusion of the FTS5 candidate pool and the vector top-K
    (score = Σ 1/(K+rank), 0-indexed rank per list) into the existing snippet
    format. A slug that matched only via the vector index (never went through
    FTS5's snippet()) falls back to a truncated body."""
    scores = {}
    fts_by_slug = {}
    for rank, row in enumerate(fts_rows):
        slug = row[0]
        scores[slug] = scores.get(slug, 0.0) + 1.0 / (_RRF_K + rank + 1)
        fts_by_slug[slug] = row
    for rank, (slug, _cosine) in enumerate(vec_hits):
        scores[slug] = scores.get(slug, 0.0) + 1.0 / (_RRF_K + rank + 1)
    ranked = sorted(scores, key=lambda s: scores[s], reverse=True)[:max_results]
    missing = [s for s in ranked if s not in fts_by_slug]
    fallback = {}
    if missing:
        qmarks = ",".join("?" * len(missing))
        for slug, desc, type_, fbody in conn.execute(
            f"SELECT slug, description, type, body FROM mem WHERE slug IN ({qmarks})",
            missing,
        ):
            fallback[slug] = (slug, desc, type_, fbody.strip().replace("\n", " ")[:120])
    return [fts_by_slug.get(s) or fallback[s] for s in ranked if s in fts_by_slug or s in fallback]


def _vec_query(conn, query, conf):
    """Embed the query and return cosine top-K vector hits — [] on any
    degradation (no model, ollama unreachable, numpy missing), never raises."""
    vectors = _embed([query], conf)
    if not vectors:
        return []
    return _VecIndex(conn).search(vectors[0])


def _mem_search(query, max_results=5):
    if not MEMORY_DIR.is_dir() or not any(MEMORY_DIR.glob("*.md")):
        return "(no memories stored yet)"
    terms = re.findall(r"[\w-]+", query.lower())
    if not terms:
        return "(empty query)"
    match = " OR ".join(f'"{t}"' for t in terms)
    conf = _ai_conf()
    hybrid = conf.get("W_AI_EMBED", "off").strip().lower() == "ollama"
    # Off: identical query/limit/order to the pre-Stage-3 code — bit-for-bit the
    # same result. On: a wider FTS5 candidate pool feeds the RRF merge below.
    pool = max(max_results * 4, 20) if hybrid else max(1, max_results)
    with _mem_conn() as conn:
        _mem_sync(conn)
        try:
            fts_rows = conn.execute(
                "SELECT slug, description, type, "
                "snippet(mem, 3, '[', ']', ' … ', 12) "
                "FROM mem WHERE mem MATCH ? ORDER BY bm25(mem) LIMIT ?",
                (match, pool),
            ).fetchall()
        except sqlite3.OperationalError as e:
            return f"(memory search error: {e})"
        if not hybrid:
            rows = fts_rows[:max_results]
        else:
            vec_hits = _vec_query(conn, query, conf)
            rows = _rrf_merge(conn, fts_rows, vec_hits, max_results)
    if not rows:
        return f"(no memories match: {query})"
    return _render_search_results(rows)


def _mem_list():
    if not MEMORY_DIR.is_dir():
        return "(no memories stored yet)"
    with _mem_conn() as conn:
        _mem_sync(conn)
        rows = conn.execute("SELECT slug, type, description FROM mem ORDER BY slug").fetchall()
    if not rows:
        return "(no memories stored yet)"
    return "\n".join(f"[{t}] {s}: {d}" for s, t, d in rows)


def _mem_rm(slug):
    path = MEMORY_DIR / f"{_slugify(slug)}.md"
    if not path.is_file():
        alt = MEMORY_DIR / f"{slug}.md"          # accept the exact stem too
        path = alt if alt.is_file() else path
    if not path.is_file():
        return f"(no such memory: {slug})"
    path.unlink()
    with _mem_conn() as conn:
        _mem_sync(conn)
    return f"removed: {path.stem}"


def _mem_review():
    """Human-facing hygiene report (CLI-only, `w-ai memory review`): every fact with
    its age and whether it's part of the session-start context, plus staleness hints
    for done tasks (>30d) and episode notes (>60d). Read-only — flags candidates for
    `w-ai memory rm <slug>`, never deletes anything itself."""
    if not MEMORY_DIR.is_dir() or not any(MEMORY_DIR.glob("*.md")):
        return "(no memories stored yet)"
    now = datetime.datetime.now().astimezone().timestamp()
    with _mem_conn() as conn:
        _mem_sync(conn)
        rows = conn.execute(
            "SELECT slug, type, status, mtime FROM mem ORDER BY type, slug"
        ).fetchall()
        episode_slugs = {r[0] for r in conn.execute(
            "SELECT slug FROM mem WHERE type='project' AND slug LIKE 'episode-%' "
            "ORDER BY mtime DESC LIMIT 3"
        ).fetchall()}
    lines = [f"{'slug':<32}{'type':<10}{'age':<8}{'context':<9}note"]
    for slug, type_, status, mtime in rows:
        age = int((now - mtime) / 86400)
        in_context = (
            type_ in ("user", "feedback")
            or (type_ == "task" and status == "open")
            or (type_ == "project" and slug in episode_slugs)
        )
        note = ""
        if type_ == "task" and status == "done" and age > 30:
            note = "(stale — consider rm)"
        elif type_ == "project" and slug.startswith("episode-") and age > 60:
            note = "(stale — consider rm)"
        lines.append(f"{slug:<32}{type_:<10}{age}d{'':<6}{'yes' if in_context else 'no':<9}{note}")
    return "\n".join(lines)


# ── Session-start context block ────────────────────────────────────────────────
# Rendered into the MCP `instructions` field (see bin/w-mcp) so every host gets it
# injected at session start, without depending on the model thinking to search.
# `user` (identity/persona) and `feedback` (behavioral rules) facts qualify, plus
# (Stage 3) open `task` facts and the 3 most recent `episode-*` `project` facts —
# plain `project`/`reference` facts stay retrieval-only via w_memory_search, same
# discipline as the rest of the memory design (ai-integration.md §7 token budget).
MAX_CONTEXT_CHARS = 6000  # ≈1500 tokens


def _mem_context():
    """Render the compact context block injected at session start. Empty store (no
    facts at all) returns "". Hard-capped so a growing store never dominates the
    prompt: over cap, drop oldest recent-episode first, then oldest feedback, then
    oldest user fact, then (last resort) the oldest open task — tasks are the whole
    point of proactive recall (Stage 3 DoD), so they're the last thing cut."""
    if not MEMORY_DIR.is_dir() or not any(MEMORY_DIR.glob("*.md")):
        return ""
    with _mem_conn() as conn:
        _mem_sync(conn)
        users = conn.execute(
            "SELECT slug, description, body, mtime FROM mem WHERE type='user' ORDER BY slug"
        ).fetchall()
        feedback = conn.execute(
            "SELECT slug, description, mtime FROM mem WHERE type='feedback' ORDER BY slug"
        ).fetchall()
        tasks = conn.execute(
            "SELECT slug, description, due, mtime FROM mem WHERE type='task' AND status='open' "
            "ORDER BY (due=''), due, slug"
        ).fetchall()
        episodes = conn.execute(
            "SELECT slug, description, mtime FROM mem WHERE type='project' "
            "AND slug LIKE 'episode-%' ORDER BY mtime DESC LIMIT 3"
        ).fetchall()
    if not users and not feedback and not tasks and not episodes:
        return ""

    def render(users, feedback, tasks, episodes):
        parts = []
        if users:
            parts.append("About you and the user:\n" + "\n".join(
                f"- {desc}\n  {body.strip()}" for _, desc, body, _ in users
            ))
        if feedback:
            parts.append("Feedback to follow:\n" + "\n".join(
                f"- {desc}" for _, desc, _ in feedback
            ))
        if tasks:
            parts.append("Open tasks:\n" + "\n".join(
                f"- {desc}" + (f" (due {due})" if due else "") for _, desc, due, _ in tasks
            ))
        if episodes:
            parts.append("Recent episodes:\n" + "\n".join(
                f"- {desc}" for _, desc, _ in episodes
            ))
        return "\n\n".join(parts)

    text = render(users, feedback, tasks, episodes)
    trimmed = False
    while len(text) > MAX_CONTEXT_CHARS and episodes:
        episodes = episodes[:-1]                              # drop oldest (list end)
        trimmed = True
        text = render(users, feedback, tasks, episodes)
    while len(text) > MAX_CONTEXT_CHARS and feedback:
        feedback = sorted(feedback, key=lambda r: r[2])[1:]    # drop oldest mtime
        trimmed = True
        text = render(users, feedback, tasks, episodes)
    while len(text) > MAX_CONTEXT_CHARS and users:
        users = sorted(users, key=lambda r: r[3])[1:]
        trimmed = True
        text = render(users, feedback, tasks, episodes)
    while len(text) > MAX_CONTEXT_CHARS and tasks:
        tasks = sorted(tasks, key=lambda r: r[3])[1:]
        trimmed = True
        text = render(users, feedback, tasks, episodes)
    if trimmed:
        text += "\n\n(…more in memory — use w_memory_search)"
    return text


# ── Tools (Tier 1: safe, reversible, user-scope) ──────────────────────────────
def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_memory_search(query: str, max_results: int = 5) -> str:
        """Recall facts W has stored about this machine and user — preferences, past
        decisions, project state, per-machine config. Keyword search over the shared
        memory store, returning only the most relevant snippets (not the whole store),
        so it stays token-cheap. This memory is shared across every host. Query in
        BOTH the user's language and English — facts may be stored in either."""
        return _mem_search(query, max_results)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_memory_store(content: str, description: str = "", name: str = "", type: str = "reference") -> str:
        """Persist a fact worth remembering across sessions (Tier 1: user-scope,
        reversible). `content` is the fact (markdown ok, any language); `description`
        is a one-line summary used for recall — always write it in English, even if
        the fact and the conversation are in another language, since it is the search
        key; `type` is one of user|feedback|project|reference|task (use `w_task_add`
        instead for tasks — it sets up the open/done status this tool doesn't manage);
        `name` optionally sets the slug. Stored as a markdown file the user can read
        and edit, shared with every host via the same store. Store durable facts
        (preferences, decisions, machine specifics) — not transient chatter. When a
        session accomplishes something durable (installed, configured, decided
        something), also store a short episode note: type=project, name starting with
        `episode-`, description starting with the date — the 3 most recent are shown
        to you automatically at the next session start."""
        if not content.strip():
            return "(nothing to store: content is empty)"
        desc = description.strip() or content.strip().splitlines()[0][:80]
        slug_preview = _mem_resolve_slug(name, desc)
        warning = _mem_collision_warning(slug_preview, type)
        slug, path = _mem_write_fact(name, desc, type, content)
        return f"stored memory '{slug}' ({path}){warning}"

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_task_add(content: str, due: str = "") -> str:
        """Remember an open task so it resurfaces automatically at the start of every
        future session (Tier 1: user-scope, reversible), until marked done. Use this
        when the user asks you to remember or follow up on something later ("remind me
        to check backups") — not for w_memory_store, which does not track status.
        `due` is an optional YYYY-MM-DD date shown alongside the task."""
        return _mem_task_add(content, due)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_task_list(status: str = "open") -> str:
        """List stored tasks. `status` is "open" (default), "done", or "all". Open
        tasks are already shown to you at session start — use this mainly to check
        done tasks or see the full list."""
        return _mem_task_list(status)

    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_task_done(slug: str) -> str:
        """Mark a task done by its slug (from w_task_list or the session-start Open
        tasks list). The record is kept, not deleted, as history; it stops appearing
        in the session-start context."""
        return _mem_task_done(slug)
