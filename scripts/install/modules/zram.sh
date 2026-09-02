# modules/zram.sh — zram-generator swap config

mod_zram() {
  ui_info "Configuring zram swap..."
  mkdir -p "$MNT/etc/systemd"
  cat > "$MNT/etc/systemd/zram-generator.conf" <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
EOF
}
