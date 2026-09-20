# modules/homesubvol.sh — per-account state outside @home snapshots.
#
# apply.sh context: runs on the live system as root; post-boot only.
#
# Data-driven: /usr/share/w/defaults/home-subvols lists the home-relative paths
# (one per line, `#` comments) and this module carves each one as a nested btrfs
# subvolume for every human account. It knows nothing about the tools that own
# those paths — adding one is a registry line (plus, where the tool must be told
# where to write, a /etc/profile.d/w-<tool>.sh env drop-in), never code here.
# Mechanism and constraints: w_home_subvol in lib/deploy.sh.

mod_homesubvol() {
  local registry="$SRC/rootfs/usr/share/w/defaults/home-subvols"
  [[ -f "$registry" ]] || { echo "  WARN: $registry missing, skipping."; return 0; }
  local -a paths=() wusers=(); local entry wuser home_dir rel
  mapfile -t paths < <(w_home_subvols_read "$registry")
  mapfile -t wusers < <(w_home_users)
  ((${#wusers[@]})) || { echo "  WARN: no W user account found (uid 1000-65533), skipping home subvolumes."; return 0; }
  for entry in "${wusers[@]}"; do
    wuser="${entry%%$'\t'*}"; home_dir="${entry#*$'\t'}"
    info "Carving snapshot-excluded subvolumes for $wuser..."
    for rel in "${paths[@]}"; do
      install -d -o "$wuser" -g "$wuser" "$(dirname "$home_dir/$rel")"
      w_home_subvol "$home_dir/$rel" "$wuser"
    done
  done
}
