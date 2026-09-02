# style.sh — deploy W Linux theme collection and the theming utilities
# apply.sh context: runs on live system as root. Post-boot only (needs imagemagick
# from --packages, and the subsystem themes already deployed by their modules).

mod_style() {
  info "Installing theming dependencies..."
  # w-style regenerates GRUB/Plymouth assets (imagemagick) and the GRUB font PF2
  # (grub-mkfont, from grub); w-theme crossfade (grim). Fonts are a theme axis now,
  # so the font families must be installed for `w-style apply all` to render them.
  # Icon stack: the active icon theme is the REAL theme Papirus-Dark (NOT a meta-theme
  # — Qt's icon loader rejects inheritance-only meta-themes and falls back to breeze).
  # Papirus-Dark natively inherits breeze-dark → hicolor, so genuine gaps fill from
  # breeze-dark (matching monochrome). breeze-icons is therefore load-bearing, so we
  # depend on it explicitly. Folders are retinted to W_ICON_FOLDER. adwaita-icon-theme
  # is a hard gtk3/gtk4 dependency (always present); not needed for our chain but harmless.
  # matugen extracts the source palette for `w-theme new` (Material HCT, official
  # repo, a single Rust binary with no runtime deps beyond glibc). The mapping
  # from its output to a W theme is ours — /usr/lib/w/w-theme/palette.py.
  w_pac -S --needed --noconfirm imagemagick grim inter-font ttf-jetbrains-mono-nerd \
    papirus-icon-theme breeze-icons matugen

  info "Deploying themes and theming utilities..."
  mkdir -p /etc/w/themes
  # Themes carry their own optional motion.conf / font.conf; the default theme `w`
  # holds the baselines that omitting themes inherit (resolved by w-style). No
  # separate global motion/font source — they live in themes/w/, deployed here.
  rsync -a --chown=root:root "$SRC/rootfs/etc/w/themes/" /etc/w/themes/
  # System-fallback pointer: create only if missing (don't clobber a sudo choice)
  [[ -e /etc/w/active-theme ]] || ln -sfn themes/w /etc/w/active-theme
  install -Dm755 "$SRC/rootfs/usr/bin/w-style" /usr/bin/w-style
  install -Dm755 "$SRC/rootfs/usr/bin/w-theme" /usr/bin/w-theme
  install -Dm755 "$SRC/rootfs/usr/bin/w-appearance" /usr/bin/w-appearance

  # w-style is a thin orchestrator over a shared SDK (lib/core.sh) + per-axis
  # modules (modules/<band>-<name>/). Ship the whole library tree; w-style
  # discovers whatever modules are present, so app-specific modules deployed by
  # their own apply.sh module (mod_ghostty, mod_files, …) drop in independently.
  mkdir -p /usr/lib/w/w-style
  rsync -a --chown=root:root "$SRC/rootfs/usr/lib/w/w-style/" /usr/lib/w/w-style/

  # w-theme's authoring half (ImageMagick pipeline + palette engine). Kept beside
  # the CLI rather than inside it so the colour work stays testable on its own.
  mkdir -p /usr/lib/w/w-theme
  rsync -a --chown=root:root "$SRC/rootfs/usr/lib/w/w-theme/" /usr/lib/w/w-theme/

  # Colors, motion, appearance, fonts (system fontconfig + GRUB PF2 + skel user
  # channels) AND Qt (brand QPalette → qt5ct/qt6ct configs) all
  # render here from the active theme. The qt5ct/qt6ct packages come from the
  # official repo via --packages (before this); apply qt only writes config, so it
  # renders fine even if a backend isn't present yet.
  info "Applying theme to all subsystems..."
  w-style apply all
}
