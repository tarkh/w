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
//      what a deep link is FOR. The anchor a Hub help: button carries is fixed
//      at the EN slug (the registry has no per-locale copy); a loaded page may
//      declare a frontmatter `anchors:` map from that EN slug to its own
//      heading's slug, translated before the section search. A missing anchor
//      (mapped or not) degrades to the whole page, never to an error.
//   4. IMAGE ABSOLUTIZATION: relative image targets are rewritten to absolute
//      file:// URLs against the page's own directory, because the card's body
//      resolves markdown resources against the QML file, not against the doc.
//   5. RENDERING: handed to the infobox as markdown, which core/Markdown turns
//      into themed rich text (block rhythm, code plaques, link colour).
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
        // Deferred, not a direct call: reassigning this SAME FileView's `path`
        // synchronously from inside its own loadFailed handler races Quickshell's
        // internal operation teardown — the retry gets silently dropped ("got
        // operation finished from dropped operation"), neither loaded nor
        // loadFailed fires for it, and the card never opens. Reproduced headless
        // (quickshell -p) against a real missing-then-present candidate pair:
        // synchronous retry drops every time, Qt.callLater's one-tick defer does
        // not. Only ever exercised with 2+ candidates — i.e. a non-English
        // locale, which is why English (always one candidate) never hit it.
        onLoadFailed: Qt.callLater(() => root._next())
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

        // A translated page's headings slug differently from the EN anchor a
        // Hub help: button carries (fixed at the registry, not per-locale), so
        // it may declare a frontmatter map from that EN slug to its own heading's
        // slug. Checked for completeness by docs.sh's _chk_help_anchors.
        let anchor = root.wantedAnchor;
        const am = /^anchors:\r?\n((?:^[ \t]+\S.*\r?\n?)+)/m.exec(fm);
        if (am && anchor) {
            const esc = anchor.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            const p = new RegExp("^[ \\t]+" + esc + ":[ \\t]*(.+?)[ \\t]*$", "m").exec(am[1]);
            if (p) anchor = p[1].trim();
        }

        let title = pageTitle;
        if (anchor) {
            const sec = root._section(body, anchor);
            if (sec) {
                title = sec.heading;
                body = sec.body;
            }
        }

        const pageDir = root._dirOf(root.wantedPage);
        body = body.replace(/(!\[[^\]]*\]\()(?!\w+:|\/|#[^)]*)([^)\s]+)/g,
            (all, pre, src) => pre + "file://" + root.dir + "/" + pageDir + "/" + src);

        // Block rhythm, code highlighting and link colour are NOT this file's
        // business: every infobox body goes through core/Markdown, so a docs page
        // and a statement card breathe identically. Pages on disk stay canonical
        // GFM — no rendering hints are written into them.

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
