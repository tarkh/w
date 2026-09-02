# Contributing to W Linux

Thanks for looking. Bug reports, questions and patches are all welcome.

Before anything else, one thing about this repository is unusual and worth two
minutes of your time, because it changes what happens to your pull request.

---

## How this repository is published

W is developed in a private repository and **published here as a series of release
snapshots**. Each commit on `main` is one release: a complete, tested tree, tagged
`vX.Y.Z`, with the changelog in the commit message. There is no day-to-day commit
history here, and there never will be.

Two consequences:

**This branch is append-only.** Installed W machines follow it with
`git pull --ff-only`. A rewritten or force-pushed history would strand every one of
them, so it does not happen.

**Pull requests are landed by hand, not merged with the button.** Merging a PR
here would put a non-release commit on the branch and break the model above.
Instead your patch is applied to the development tree, reviewed and tested there,
and arrives in the next release. When that release ships, your PR is closed with a
link to it — closed, not rejected. Your authorship is preserved via
`Co-authored-by`, and you are credited in the release notes.

So: **a closed PR here usually means "shipped"**, and the release it shipped in
will be linked in the closing comment.

---

## Reporting a bug

Open an [issue](https://github.com/tarkh/w/issues). What actually helps:

- The `IMAGE_VERSION` and `W_BUILD_DATE` lines from `/etc/os-release`
- `w-sync status` — which channel and ref the machine is on
- The relevant log. W logs its own work to `/var/log/w/`;
  `sudo /var/lib/w/src/scripts/collect-logs.sh` assembles a full diagnostic bundle
  if you want to attach one. **Read it before
  attaching** — it is a system diagnostic and may contain hostnames, usernames,
  network names or paths you would rather not publish.
- Hardware, when the bug looks hardware-shaped (GPU, laptop model, display setup)

For anything security-sensitive, do not open an issue — see
[SECURITY.md](SECURITY.md).

---

## Sending a patch

1. Fork, branch, and make your change against `main`.
2. **Run the checks.** `scripts/check.sh` is the project's static gate — shell and
   Python linting, permission and manifest invariants, delivery routing, config
   layering, i18n, QML linting, and unit tests. It takes seconds and it must be
   green:

   ```sh
   ./scripts/check.sh              # everything
   ./scripts/check.sh --bash       # one suite
   ```

   Missing linters skip their suite with a warning rather than failing, so a
   partial toolchain still gets you most of the way.

3. If your change touches anything user-visible, say how you tested it on a real
   machine or VM. `vm/` holds the project's own harness: `vm/start.sh` runs a dev
   VM, `vm/e2e.sh` does an unattended install end to end.
4. Open the PR. Explain what breaks without the change — that is more useful than
   describing the diff.

### What the code should look like

Match what is already there. Concretely:

- **Shell** is bash with `set -euo pipefail`, shellcheck-clean. Python is
  ruff-clean. Both are enforced by `check.sh`.
- **Comments explain why, not what.** The existing code is heavy on rationale —
  which trap was hit, which alternative was rejected and for what reason. That is
  deliberate; keep it up. A comment restating the line below it is noise.
- **Respect the ownership boundary.** Files W manages are overwritten on every
  update; files the user owns are seeded once and never touched again. Which is
  which is declared in the module manifests under
  `rootfs/usr/share/w/update/*.manifest`, and `check.sh` enforces it. If you add a
  shipped file, add its manifest row in the same change.
- **New module, new routing.** `rootfs/usr/share/w/update/sync-map` decides which
  `apply.sh` module runs when a given path changes. The `routing` suite fails if a
  shipped file has nowhere to go.
- **Keep the diff to the task.** Drive-by reformatting of untouched code makes
  review harder and will usually be asked out.

### Things worth asking about first

Open an issue before starting if your change adds a dependency, a new top-level
directory, a new `w-*` tool, or alters the installer's step flow. These are
architectural and cheaper to discuss than to redo.

---

## License

By contributing you agree that your work is licensed under
**GPL-3.0-or-later**, the licence of this project, and that artwork you contribute
is licensed **CC BY-SA 4.0** — the split is described in
[COPYING.assets](COPYING.assets). There is no CLA and no copyright assignment; you
keep your copyright.
