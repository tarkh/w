# system.sh — locale, timezone, hostname, users

sys_timezone() {
  ui_info "Setting timezone: $CONF_TZ"
  chroot_run ln -sf "/usr/share/zoneinfo/$CONF_TZ" /etc/localtime
  chroot_run hwclock --systohc
}

sys_locale() {
  ui_info "Configuring locale..."
  # Generate the chosen locale plus en_US.UTF-8 as an always-present fallback.
  local loc="${CONF_LOCALE:-en_US.UTF-8}"
  {
    echo "en_US.UTF-8 UTF-8"
    [[ "$loc" != "en_US.UTF-8" ]] && echo "$loc UTF-8"
  } > "$MNT/etc/locale.gen"
  chroot_run locale-gen
  echo "LANG=$loc" > "$MNT/etc/locale.conf"
  # Console keymap chosen in the wizard — also the layout used to type the LUKS
  # passphrase at every boot. Writing it here (before mod_plymouth's mkinitcpio -P)
  # both configures the target and silences sd-vconsole's missing-file warning.
  echo "KEYMAP=${CONF_KEYMAP:-us}" > "$MNT/etc/vconsole.conf"
}

# Option sources + validator for the keymap/locale wizard steps. Descriptions are
# single tokens (the menu splits items on whitespace).
km_list() {
  echo "us English-US uk English-UK de German fr French es Spanish it Italian" \
       "ru Russian ua Ukrainian pl Polish cz Czech sv-latin1 Swedish fi Finnish" \
       "no Norwegian dk Danish br-abnt2 Portuguese-BR pt-latin1 Portuguese" \
       "tr Turkish gr Greek hu Hungarian nl Dutch"
}
locale_list() {
  echo "en_US.UTF-8 English-US en_GB.UTF-8 English-UK ru_RU.UTF-8 Russian" \
       "de_DE.UTF-8 German fr_FR.UTF-8 French es_ES.UTF-8 Spanish it_IT.UTF-8 Italian" \
       "pt_BR.UTF-8 Portuguese-BR pl_PL.UTF-8 Polish uk_UA.UTF-8 Ukrainian" \
       "cs_CZ.UTF-8 Czech tr_TR.UTF-8 Turkish nl_NL.UTF-8 Dutch sv_SE.UTF-8 Swedish" \
       "ja_JP.UTF-8 Japanese zh_CN.UTF-8 Chinese"
}
# Doubles as the live apply: loadkeys both validates the code and remaps the
# console so the passphrase steps that follow use the chosen layout.
v_keymap() { loadkeys "$1" &>/dev/null; }

# Option source for the timezone wizard step: one "Zone<TAB>±HH:MM" line per
# zone (tab-separated, like the checklist format — zone names have no spaces
# but this keeps it consistent and future-proof). Same offset computation as
# `list_zones()` in rootfs/usr/bin/w-time (~350 `date` forks, one-shot).
tz_zone_list() {
  local z off
  timedatectl list-timezones | while read -r z; do
    off="$(TZ="$z" date +%z)"
    off="${off:0:3}:${off:3:2}"
    printf '%s\t%s\n' "$z" "$off"
  done
}

sys_hostname() {
  ui_info "Setting hostname: $CONF_HOSTNAME"
  echo "$CONF_HOSTNAME" > "$MNT/etc/hostname"
}

sys_hosts() {
  cat > "$MNT/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${CONF_HOSTNAME}.localdomain  ${CONF_HOSTNAME}
EOF
}

sys_root_password() {
  ui_info "Setting root password..."
  { set +x; } 2>/dev/null   # keep password out of the trace log
  chroot_sh "echo 'root:${CONF_ROOT_PASS}' | chpasswd"
  [[ -n "${W_TRACE_FD:-}" ]] && set -x || true
}

sys_create_user() {
  ui_info "Creating user: $CONF_USER"
  chroot_run useradd -m -G wheel -s /bin/bash "$CONF_USER"
  { set +x; } 2>/dev/null   # keep password out of the trace log
  chroot_sh "echo '${CONF_USER}:${CONF_USER_PASS}' | chpasswd"
  [[ -n "${W_TRACE_FD:-}" ]] && set -x || true
  # Allow wheel group to use sudo
  echo "%wheel ALL=(ALL:ALL) ALL" > "$MNT/etc/sudoers.d/wheel"
}

# Headless access for unattended installs (fleet/E2E): a preset may carry
# ssh_authorized_key=<pubkey line> (see tui.sh PRESET_EXTRA_VARS) — install it
# for root on the target. sshd is already enabled by mod_network, and its stock
# PermitRootLogin=prohibit-password admits exactly this key and nothing else.
# No-op without the key (interactive installs never set it).
sys_ssh_key() {
  [[ -n "${ssh_authorized_key:-}" ]] || return 0
  ui_info "Installing SSH authorized key for root..."
  install -dm700 "$MNT/root/.ssh"
  printf '%s\n' "$ssh_authorized_key" > "$MNT/root/.ssh/authorized_keys"
  chmod 600 "$MNT/root/.ssh/authorized_keys"
}

# Persistent journald — without /var/log/journal the journal is volatile and
# everything before the first reboot is lost. Create the dir + drop-in so the
# very first boot already records persistently (Storage=auto → persistent).
sys_journal() {
  ui_info "Enabling persistent journal..."
  mkdir -p "$MNT/var/log/journal"
  local drop="$SRC/rootfs/etc/systemd/journald.conf.d/00-persistent.conf"
  [[ -f "$drop" ]] && install -Dm644 "$drop" \
    "$MNT/etc/systemd/journald.conf.d/00-persistent.conf"
}
