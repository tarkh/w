---
title: w-secureboot
section: reference
order: 0
summary: Set up and manage Secure Boot (sbctl keys or shim + MOK, Limine hash).
---

`w-secureboot` — Set up and manage Secure Boot (sbctl keys or shim + MOK, Limine hash).

## Usage

```
Usage: w-secureboot <command>

Info: Set up and manage Secure Boot (sbctl keys or shim + MOK, Limine hash).

Commands:
  status [--porcelain]   Show the Secure Boot mode, firmware state and signed files
  enable [--mode own|shim]
                         Turn Secure Boot on. The mode follows the firmware: Setup Mode
                          → own keys; factory keys → Microsoft-signed shim + this
                          machine's key in MokList (BitLocker-safe). Two-phase — the
                          first call changes the keys or queues the MokManager step and
                          asks for a reboot; run it again after rebooting to finish and
                          re-seal an existing TPM2 disk auto-unlock (PCR7 only updates
                          on that reboot; 'w-crypt enroll-tpm' adds one)
  disable                Turn Secure Boot off: drop TPM2 disk unlock + reset keys (own)
                          or the shim chain (shim, after Secure Boot is off in firmware)
  setup                  One-time own-keys enable: create+enroll keys (Setup Mode) + sign
  sign                   Re-sign all sbctl-tracked binaries (after a Limine update)
  reenroll [--if-stale]  Re-enroll the Limine config hash (after limine.conf changed);
                          --if-stale: only when the boot loaders no longer match it
                          (run automatically before shutdown and hibernation)
  help                   Show this help

Exit codes:
  0 Success   1 Runtime error   2 Usage error

Examples:
  sudo w-secureboot enable
  w-secureboot status --porcelain
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-secureboot help`.
