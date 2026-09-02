# check/manifests.sh — ownership manifests vs the trees they describe.
#
# /usr/share/w/update/<module>.manifest is the single source of truth for
# deploy (seed-if-absent), w-reset and future drift detection — a path that
# drifts from rootfs/skel silently breaks all three consumers at once.
# Format (v2): <path>\t<class>, class ∈ user|managed|override|user-conf. Class
# is ownership semantics only; the source location follows the path SHAPE:
# home-relative → rootfs/etc/skel/, absolute → rootfs/. Trailing "/" marks a
# whole managed directory. user/managed sources must exist in the repo;
# override is admin-state that may be seeded at runtime only (e.g.
# /etc/w/update.conf is deliberately NOT in rootfs — apply_rootfs would
# clobber the edge channel), so its existence is not required. user-conf is a
# wconf user-layer file (~/.config/w/<subsys>.conf) written on demand by
# `wconf_set ... user` — it has no vendor default and thus no repo source
# either, and it must be home-relative (it is restored by deleting it).
# Pack manifests (scripts/packs/*/manifest) resolve against the bundle tree —
# separate semantics, to be covered when packs Ф4 lands.

chk_manifests() {
  local rc=0 m p cls src line n
  declare -A SEEN=()
  for m in rootfs/usr/share/w/update/*.manifest; do
    n=0
    while IFS= read -r line; do
      n=$((n + 1))
      [[ -z "$line" || "$line" == \#* ]] && continue
      p="${line%%$'\t'*}"; cls="${line#*$'\t'}"
      if [[ "$p" == "$line" || "$cls" == *$'\t'* || -z "$p" || -z "$cls" ]]; then
        echo "  ${m##*/}:$n: malformed (need <path>\\t<class>): $line"; rc=1; continue
      fi
      case "$cls" in
        user|managed)
          if [[ "$p" == /* ]]; then src="rootfs$p"; else src="rootfs/etc/skel/$p"; fi
          [[ -e "$src" ]] || { echo "  ${m##*/}:$n: source missing ($src): $p"; rc=1; } ;;
        override) ;;
        user-conf)
          [[ "$p" == /* ]] && { echo "  ${m##*/}:$n: class 'user-conf' must be home-relative: $p"; rc=1; } ;;
        *) echo "  ${m##*/}:$n: unknown class '$cls': $p"; rc=1; continue ;;
      esac
      if [[ -n "${SEEN[$p]:-}" ]]; then
        echo "  ${m##*/}:$n: path also owned by ${SEEN[$p]}: $p"; rc=1
      fi
      SEEN[$p]="${m##*/}"
    done < "$m"
  done

  # Reverse direction. /etc/w is W's admin-state namespace, and apply_rootfs spares
  # exactly what a manifest declares `override` — anything else shipped there is
  # overwritten on every update. That is how the machine mode, the active theme and
  # the NTP selection silently reverted in the field, and three separate configs sat
  # undeclared for months. So: a file under rootfs/etc/w must carry a row (override
  # for admin-state, managed for vendor data) or not be shipped at all.
  local f
  for f in rootfs/etc/w/*; do
    [[ -e "$f" || -L "$f" ]] || continue
    [[ -d "$f" && ! -L "$f" ]] && continue     # directories are declared with a trailing '/'
    p="/etc/w/${f##*/}"
    [[ -n "${SEEN[$p]:-}" ]] && continue
    echo "  $p: shipped in rootfs but declared by no manifest — apply_rootfs would clobber it"
    rc=1
  done

  # ── W-Pack bundle manifests ────────────────────────────────────────────────
  # Same TSV, different roots: a bundle keeps its pristine copies inside its own
  # tree (config/skel/<home-rel>, config/root<abs>), which is what makes it
  # self-contained. These are no longer only a deploy input — `w-reset <bundle>`
  # restores from them too, so a typo here breaks recovery as well as install.
  local bdir bname bm nbundles=0
  for bdir in scripts/packs/*/; do
    [[ -f "$bdir/meta.conf" ]] || continue
    bname="$(basename "$bdir")"
    nbundles=$((nbundles + 1))

    # A bundle sharing a module's name would make `w-reset <name>` ambiguous —
    # it resolves modules first, so the bundle would become unreachable.
    if [[ -f "rootfs/usr/share/w/update/$bname.manifest" ]]; then
      echo "  packs/$bname: bundle name collides with the module manifest of the same name"
      echo "    (w-reset resolves modules first, so this bundle could never be reset)"
      rc=1
    fi

    bm="$bdir/manifest"
    [[ -f "$bm" ]] || continue
    n=0
    while IFS= read -r line; do
      n=$((n + 1))
      [[ -z "$line" || "$line" == \#* ]] && continue
      p="${line%%$'\t'*}"; cls="${line#*$'\t'}"
      if [[ "$p" == "$line" || "$cls" == *$'\t'* || -z "$p" || -z "$cls" ]]; then
        echo "  packs/$bname/manifest:$n: malformed (need <path>\\t<class>): $line"; rc=1; continue
      fi
      case "$cls" in
        user|managed)
          if [[ "$p" == /* ]]; then src="$bdir/config/root$p"; else src="$bdir/config/skel/$p"; fi
          [[ -e "${src%/}" ]] || { echo "  packs/$bname/manifest:$n: source missing ($src): $p"; rc=1; } ;;
        override)
          # /etc/w admin-state is a base-system concept; w-reset skips it for a
          # bundle, so declaring it here means the row does nothing at all.
          echo "  packs/$bname/manifest:$n: class 'override' is not a bundle concept: $p"; rc=1 ;;
        *) echo "  packs/$bname/manifest:$n: unknown class '$cls': $p"; rc=1 ;;
      esac
    done < "$bm"
  done

  echo "  manifests: $(ls rootfs/usr/share/w/update/*.manifest | wc -l | tr -d ' ') files, ${#SEEN[@]} owned paths; $nbundles bundle(s)"
  return $rc
}
