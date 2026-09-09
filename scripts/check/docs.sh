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
#   2a. anchors     headings must slug identically on GitHub and in the card.
#                   GitHub's slugger strips punctuation unicode-aware; the card's
#                   (core/DocsViewer.slug) strips the ASCII block only, so a
#                   heading carrying an em dash, an ellipsis or typographic
#                   quotes gets two different slugs — and every `help:` deep-link
#                   into it silently degrades to the whole page. Letters are fine
#                   in any script (both keep them), so a translated tree passes.
#   2b. help links  every Hub "?" target (help: {page, anchor} in the hub QML)
#                   resolves to a real page and a real section — a typo there
#                   fails nowhere at runtime, it just opens the wrong thing.
#                   Extends into every `<lang>/` tree that exists: a translated
#                   page must carry a frontmatter `anchors:` map from the fixed
#                   EN slug to its own heading's slug (core/DocsViewer.qml
#                   applies it before searching for the section).
#   2c. help reach  a panel with a help button also declares the focusHeader
#                   signal, so the button is reachable by keyboard and not only
#                   by mouse (quickshell-hub.md, Ф-Keyboard).
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

# Deep-linkable headings (## and deeper — an H1 is a page title, never a target).
# Only NON-ASCII PUNCTUATION diverges between the two sluggers; letters of any
# script are kept by both, so this stays correct for a translated tree.
_chk_heading_slugs() {
  local rc=0 page hits cls
  # Written as escapes, not glyphs: the literals are invisible in review, and a
  # typographic quote in source reads as a typo to the linter (SC1112). In order:
  # em/en/non-breaking dash, ellipsis, guillemets, curly double + single quotes,
  # middle dot, bullet. (A comment line may not OPEN with the linter's own name —
  # it would be parsed as a directive.)
  cls=$'[\u2014\u2013\u2011\u2026\u00ab\u00bb\u201c\u201d\u2018\u2019\u00b7\u2022]'
  while IFS= read -r page; do
    hits="$(grep -nE "^#{2,6}[ \t]+.*$cls" "$page" || true)"
    [[ -n "$hits" ]] && {
      echo "  $page: heading with non-ASCII punctuation — GitHub and the card"
      echo "      slug it differently, so a deep-link to it degrades to the page:"
      sed 's/^/        /' <<<"$hits"; rc=1; }
  done < <(_doc_pages)
  [[ $rc == 0 ]]
}

# Every `help: { page, anchor }` the Hub can open must resolve: the page exists
# under the docs tree and the anchor names a real heading in it. These pairs are
# hand-written in QML (HubRegistry + the per-tab overrides in panels/), and a
# typo does not fail anywhere — DocsViewer degrades a missed anchor to the whole
# page, which is exactly the "approximately about this" outcome the layer bans.
# The slug is DocsViewer.slug()'s algorithm: lowercase, ASCII punctuation
# dropped, space runs → one '-'. (_chk_heading_slugs above keeps the two
# sluggers agreeing, so computing GitHub's here would give the same answer.)
# DocsViewer.slug(): lowercase, ASCII punctuation stripped, space runs → one
# '-'. Its lowercase is JS .toLowerCase() — Unicode-aware, so a Cyrillic
# heading's capital first letter folds correctly. `tr '[:upper:]' '[:lower:]'`
# does NOT (byte-oriented, ASCII-only in the "C" locale check.sh may run
# under) — it silently left translated headings capitalized and every ru
# anchor mismatched until this was written through python3's str.lower(),
# which folds Unicode correctly regardless of the process locale.
_heading_slugs_of() {
  grep -E '^#{2,6}[ \t]+' "$1" | sed -E 's/^#+[ \t]+//; s/[ \t]*#*[ \t]*$//' \
    | python3 -c 'import sys
for line in sys.stdin:
    print(line.rstrip("\n").lower())' \
    | sed -E 's/[!-\/:-@[-`{-~]//g; s/^[ \t]+//; s/[ \t]+$//; s/ +/-/g'
}

_chk_help_anchors() {
  local rc=0 hub="rootfs/etc/skel/.config/quickshell/w/modules/hub"
  [[ -d "$hub" ]] || return 0
  local pairs
  mapfile -t pairs < <(grep -rhoE 'page: "[^"]+", anchor: "[^"]*"' "$hub" \
           | sed 's/page: "//; s/", anchor: "/\t/; s/"$//' | sort -u)
  local page anchor pair
  for pair in "${pairs[@]}"; do
    page="${pair%%$'\t'*}"; anchor="${pair#*$'\t'}"
    [[ -z "$page" ]] && continue
    if [[ ! -f "$DOCS_DIR/$page" ]]; then
      echo "  hub help: page '$page' does not exist in the docs tree"; rc=1; continue
    fi
    [[ -z "$anchor" ]] && continue
    _heading_slugs_of "$DOCS_DIR/$page" | grep -qx "$anchor" || {
        echo "  hub help: '$page' has no section '$anchor'"; rc=1; }
  done

  # A translated page's headings slug differently from the EN anchor a Hub
  # help: button carries (fixed at the registry, no per-locale copy there), so
  # it must declare a frontmatter `anchors:` map from that EN slug to its own
  # heading's slug — DocsViewer applies it before searching for the section
  # (core/DocsViewer.qml, _render). An untranslated page is exempt: DocsViewer
  # falls back to the EN page for it, and this loop above already checked that
  # one. Only `<lang>/` trees that exist are walked, so this is a no-op today
  # and starts enforcing itself the moment a translation lands.
  local lang_dir lang tpage fm tanchor
  for lang_dir in "$DOCS_DIR"/*/; do
    lang="$(basename "$lang_dir")"
    [[ "$lang" =~ ^[a-z]{2}$ ]] || continue
    for pair in "${pairs[@]}"; do
      page="${pair%%$'\t'*}"; anchor="${pair#*$'\t'}"
      [[ -z "$page" || -z "$anchor" ]] && continue
      tpage="$DOCS_DIR/$lang/$page"
      [[ -f "$tpage" ]] || continue
      fm="$(awk 'NR==1 && /^-{3}/{f=1;next} f && /^-{3}/{exit} f{print}' "$tpage")"
      tanchor="$(awk -v want="$anchor" '
          /^anchors:[ \t]*$/ { inblk=1; next }
          inblk && /^[ \t]+[^ \t]/ {
            line=$0; sub(/^[ \t]+/, "", line)
            key=line; sub(/:.*/, "", key)
            if (key == want) { val=line; sub(/^[^:]+:[ \t]*/, "", val); print val; exit }
            next
          }
          inblk { inblk = 0 }
        ' <<<"$fm")"
      if [[ -z "$tanchor" ]]; then
        echo "  hub help: '$lang/$page' has no anchors: mapping for '$anchor'"; rc=1; continue
      fi
      _heading_slugs_of "$tpage" | grep -qx "$tanchor" || {
          echo "  hub help: '$lang/$page' anchors: maps '$anchor' to '$tanchor', no such section"; rc=1; }
    done
  done
  [[ $rc == 0 ]]
}

# The "?" button has TWO halves and shipping one is a silent half-feature: the
# `help:` entry draws it (mouse works) and the panel's `signal focusHeader()`
# makes it reachable by keyboard (Up at the panel's topmost roving position —
# quickshell-hub.md, Ф-Keyboard). Adding help entries without the signal is
# exactly what happened on 2026-09-09: six panels grew a button no keyboard
# could reach, and nothing failed. So: any panel the Hub can open help FOR must
# declare the signal.
_chk_help_reachable() {
  local rc=0 hub="rootfs/etc/skel/.config/quickshell/w/modules/hub"
  [[ -d "$hub" ]] || return 0
  local src
  # Registry entries pairing a `source:` with a `help:` — the two sit in one
  # object, so a 2-line window over the file catches both orderings.
  while IFS= read -r src; do
    [[ -f "$hub/$src" ]] || { echo "  hub help: registry names a missing panel '$src'"; rc=1; continue; }
    grep -q 'signal[ \t]\+focusHeader()' "$hub/$src" || {
      echo "  hub help: '$src' has a help button but no 'signal focusHeader()' —"
      echo "      the mouse reaches it and the keyboard cannot"; rc=1; }
  done < <(awk '
      # A registry entry is one { route: … } object and WRAPS across lines, so a
      # per-line grep would silently match nothing (it did — 2026-09-09). Buffer
      # from "{ route:" to the closing "}," and test the whole object.
      /\{ route:/ { buf = $0; inrec = 1 }
      inrec && !/\{ route:/ { buf = buf " " $0 }
      inrec && /\},[ \t]*$/ {
        if (buf ~ /help:/ && match(buf, /panels\/[A-Za-z]+\.qml/))
          print substr(buf, RSTART, RLENGTH)
        inrec = 0
      }
    ' "$hub/HubRegistry.qml" | sort -u)
  # Per-tab overrides: a panel declaring its own `help` property is opted in too.
  while IFS= read -r src; do
    grep -q 'signal[ \t]\+focusHeader()' "$src" || {
      echo "  hub help: '${src#"$hub"/}' declares a per-tab help override but no"
      echo "      'signal focusHeader()' — the button is mouse-only there"; rc=1; }
  done < <(grep -rl 'readonly property var help:' "$hub/panels" 2>/dev/null | sort)
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
  _chk_heading_slugs || rc=1
  _chk_help_anchors || rc=1
  _chk_help_reachable || rc=1
  _chk_dev_bleed || rc=1
  _chk_links || rc=1

  devtools/usr/local/bin/w-docs-refgen --check > /dev/null || {
    echo "  generated reference docs are stale (see w-docs-refgen --check above)"; rc=1; }

  [[ $rc == 0 ]] && echo "  docs tree: $(count_md) pages consistent"
  return $rc
}

count_md() { _doc_pages | wc -l; }
