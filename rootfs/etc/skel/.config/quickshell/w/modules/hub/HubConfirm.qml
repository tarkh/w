// W Linux — Hub confirmation modal.
// The Hub's one way to ask "are you sure?" before something destructive: HubPrompt's
// chrome (tint + card) filled with a heading, the caller's own explanation of what is
// about to happen, and a row of pills ending in Cancel. The caller supplies the text
// AND the actions, because a good confirmation names the specific consequence rather
// than asking a generic question — and because one row can offer two DIFFERENT
// destructive answers (Packs: take a bundle off the machine, or only out of my own
// account) that differ in privilege and in blast radius.
//
//   confirm.ask({
//       title:   "Remove containers?",
//       message: "...what W will undo...",
//       note:    "...the muted caveat...",           // optional
//       actions: [{ key: "remove", label: "Remove from machine" },
//                 { key: "unsetup", label: "Just for me" }],
//   });
//   onChose:     (key) => ...    // one of the action keys
//   onCancelled: ...             // Cancel pill, Esc/Backspace, or a click outside
//
// Keyboard: the modal takes no real Qt focus (it holds no text field), so the panel
// keeps it and forwards — `if (confirm.open) { confirm.handleKey(e); return; }` as the
// first line of its Keys.onPressed, the same local-guard shape every other panel uses
// for a prompt (quickshell-hub.md's Ф-Keyboard gotcha 14). The ring STARTS on Cancel,
// not on the first action: a confirmation reached by a single Delete keypress must not
// also be answerable by a single Enter.
//
// `onDismissed` is spoken for here (it routes HubPrompt's outside-click into cancel);
// consumers use onCancelled, and re-declaring onDismissed at the use site would
// override this one rather than add to it.
import QtQuick
import qs.core

HubPrompt {
    id: root

    // Body text, set by ask(). Split in two so the caller can put the consequence in
    // normal ink and the caveat in muted ink without composing markup.
    property string message: ""
    property string note: ""
    // [{ key, label }] — rendered in order, all destructive (Cancel is added here).
    property var actions: []

    signal chose(string key)
    signal cancelled()

    function ask(spec) {
        root.title   = spec.title   || "";
        root.message = spec.message || "";
        root.note    = spec.note    || "";
        root.actions = spec.actions || [];
        root.focusIndex = root.actions.length;   // Cancel — see the header note
        root.open = true;
    }

    function cancel() { root.open = false; root.cancelled(); }
    function pick(key) { root.open = false; root.chose(key); }

    onDismissed: root.cancel()

    // ── Local roving over the pill row (actions…, then Cancel) ──────────────────
    property int focusIndex: 0
    readonly property int focusCount: root.actions.length + 1
    function focusPill(i) { root.focusIndex = Math.max(0, Math.min(i, root.focusCount - 1)); }

    function handleKey(e) {
        switch (e.key) {
        case HubNavKeys.back:
        case Qt.Key_Escape:
        case Qt.Key_Backspace:
            root.cancel(); e.accepted = true; return;
        case HubNavKeys.right:
        case HubNavKeys.down:
            root.focusPill(root.focusIndex + 1); e.accepted = true; return;
        case HubNavKeys.left:
        case HubNavKeys.up:
            root.focusPill(root.focusIndex - 1); e.accepted = true; return;
        case HubNavKeys.confirm:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (root.focusIndex < root.actions.length) root.pick(root.actions[root.focusIndex].key);
            else root.cancel();
            e.accepted = true; return;
        }
        // Anything else is swallowed rather than left to bubble to the panel behind
        // the tint — the modal is modal.
        e.accepted = true;
    }

    // ── Body (lands in HubPrompt's card Column, under its title) ────────────────
    Text {
        visible: root.message.length > 0
        width: parent.width
        text: root.message
        color: Colors.text
        font.family: Fonts.family
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    Text {
        visible: root.note.length > 0
        width: parent.width
        text: root.note
        color: Colors.muted
        font.family: Fonts.family
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    // Flow, not Row: two spelled-out destructive verbs plus Cancel can outgrow the
    // card in a long language, and wrapping beats clipping.
    Flow {
        width: parent.width
        spacing: 8

        Repeater {
            model: root.actions
            WPill {
                required property int index
                required property var modelData
                borderWidth: HubConfig.border
                label: modelData.label
                danger: true
                focused: root.focusIndex === index
                onClicked: root.pick(modelData.key)
            }
        }

        WPill {
            borderWidth: HubConfig.border
            label: Strings.t("hub.cancel")
            focused: root.focusIndex === root.actions.length
            onClicked: root.cancel()
        }
    }
}
