# w-mcp domain: shared — keyword search over the shipped knowledge base
# (AGENTS.md + skills, user overlay included). Tier 0, read-only. The knowledge
# *resources* (w-knowledge:// URIs) are registered by the orchestrator; this is
# the retrieval tool for hosts that would rather search than pull whole skills.
from core import KNOWLEDGE_ROOTS, tool

DOMAIN = "shared"


def _search_knowledge(query, max_results=5):
    """The actual search: a plain substring/score scan over KNOWLEDGE_ROOTS (user
    overlay wins on a name clash — first root to see a given relative path takes
    it). Split from the @tool wrapper below so it's directly unit-testable (same
    pattern as every other module's module-level helpers, e.g. modules/skills.py)
    without needing the `mcp` package."""
    terms = [t.lower() for t in query.split() if t]
    if not terms:
        return "(empty query)"
    seen, hits = set(), []
    for root in KNOWLEDGE_ROOTS:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if path.suffix.lower() not in (".md", ".txt") or not path.is_file():
                continue
            rel = path.relative_to(root).as_posix()
            if rel in seen:  # user overlay already provided this file
                continue
            seen.add(rel)
            text = path.read_text(errors="replace")
            low = text.lower()
            score = sum(low.count(t) for t in terms)
            if not score:
                continue
            snippet = ""
            for ln in text.splitlines():
                if any(t in ln.lower() for t in terms):
                    snippet = ln.strip()
                    break
            hits.append((score, rel, str(path), snippet))
    if not hits:
        return f"(no matches for: {query})"
    hits.sort(key=lambda h: -h[0])
    out = [f"{len(hits)} file(s) matched; top {min(max_results, len(hits))}:"]
    for score, rel, full, snip in hits[: max(1, max_results)]:
        out.append(f"\n• {rel}  ({full})\n  hits={score}  {snip}")
    return "\n".join(out)


def register(mcp):
    @tool(mcp, domain=DOMAIN, minimal=True)
    def w_search_knowledge(query: str, max_results: int = 5) -> str:
        """Keyword search over the W knowledge base — AGENTS.md + skills, user
        overlay included (Tier 0). The fallback when no catalog entry fits, not a
        substitute for the catalog. Returns matching files with a snippet each;
        then w_skill_read the one that matched."""
        return _search_knowledge(query, max_results)
