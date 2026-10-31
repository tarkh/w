#!/usr/bin/env python3
"""pe-authenticode.py — authenticode SHA-256 of PE images, one hex digest per line.

The hash MokManager's "Enroll hash from disk" records and shim compares a second
stage against (MokList). Per the PE/COFF spec: headers without CheckSum and the
Security directory entry, sections in PointerToRawData order, then whatever trails
the last section up to the certificate table. Used by scripts/iso-secureboot.sh
(the published hash of the install medium's grubx64.efi) and vm/e2e.sh --iso-sb.
pe-dumpinfo prints such hashes too, but unlabelled among others — not a contract.
"""
import hashlib
import sys

import pefile


def authenticode(path):
    data = open(path, "rb").read()
    pe = pefile.PE(data=data, fast_load=True)
    opt = pe.OPTIONAL_HEADER
    cs = opt.get_file_offset() + 64  # CheckSum: same offset in PE32 and PE32+
    sec = opt.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_SECURITY"]]
    so = sec.get_file_offset()
    h = hashlib.sha256()
    h.update(data[:cs])
    h.update(data[cs + 4:so])
    h.update(data[so + 8:opt.SizeOfHeaders])
    end = opt.SizeOfHeaders
    for s in sorted(pe.sections, key=lambda s: s.PointerToRawData):
        if s.SizeOfRawData:
            h.update(data[s.PointerToRawData:s.PointerToRawData + s.SizeOfRawData])
            end = max(end, s.PointerToRawData + s.SizeOfRawData)
    # The certificate table's VirtualAddress is a file offset; nothing after it counts.
    tail = sec.VirtualAddress if sec.Size else len(data)
    if tail > end:
        h.update(data[end:tail])
    return h.hexdigest()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: pe-authenticode.py FILE...")
    for f in sys.argv[1:]:
        print(authenticode(f))
