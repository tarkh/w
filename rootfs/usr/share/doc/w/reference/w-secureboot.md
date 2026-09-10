---
title: w-secureboot
section: reference
order: 0
summary: Set up and manage Secure Boot (sbctl keys + Limine hash).
---

`w-secureboot` — Set up and manage Secure Boot (sbctl keys + Limine hash).

## Usage

```
Usage: w-secureboot <command>

Info: Set up and manage Secure Boot (sbctl keys + Limine hash).

Commands:
  status [--porcelain]   Show sbctl setup-mode/enroll state and signed files
  enable                 Turn Secure Boot on: enroll keys + sign Limine. Two-phase — the
                          first call enrolls and asks for a reboot; run it again after
                          rebooting to re-seal the TPM2 disk auto-unlock (PCR7 only
                          updates on that reboot, not live)
  disable                Turn Secure Boot off: drop TPM2 disk unlock + reset keys (back to Setup Mode)
  setup                  One-time enable: create+enroll keys (Setup Mode) + sign Limine + enroll hash
  sign                   Re-sign all sbctl-tracked binaries (after a Limine update)
  reenroll               Re-enroll the Limine config hash (after limine.conf changed)
  help                   Show this help

Exit codes:
  0 Success   1 Runtime error   2 Usage error

Examples:
  sudo w-secureboot enable
  w-secureboot status --porcelain
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-secureboot help`.
