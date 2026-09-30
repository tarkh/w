---
title: The AI assistant
section: guide
order: 9
summary: Opening the assistant, profiles for different setups, hosts and providers, where API keys are kept, how much it may do on its own, and the optional advanced stack.
sources:
  - path: .claude/library/w-ai.md
    sha256: 03a5fdbf137556293d33480cd23ea657356315aea50fe6b2a83a5271c7ef2359
  - path: .claude/library/ai-integration.md
    sha256: f32aa75761dcd502adb75af9854472c0c4385f7794e9acc932f5c06d7775fa46
  - path: .claude/library/pack-comfyui.md
    sha256: 39359310301024f530ea09fad70d83c56e60265cfe9951ef5f1ef919a3e4a2ad
  - path: .claude/library/pack-invokeai.md
    sha256: 5abb48e8ed21e81603e71e780be300ed84b9e15d335acb58453fd330f70dc41d
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

The third-party CLIs W can drive are Claude Code, Codex and OpenCode. W hands
them its tools and its identity only when it launches them itself — start
`claude`, `codex` or `opencode` by hand in a project of your own and you get
the plain tool, with nothing of W attached. OpenCode is the one with its own
subscription (Zen) *and* a direct line to dozens of other providers at once —
pick *subscription* for Zen, one of the providers W already manages a key for,
or set up anything else straight in OpenCode itself (`opencode auth login`).

Some packs bring tools of their own for the assistant — the **graphics** pack,
for instance, lets it draw in Inkscape and edit inside GIMP. These arrive the
same way, at launch, for every host; `w-ai status` lists them under
**MCP extra**. One shown as *missing* is installed on the machine but not set up
for your account yet: `w-pack setup <pack>` (no password) and a fresh session.

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
your behalf. For the same reason W's own tools (including the ones an installed
pack adds, like the Inkscape or GIMP helpers) never wait on the host's
per-tool confirmation: the assistant calls them directly, and anything
privileged still stops at that same prompt. MCP servers you register yourself
keep the host's normal confirmation flow.

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

## ComfyUI

Generation of images and video is a separate optional bundle — see
[the packs guide](packs.md). It runs ComfyUI as a system service: a node-based
editor and backend combined, on `http://127.0.0.1:8188/`. Open it from the app
menu (which starts the service, asks for the admin password the first time and
opens the browser) or start it yourself with `systemctl start comfyui`.

- **GPU matching:** the engine is installed with the driver your hardware needs
  (`nvidia` / `amd` / `intel` Arc / `cpu`), detected automatically.
- **Adding nodes:** the node manager is built in and already switched on, so a
  node pack you are missing is installed from the interface itself — nothing to
  clone, nothing to install by hand. It only works while ComfyUI answers on
  `127.0.0.1`: expose the engine to the network and the manager stops installing
  anything, which is its own safety rule rather than W's.
- **Shared model store:** models are downloaded into
  `/var/lib/w/ai-models`, a snapshot-excluded store shared by the whole machine;
  every account set up for the pack writes there.
- **Where your results land:** `/var/lib/w/comfyui/data/output` (under the engine
  directory, wherever it was installed). You can open that folder in the file
  manager, collect renders and drop source images into `input/` next to it —
  access comes with the `w-ai` group the bundle adds you to, which takes effect
  at your next login.
- **The assistant can help** with ComfyUI workflows, model placement and the
  service — load the *comfyui* knowledge pack when asked about local generation.

## InvokeAI

A second, independent generation bundle with a different interface: InvokeAI
works on a layered **canvas** (inpainting, outpainting, regional prompts) with a
gallery and boards, where ComfyUI builds a node graph. It runs as a system
service on `http://127.0.0.1:9090/`; open **InvokeAI** from the app menu or run
`systemctl start invokeai`.

- **GPU matching:** the PyTorch build is chosen for your hardware at install
  (`nvidia` / `amd` / `intel` Arc / `cpu`), the same way as for ComfyUI.
- **Same models as ComfyUI:** every model file in the shared store
  (`/var/lib/w/ai-models/checkpoints`, `loras`, `vae`, …) is registered in
  InvokeAI where it lies — nothing is copied. Added a file? Run
  `sudo systemctl reload invokeai` and it appears after a short check. Files
  InvokeAI cannot use are skipped quietly.
- **Its own downloads** from the Model Manager tab go to
  `/var/lib/w/ai-models/invokeai`. Removing a model inside InvokeAI deletes a
  file only from there; a shared-store model is just hidden until next start.
- **Where your results land:** `/var/lib/w/invokeai/data/outputs`, reachable
  from the file manager with the same `w-ai` group (next login).
- **Tuning** (memory limits, attention, precision) lives in
  `/var/lib/w/invokeai/data/invokeai.yaml`; the example file next to it lists
  every setting.
