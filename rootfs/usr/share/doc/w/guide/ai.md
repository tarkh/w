---
title: The AI assistant
section: guide
order: 9
summary: Opening the assistant, profiles for different setups, hosts and providers, where API keys are kept, how much it may do on its own, and the optional advanced stack.
sources:
  - path: .claude/library/w-ai.md
    sha256: cf1f9571d398b0c8958eb9eb64703fb0c8e16d7fe3c4fb13b3e9af2302b71ba2
  - path: .claude/library/ai-integration.md
    sha256: a6d74379bf5431af871ca58676b41cf5c9130ec6cfe0faf20d1edec104711d16
---

W ships an AI assistant that runs in a terminal and can drive the machine
through W's own tools — read the display layout, switch a power profile, look
at logs. It is optional in every sense: nothing depends on it, and it does
nothing until you configure a model for it.

<kbd>Super+W</kbd> opens the ask palette; typing a question there hands off to a
full session. `w-ai` in a terminal is the same thing, and `w-ai status` prints
what is configured right now.

## Profiles

**Hub → AI** is a list of **profiles**. A profile is a saved combination of
*which program runs the assistant*, *which model it talks to*, and *how much it
may do without asking*. Tapping an inactive profile makes it active immediately;
the active one carries a checkmark.

The point of profiles is switching setups without editing anything: keep one for
a cloud model and one that runs entirely on your own machine, and flip between
them in a tap. **New profile…** creates one, optionally copying an existing one
as a starting point.

The chevron on a row expands the editor. Every change applies as you pick it —
there is no save button — and none of it asks for your password: this is a
personal setting, like a keyboard layout.

## Host, provider and model

- **Host** is the program that actually runs the session. W ships with one
  included; the others are third-party CLIs with their own login and their own
  updater, so they are installed per user, on request.
- **Provider** is the service behind the model. What the dropdown offers adapts
  to the host you picked — for a CLI that has its own subscription login it
  offers *subscription*, which means W passes no API key at all and the vendor
  bills your plan rather than per token.
- **Model** is the model id. It is **required** for the included host — leave it
  empty and the session will not start. For a provider CLI it is marked
  *optional*, because that CLI picks its own.

When the chosen host needs something, a row appears right underneath it saying
so — **not installed** with an **Install** button, or **not signed in** with
**Sign in**. Both open a terminal and run the step for you. Installing a host
does not need your password: it lands in your own account.

If a session refuses to start, `w-ai ready` in a terminal answers why in one
word.

## API keys

Where the provider needs a key, the expanded profile shows an **API key** row:
whether one is stored, a masked field to paste one into, and a button to remove
it. The key goes into the system keyring, never into a file on disk, and it
belongs to the *provider* rather than to the profile — every profile using that
provider shares it. From a terminal the same thing is `w-ai key set`.

One trap worth naming: if you are using a CLI on its **subscription** login, do
not also store an API key for it. With a key present the CLI switches to
per-token API billing.

## Mode: how much it does on its own

**Mode** is *chat*, *approve*, *smart approve* or *auto*, in increasing order of
independence: from answering only, through asking before each action, to acting
on its own.

This is a convenience setting, not the security boundary. Anything that touches
the system as administrator stops at W's own password or fingerprint prompt no
matter which mode you picked — *auto* cannot authorise a privileged change on
your behalf.

**Tool surface** next to it controls how much of W's own tooling the assistant
is offered. Leave it on *auto*.

## Advanced

The **Advanced** section adds capabilities that need extra software: **Web
search**, **Reader** (fetching and reading a page), **Semantic memory**
(searching its own memory by meaning rather than by keyword) and **Local
models**.

These come from an optional bundle. Until it is installed the four rows are
greyed out with *Requires the ai-extra pack* and a single **Install** button
that does it for you — see [the packs guide](packs.md). Afterwards each row
switches on independently, and the ones W cannot enable for you report why:
that the local model runner is not running, or that a model still has to be
downloaded. Choosing *brave* for web search reveals its own API-key field, which
works exactly like the one above.

Nothing here is required for an ordinary chat session; it is the difference
between an assistant that can look things up and one that can only answer.
