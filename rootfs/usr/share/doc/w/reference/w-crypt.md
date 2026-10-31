---
title: w-crypt
section: reference
order: 0
summary: Manage disk-encryption factors — TPM2 auto-unlock and recovery keys.
---

`w-crypt` — Manage disk-encryption factors — TPM2 auto-unlock and recovery keys.

## Usage

```
Usage: w-crypt <command>

Info: Manage disk-encryption factors — TPM2 auto-unlock and recovery keys.

Commands:
  status [--porcelain]
                 Show LUKS device, key slots and enrolled tokens (TPM2/recovery);
                  --porcelain: one TSV row luks/tpm_device/tpm2/pcrs/recovery/reseal
  enroll-tpm [--pin] [--no-secureboot]
                 Enroll TPM2 auto-unlock (PCRs: ${W_CRYPT_TPM2_PCRS}), replacing an existing
                  one; asks for the passphrase once. --pin also asks for a PIN at
                  every boot. Refused while Secure Boot is off: without it the TPM
                  releases the key to any boot medium (--no-secureboot overrides)
  reenroll-tpm   Re-seal TPM2 to the current boot state (after firmware/Secure Boot change)
  recovery-add [--replace]
                 Generate and print a one-time recovery key (store it offline);
                  --replace removes the previous recovery key
  wipe-tpm       Remove the TPM2 token (revert to passphrase-only unlock)
  help           Show this help

Exit codes:
  0 Success   1 Runtime error   2 Usage error

Examples:
  sudo w-crypt status
  sudo w-crypt enroll-tpm --pin
  sudo w-crypt recovery-add --replace
```

This page is generated from the command's own help text (w-docs-refgen). The
live version of the same text on a W machine: `w-crypt help`.
