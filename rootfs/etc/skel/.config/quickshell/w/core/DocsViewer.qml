pragma Singleton

// W Linux — the documentation viewer's resolver: a docs page + optional deep
// link → a rendered infobox card.
//
// Docs live at /usr/share/doc/w (rootfs/usr/share/doc/w); index.md lands here.
// openPage() is the ONE entry point for every surface that wants to show
// documentation:
//
//   • the hotkey (catalog token "docs", SUPER+F1) → DocsViewer.openIndex();
//   • the Hub's "help on this panel" button (HubHeader, fed by HubRegistry.help)
//     → openPage(page, anchor) — anchor is a GitHub-style heading slug;
//   • links inside a rendered page (relative .md navigate, http opens).
//
// What happens to a page before it reaches the card:
//   1. LOCALE RESOLUTION: the path is first tried under the active UI language
//      (Strings.lang, the 2-letter system locale). A missing translation falls
//      back to the English page — W ships English plus whatever translation
//      trees exist (ru/); a locale with no tree of its own (fr) reads English.
//   2. FRONTMATTER STRIPPING: the YAML block belongs to the site generator and
//      the drift checker (title/summary/sources sha256 anchors to .claude/
//      library — DEV-ONLY machinery); the card renders the body.
//   3. DEEP LINK: an anchor slug selects ONE section — from its heading to the
//      next heading of the same-or-higher level — instead of the whole page.
//      The card is a ~720px dialog; the section that answers the question is
//      what a deep link is FOR. A missing anchor (or a not-yet-translated one)
//      degrades to the whole page, never to an error.
//   4. IMAGE ABSOLUTIZATION: relative image targets are rewritten to absolute
//      file:// URLs against the page's own directory, because the card's Text
//      resolves markdown resources against the QML file, not against the doc.
//
// FileView's loadFailed drives the locale fallback: try <lang>/<page>, then
// <page> — no filesystem probing anywhere.
//
// Search (an explicit future option, not built yet): every page carries a
// one-line summary in its frontmatter and lives on disk as plain text, so a
// future search indexes titles/summaries/bodies without touching this viewer.

import Quickshell
import Quickshell.Io
import QtQuick
import qs.core

Singleton {
    id: root

    property string wantedPage: ""      // docs-root-relative, normalized
    property string wantedAnchor: ""    // slug, "" = whole page
    property var tries: []              // absolute candidate paths, first-to-try order

    // Docs root on the machine. W_DOCS_DIR is a dev/testing seam (live probe
    // of a repo-side tree without one installed there); unset → the shipped path.
    readonly property string dir: Quickshell.env("W_DOCS_DIR") || "/usr/share/doc/w"

    function openIndex() {
        root.openPage("index.md", "", "");
    }

    // page — docs-root-relative path ("guide/updates.md"); anchor — a heading
    // slug ("" = whole page); fromDir — the docs-root-relative directory of the
    // page a relative link was clicked on.
    function openPage(page, anchor, fromDir) {
        const full = (fromDir ? fromDir + "/" : "") + page;
        const candidates = [];
        const lang = Strings.lang;
        // A translation links within its own tree (relative links under ru/
        // resolve into ru/), so only an unprefixed path gets the locale-first
        // candidate.
        if (lang !== "en" && !full.startsWith(lang + "/"))
            candidates.push(root.dir + "/" + lang + "/" + full);
        candidates.push(root.dir + "/" + full);
        root.wantedPage = full;
        root.wantedAnchor = anchor || "";
        root.tries = candidates;
        root._next();
    }

    function _next() {
        if (root.tries.length === 0) {
            Overlays.openInfobox({
                title: Strings.t("docs.notFoundTitle"),
                bodyMarkdown: Strings.t("docs.notFoundBody"),
                glyph: root.helpGlyph
            });
            return;
        }
        view.path = root.tries.shift();
        view.reload();
    }

    FileView {
        id: view
        onLoaded: root._render(text())
        onLoadFailed: root._next()
    }

    // One glyph for "help" everywhere (Hub's help button, docs cards) — verified
    // against the shipped Nerd Font's cmap (md-help_circle_outline).
    readonly property string helpGlyph: String.fromCodePoint(0xf0625)

    // GitHub's heading slug, restricted to what is unambiguous without Unicode
    // property classes (QML's regex engine does not support \p{}): lowercase,
    // ASCII punctuation removed, runs of spaces → single '-'. Repeats get the
    // GitHub -1/-2 suffixes. Translations keep their non-ASCII letters — an
    // anchor written into them must match this same algorithm.
    function slug(text) {
        return text.toLowerCase()
            .replace(/[!-/:-@[-`{-~]/g, "")
            .trim()
            .replace(/ +/g, "-");
    }

    function _render(raw) {
        // Frontmatter off; the title feeds the card + section headings logic.
        let fm = "";
        let body = raw;
        const m = /^-{3}[ \t]*\r?\n([\s\S]*?)\r?\n-{3}[ \t]*\r?\n?/.exec(raw);
        if (m) {
            fm = m[1];
            body = raw.slice(m[0].length);
        }
        const tm = /^title:[ \t]*(.+)$/m.exec(fm);
        const pageTitle = tm ? tm[1].trim().replace(/^["']|["']$/g, "") : root.wantedPage;

        let title = pageTitle;
        if (root.wantedAnchor) {
            const sec = root._section(body, root.wantedAnchor);
            if (sec) {
                title = sec.heading;
                body = sec.body;
            }
        }

        const pageDir = root._dirOf(root.wantedPage);
        body = body.replace(/(!\[[^\]]*\]\()(?!\w+:|\/|#[^)]*)([^)\s]+)/g,
            (all, pre, src) => pre + "file://" + root.dir + "/" + pageDir + "/" + src);

        // The card's markdown importer has flat block margins: headings come
        // with NONE, list and hr containers sit flush against surrounding
        // text, and the list MARKER follows the source bullet char (`-` filled
        // disc, `*` hollow circle, `+` square — probed against the shipped Qt).
        // All uniform-only, source-agnostic block rules live in _spaceUp:
        // spacer paragraphs (U+200B keeps the width exact) around headings,
        // code fences, rules and list runs, and every bullet marker becomes
        // the disc one. Pages on disk stay untouched canonical GFM.
        body = root._spaceUp(body);

        const actions = [];
        if (root.wantedAnchor) {
            const full = {};
            full.label = Strings.t("docs.fullPage");
            full.exec = () => root.openPage(root.wantedPage, "", "");
            actions.push(full);
        }
        // Back returns to the index (locale-resolved). Everything except the
        // index itself gets it; the header renders it compactly left of the
        // title, so "Contents"/glyph duplication is unnecessary.
        const back = (root.wantedPage === "index.md" || root.wantedPage.endsWith("/index.md"))
            ? null : { exec: () => root.openIndex() };
        Overlays.openInfobox({
            title: title,
            bodyMarkdown: body,
            tall: true,
            back: back,
            actions: actions.length ? actions : undefined,
            onLink: (link) => root._openLink(link, pageDir)
        });
    }

    // Uniform block rules for the card's flat-margin importer. One empty
    // spacer line (≈ one body line high) above/below: headings, fenced code,
    // horizontal rules, and whole LISTS (the <ul>/<ol> container itself gets
    // zero margin from the importer — only the items between them breathe).
    // Also normalizes every bullet marker to `-`, so no source can ship
    // hollow-circle or square markers. Inside a fence nothing is touched.
    // Paragraph blocks are Qt's own 7px pair — untouched.
    function _spaceUp(src) {
        const SP = "\u200b";
        const out = [];
        const lines = src.split("\n");
        const gap = () => {
            if (out.length && out[out.length - 1] !== SP) out.push(SP);
        };
        const bullet = /^[ \t]*([*+-])[ \t]+/;
        const ordered = /^[ \t]*\d{1,9}[.)][ \t]+/;
        let fence = false, inList = false;
        for (let line of lines) {
            if (/^```/.test(line)) {
                if (!fence) gap();
                out.push(line);
                if (fence) gap();
                fence = !fence;
                inList = false;
                continue;
            }
            if (fence) {
                out.push(line);
                continue;
            }
            if (/^[ \t]*-{3,}[ \t]*$/.test(line) || /^[ \t]*\*{3,}[ \t]*$/.test(line)) {
                gap();
                out.push(line);
                gap();
                inList = false;
                continue;
            }
            // A list item, either marker class. ONE state for both: the run
            // stays open through items, loose blanks and indented
            // continuations, and gets exactly one spacer above the first item
            // and one after the last — never between the items.
            const bm = bullet.exec(line);
            if (bm || ordered.test(line)) {
                if (bm && bm[1] !== "-")
                    line = line.slice(0, bm.index) + " - " + line.slice(bm.index + bm[1].length);
                if (!inList) {
                    gap();
                    inList = true;
                }
                out.push(line);
                continue;
            }
            if (inList && line.trim() === "") {
                out.push(line);          // loose list — run continues
                continue;
            }
            if (inList && /^[ \t]{2,}/.test(line)) {
                out.push(line);          // indented continuation of a list item
                continue;
            }
            if (inList) {
                gap();
                inList = false;
            }
            if (/^#{1,6}[ \t]+\S/.test(line)) {
                gap();
                out.push(line);
                out.push(SP);
                continue;
            }
            out.push(line);
        }
        if (inList) gap();
        return out.join("\n");
    }

    // Link dispatch: documentation links navigate, the rest are external.
    function _openLink(link, pageDir) {
        if (/^https?:/.test(link)) {
            Qt.openUrlExternally(link);
            return;
        }
        if (/^file:/.test(link)) return;   // an image or another resource, not a page
        let page = "", anchor = "";
        const h = link.indexOf("#");
        if (h >= 0) {
            page = link.slice(0, h);
            anchor = link.slice(h + 1);
        } else {
            page = link;
        }
        if (page === "") page = root.wantedPage;
        root.openPage(page, anchor, pageDir);
    }

    // The section from the heading matched by slug (GitHub's -1/-2 dedup
    // included) to the next heading of the same or higher level.
    function _section(body, anchor) {
        const lines = body.split("\n");
        const dup = {};
        let start = -1, level = 0, heading = "";
        for (let i = 0; i < lines.length; i++) {
            const hm = /^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$/.exec(lines[i]);
            if (!hm) continue;
            let sl = root.slug(hm[2]);
            if (dup[sl] !== undefined) {
                dup[sl] = dup[sl] + 1;
                sl = sl + "-" + dup[sl];
            } else {
                dup[sl] = 0;
            }
            if (start < 0) {
                if (sl === anchor) {
                    start = i;
                    level = hm[1].length;
                    heading = hm[2];
                }
            } else if (hm[1].length <= level) {
                // The heading itself is the card's title — the body starts after
                // it, or the section repeats the header line twice.
                return { heading: heading, body: lines.slice(start + 1, i).join("\n").trim() };
            }
        }
        return start < 0 ? null : { heading: heading, body: lines.slice(start + 1).join("\n").trim() };
    }

    function _dirOf(p) {
        const i = p.lastIndexOf("/");
        return i < 0 ? "" : p.slice(0, i);
    }
}
