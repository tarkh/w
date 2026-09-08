---
title: w-crypt
section: reference
order: 0
summary: Manage disk-encryption factors — TPM2 auto-unlock and recovery keys.
---

`w-crypt` — Manage disk-encryption factors — TPM2 auto-unlock and recovery keys..

## Usage

```
Usage: w-crypt <command>

Info: Manage disk-encryption factors — TPM2 auto-unlock and recovery keys.

Commands:
  status         Show LUKS device, key slots and enrolled tokens (TPM2/recovery)
  enroll-tpm     Enroll TPM2 auto-unlock (PCRs: ${W_CRYPT_TPM2_PCRS}); asks for the passphrase once
  reenroll-tpm   Re-seal TPM2 to the current boot state (after firmware/Secure Boot change)
  recovery-add   Generate and print a one-time recovery key (store it offline)
  wipe-tpm       Remove the TPM2 token (revert to passphrase-only unlock)
  help           Show this help

Exit codes:
  0 Success   1 Runtime error   2 Usage error

Examples:
  w-crypt status
  sudo w-crypt enroll-tpm
  sudo w-crypt recovery-add
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-crypt help`.
