# w-sbat-lib.sh — Limine as a second stage shim accepts (shared, sourced).
#
# shim refuses a second stage without a .sbat section (EFI_SECURITY_VIOLATION), and
# upstream Limine does not carry one. One recipe, two callers:
#   • /usr/lib/w/w-secureboot-stage — the installed machine's grubx64.efi (shim mode);
#   • scripts/iso-secureboot.sh     — the install medium's grubx64.efi, sourced from
#     the source checkout (rootfs/usr/lib/w), where /usr/lib/w does not exist.
# The config hash and any signature are the caller's: both come after this step.

# w_sbat_build <limine.efi> <out.efi> <limine version>
# SBAT: the mandatory header line, upstream Limine's component, and W's own vendor
# line (a W-specific revocation is possible without touching upstream's generation).
# The new section goes right after the image (SizeOfImage), page-aligned, so it
# overlaps nothing Limine maps. Always from the pristine package binary:
# limine-entry-tool restores its own copy from a backup before each enroll, so a
# section added to that one would not survive the next limine-update anyway.
w_sbat_build() {
  local src="$1" out="$2" ver="${3:-unknown}" end csv
  end="$(objdump -p "$src" | awk '/^SizeOfImage/{print $2}')"
  [[ -n "$end" ]] || { echo "w_sbat_build: cannot read SizeOfImage of $src" >&2; return 1; }
  csv="$out.sbat.csv"
  cat > "$csv" <<EOF
sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
limine,1,Limine,limine,$ver,https://codeberg.org/Limine/Limine
limine.w,1,W Linux,limine,$ver,https://github.com/tarkh/w
EOF
  objcopy --set-section-alignment .sbat=4096 --add-section .sbat="$csv" \
    --set-section-flags .sbat=contents,alloc,load,readonly,data \
    --adjust-section-vma ".sbat+0x$end" "$src" "$out" || { rm -f "$csv"; return 1; }
  rm -f "$csv"
}
