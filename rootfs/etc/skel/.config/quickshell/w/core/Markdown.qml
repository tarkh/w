pragma Singleton

// W Linux — the shell's Markdown renderer: canonical GFM in, themed rich text out.
//
// Everything the infobox shows as a body goes through here — the documentation
// viewer's pages (core/DocsViewer) and the short statement cards (assistant gate,
// layout confirmation). One renderer, so a paragraph breathes the same everywhere.
//
// WHY NOT JUST `textFormat: MarkdownText`. Qt's markdown importer is md4c and it
// renders well, but the result is unstyleable from QML: headings and list
// containers import with ZERO block margins (so a paragraph sits flush against the
// list above it), inline HTML in a paragraph is swallowed rather than parsed (so no
// span can be coloured), fenced code arrives as plain text with no ground of its
// own, and — the one that forced this — `TextEdit` has no `linkColor`, so a
// selectable body would paint every link in Qt's built-in blue, off-theme.
//
// WHAT THIS DOES INSTEAD. Qt still does the parsing; we take its output as HTML and
// restyle it before it is shown:
//
//   1. code is lifted OUT first (fenced blocks and inline spans → sentinels), so no
//      later rule can rewrite anything a user is meant to read verbatim;
//   2. the markdown goes through a headless TextEdit, which re-serialises it as
//      HTML — Qt's own importer, no second markdown parser in this project;
//   3. the HTML is restyled: the baked `Sans Serif 9pt` is stripped so the item's
//      own font governs, anchors get the theme's ink instead of Qt's blue, and
//      every block gets real CSS margins (this is the vertical rhythm — no more
//      zero-width-space spacer paragraphs, which md4c merged into the neighbouring
//      block as often as not);
//   4. inline code goes back as a small plaque, and the body is SPLIT at the
//      fence sentinels into an ordered list of chunks — prose (rich text) and
//      code (its own item, on its own ground, selectable). Shell is the only
//      language W's own pages use, and it gets a one-pass tokenizer (comments,
//      quoted strings, flags, `w-*` commands) — not a highlighting engine.
//
// The rules are UNIFORM and source-agnostic: pages on disk stay canonical GFM, with
// no rendering hints written into them. Colours resolve from the active theme at
// render time; a card open across a live theme switch keeps the colours it was
// built with, which is invisible in practice because the card is transient.
import Quickshell
import QtQuick
import qs.core

Singleton {
    id: root

    // Private-use sentinels: code is parked under these while the markdown is
    // converted, so a rule meant for prose can never reach into a command. They
    // cannot occur in a source page — that is what the private-use area is for.
    readonly property string sFence: String.fromCharCode(0xE000)
    readonly property string sCode: String.fromCharCode(0xE001)
    readonly property string sEnd: String.fromCharCode(0xE002)

    // ONE KNOB for the whole vertical rhythm. Every block margin below is this
    // multiplied by Qt's own baseline for that block, so "a bit more air
    // everywhere" is this number and nothing else — no per-block tuning, and the
    // proportions between a paragraph, a heading and a list stay as designed.
    readonly property real air: 1.5

    // The headless converter. A TextEdit is the only thing in Qt Quick that will
    // import markdown and hand back HTML (`getFormattedText` re-serialises in the
    // format set at the time of the call), and it does not need a window or a
    // visual parent to do it — the work happens in its QTextDocument.
    readonly property Item conv: TextEdit { visible: false; width: 0 }

    // Escape for the code paths (the only text this file injects verbatim). Runs
    // of two or more spaces become non-breaking, which is what keeps a `usage()`
    // block's column alignment when the card is narrower than the source line;
    // single spaces stay breakable, so a long command still wraps inside its
    // plaque instead of running out of it.
    function _escape(t) {
        return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                .replace(/ {2,}/g, (run) => "&nbsp;".repeat(run.length));
    }

    // Shell highlighting, one pass, four roles: comment · quoted string · option
    // flag · a `w-*` command. Deliberately not a language engine — every fence in
    // W's own documentation is shell (commands, their output, or a config
    // snippet), and an unrecognised token simply renders as body text.
    function _highlight(code) {
        // The quoted-string rule is deliberately narrow: a quote may not open in
        // the middle of a word and may not span a line. Prose inside a help text
        // is full of apostrophes ("a host's contract"), and a greedy rule turned
        // everything between two of them — across lines — into one string.
        const re = /(#[^\n]*)|(^|[^\w'"])('[^'\n]*'|"[^"\n]*")|(^|\s)(--?[A-Za-z][\w-]*)|(\bw-[a-z]+(?:-[a-z]+)*\b)/g;
        let out = "";
        let last = 0;
        let m;
        while ((m = re.exec(code)) !== null) {
            out += root._escape(code.slice(last, m.index));
            if (m[1])
                out += '<span style="color:' + Colors.muted + '">' + root._escape(m[1]) + "</span>";
            else if (m[3])
                out += root._escape(m[2]) + '<span style="color:' + Colors.accentInk + '">'
                     + root._escape(m[3]) + "</span>";
            else if (m[5])
                out += root._escape(m[4]) + '<span style="color:' + Colors.accentInk + '">'
                     + root._escape(m[5]) + "</span>";
            else if (m[6])
                out += '<span style="color:' + Colors.iconTint + '">' + root._escape(m[6]) + "</span>";
            last = m.index + m[0].length;
        }
        return out + root._escape(code.slice(last));
    }

    // md → an ordered list of chunks, `[{ code: bool, html: string }, …]`. The one
    // entry point; the caller renders prose chunks as rich text and code chunks as
    // whatever it wants a code block to be.
    //
    // Why a LIST and not one HTML string: a fence used to come back as a `<table>`
    // inside the body, and Qt's rich text gives a table frame no margin of its own
    // — the paragraph above it sat ON the plaque. Separate items make the gap
    // ordinary layout spacing. It is also what lets the caller make code, and only
    // code, selectable: the body as a whole must stay a `Text` (a long document in
    // a `TextEdit` loses whole blocks — see the comment in Infobox.qml).
    function render(md) {
        if (!md) return "";
        // Plain JS locals, NOT properties: this function is called from a binding
        // (the infobox body), and a property written mid-evaluation that the same
        // expression later reads is a binding loop.
        const fences = [];
        const codes = [];

        // ── 1. lift the code out ──────────────────────────────────────────────
        // A fence becomes a paragraph of its own so it survives as a block; an
        // inline span stays inline. The info string (```sh) is dropped: shell is
        // the only language these pages carry, and the tokenizer assumes it.
        let src = md.replace(/```[^\n]*\n([\s\S]*?)```[ \t]*/g, (all, code) => {
            fences.push(code.replace(/\n+$/, ""));
            return "\n" + root.sFence + (fences.length - 1) + root.sEnd + "\n";
        });
        src = src.replace(/`([^`\n]+)`/g, (all, code) => {
            codes.push(code);
            return root.sCode + (codes.length - 1) + root.sEnd;
        });

        // ── 2. let Qt parse it ────────────────────────────────────────────────
        root.conv.textFormat = TextEdit.MarkdownText;
        root.conv.text = src;
        root.conv.textFormat = TextEdit.RichText;
        let html = root.conv.getFormattedText(0, root.conv.length);

        // ── 3. restyle ────────────────────────────────────────────────────────
        // The importer bakes the default UI font into every span; strip it so the
        // body's own font.family / font.pixelSize governs the whole card.
        html = html.replace(/font-family:'[^']*';[ \t]*/g, "")
                   .replace(/font-size:\d+pt;[ \t]*/g, "");
        // Anchors: Qt paints them in its own blue, and TextEdit has no linkColor
        // to override it with.
        html = html.replace(/color:#[0-9a-fA-F]{6};/g, "color:" + Colors.accentInk + ";");
        // Vertical rhythm. Qt gives paragraphs a 6px pair and gives headings and
        // list CONTAINERS nothing at all, which is why a paragraph used to sit
        // flush under a bullet list. Adjacent block margins do NOT collapse in
        // QTextDocument, so the gap between two paragraphs is the pair added up.
        const sp = (n) => Math.round(n * root.air);
        html = html.replace(/margin-top:\d+px;[ \t]*margin-bottom:\d+px;/g,
                            "margin-top:" + sp(6) + "px; margin-bottom:" + sp(6) + "px;");
        html = html.replace(/<h([1-6]) style="/g,
                            '<h$1 style=" margin-top:' + sp(16) + "px; margin-bottom:" + sp(7) + 'px;');
        html = html.replace(/<(ul|ol) style="/g,
                            '<$1 style="margin-top:' + sp(7) + "px; margin-bottom:" + sp(11) + 'px;');

        // ── 4. put the code back, styled ──────────────────────────────────────
        const reCode = new RegExp(root.sCode + "(\\d+)" + root.sEnd, "g");
        html = html.replace(reCode, (all, i) =>
            '<span style="font-family:' + Fonts.mono + "; font-size:13px; background-color:"
            + Colors.inputBg + ';">&nbsp;' + root._escape(codes[parseInt(i)]) + "&nbsp;</span>");
        // ── 5. split the body at the fences ───────────────────────────────────
        // The fence's own paragraph becomes the boundary. Line breaks inside a code
        // chunk come from <br/> and its indentation from the non-breaking runs
        // _escape leaves, so a long `usage()` line wraps inside the block instead of
        // running out of it. 13px, not the body's 14: a monospace face reads a size
        // larger than a proportional one at the same pixel height, and the generated
        // reference pages are laid out for 80 columns — which is what fits the card's
        // 720px at this size and does not at 14.
        const reFence = new RegExp("<p[^>]*>[ \\t]*(?:<span[^>]*>)?" + root.sFence
                                   + "(\\d+)" + root.sEnd + "(?:</span>)?[ \\t]*</p>", "g");
        const out = [];
        let last = 0;
        let m;
        while ((m = reFence.exec(html)) !== null) {
            const before = html.slice(last, m.index);
            if (before.replace(/<[^>]*>/g, "").trim().length > 0)
                out.push({ code: false, html: before });
            out.push({
                code: true,
                html: '<span style="font-family:' + Fonts.mono + '; font-size:13px;">'
                      + root._highlight(fences[parseInt(m[1])]).replace(/\n/g, "<br/>")
                      + "</span>"
            });
            last = m.index + m[0].length;
        }
        const rest = html.slice(last);
        if (rest.replace(/<[^>]*>/g, "").trim().length > 0)
            out.push({ code: false, html: rest });
        return out;
    }
}
