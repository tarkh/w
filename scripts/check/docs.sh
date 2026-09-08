# check/docs.sh — the user documentation tree (rootfs/usr/share/doc/w).
#
# The docs are PRODUCTS in the shipped sense: they ride rootfs to every
# installed machine (apply_rootfs + the sync-map `rootfs/*.md --rootfs` rule),
# and render on three consumers — GitHub, the future site (any static
# generator) and the shell's infobox card, whose Qt markdown importer is the
# least capable of the three. The suite pins exactly that boundary:
#
#   1. frontmatter   every page carries title/section/order/summary — the
#                    navigation contract of the layer (RECOVERY.md and its
#                    ru twin are exempt: they are a standalone product with
#                    their own byte-pinned copies, see paths.sh rule 6).
#   2. parser bans   constructs the card's importer provably cannot render
#                    (probed against the shipped Qt 6.x in .claude/library/
#                    docs.md): footnotes, <details> and remote images. Written
#                    once, they stop each future author before a VM probe.
#   3. dev bleed     no .claude references in page BODIES — frontmatter
#                    sources: is the curation machinery and may name the
#                    library; prose may not (the skill-layer lesson: a shipped
#                    pointer to a tree the reader does not have).
#   4. links         relative .md and image targets resolve (both languages).
#   5. gold          the generated reference is byte-current
#                    (w-docs-refgen --check — the same script regenerates).

DOCS_DIR="rootfs/usr/share/doc/w"

# RECOVERY* are excluded: standalone product pages, guarded by paths.sh rule 6.
_doc_pages() { find "$DOCS_DIR" -name '*.md' ! -name 'RECOVERY*' | sort; }

_chk_frontmatter() {
  local page rc=0 fm
  while IFS= read -r page; do
    fm="$(awk 'NR==1{if ($0 !~ /^-{3}[ \t]*$/) {print; exit 1}; next} /^-{3}[ \t]*$/{exit} {print}' "$page" || true)"
    for key in title section order summary; do
      grep -q "^$key:" <<<"$fm" || { echo "  $page: frontmatter lacks '$key:'"; rc=1; }
    done
    grep -q '^section:' <<<"$fm" || continue
    grep -qE '^section: (start|guide|reference)[ \t]*$' <<<"$fm" || {
      echo "  $page: unknown frontmatter section (start|guide|reference)"; rc=1; }
  done < <(_doc_pages)
  [[ $rc == 0 ]]
}

_chk_bans() {
  local rc=0 page
  while IFS= read -r page; do
    grep -q '\[\^' "$page" && { echo "  $page: footnote syntax — the card's parser renders it literally"; rc=1; }
    grep -q '<details' "$page" && { echo "  $page: <details> — the card's parser flattens it"; rc=1; }
    grep -qE '!\[[^]]*\]\(https?:' "$page" && {
      echo "  $page: remote image — impossible offline; use the img/ tree"; rc=1; }
  done < <(_doc_pages)
  [[ $rc == 0 ]]
}

# Frontmatter is machinery (sources: anchors to .claude/library); bodies ship.
_chk_dev_bleed() {
  local rc=0 page body
  while IFS= read -r page; do
    awk 'NR==1 && /^-{3}/{f = 1; next} f && /^-{3}/{f = 0; next} f == 0 {print}' \
      "$page" | grep -q '\.claude' && { echo "  $page: body references .claude — rehome to a shipped page"; rc=1; }
  done < <(_doc_pages)
  [[ $rc == 0 ]]
}

# Markdown link targets: relative .md and image files must exist (both
# language trees); http(s), mailto, bare #anchors and RECOVERY homepage links
# are out of scope here.
_chk_links() {
  local rc=0 page dir link out
  while IFS= read -r page; do
    dir="$(dirname "$page")"
    while IFS= read -r link; do
      [[ "$link" == http* || "$link" == mailto:* || "$link" == \#* ]] && continue
      case "$link" in
        /*) continue ;;               # site-root links — site generator's domain
      esac
      out="$dir/$link"
      [[ -e "$out" ]] || { echo "  $page: broken link target '$link'"; rc=1; }
    done < <(grep -hoE '\]\(([^)#]+\.md|img/[^)]+)\)' "$page" | sed 's/^\](//;s/)$//')
  done < <(_doc_pages)
  [[ $rc == 0 ]]
}

chk_docs() {
  local rc=0
  [[ -d "$DOCS_DIR" ]] || { echo "  no docs tree at $DOCS_DIR"; return 1; }

  _chk_frontmatter || rc=1
  _chk_bans || rc=1
  _chk_dev_bleed || rc=1
  _chk_links || rc=1

  devtools/usr/local/bin/w-docs-refgen --check > /dev/null || {
    echo "  generated reference docs are stale (see w-docs-refgen --check above)"; rc=1; }

  [[ $rc == 0 ]] && echo "  docs tree: $(count_md) pages consistent"
  return $rc
}

count_md() { _doc_pages | wc -l; }
