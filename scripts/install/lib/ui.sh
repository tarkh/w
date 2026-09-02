# ui.sh — terminal output, ASCII logo, dialog wrappers

# ── ANSI colors (for non-dialog output) ──────────────────────────────────────
C_MAGENTA='\033[1;35m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;37m'
C_RESET='\033[0m'

DIALOG_BACKTITLE="W Linux Installer"
DIALOG_COMMON=(--backtitle "$DIALOG_BACKTITLE" --colors --no-cancel)

# Apply our theme
DIALOGRC="$(dirname "${BASH_SOURCE[0]}")/../dialogrc"
export DIALOGRC

# ── Logo ─────────────────────────────────────────────────────────────────────
ui_logo() {
  clear
  echo -e "${C_MAGENTA}"
  echo '  ██╗    ██╗'
  echo '  ██║    ██║'
  echo '  ██║ █╗ ██║'
  echo '  ╚███╔███╔╝'
  echo '   ╚══╝╚══╝'
  echo -e "${C_WHITE}  W Linux Installer${C_GRAY}  —  Arch-based${C_RESET}"
  echo ''
}

# ── Dialog wrappers ───────────────────────────────────────────────────────────

# ui_msg <title> <text>
ui_msg() {
  dialog "${DIALOG_COMMON[@]}" --title " $1 " --msgbox "\n$2\n" 12 60
}

# ui_yesno <title> <text> → returns 0 (Yes) or 1 (No)
ui_yesno() {
  dialog "${DIALOG_COMMON[@]}" --title " $1 " --yesno "\n$2\n" 10 60
}

# ui_input <title> <text> <default> → prints value to stdout via $UI_RESULT
ui_input() {
  UI_RESULT=$(dialog "${DIALOG_COMMON[@]}" --title " $1 " \
    --inputbox "\n$2" 10 60 "$3" 3>&1 1>&2 2>&3) || true
}

# ui_password <title> <text> → $UI_RESULT (confirmed, loops until match)
ui_password() {
  local title="$1" text="$2" p1 p2
  while true; do
    p1=$(dialog "${DIALOG_COMMON[@]}" --title " $title " \
      --insecure --passwordbox "\n$text" 10 60 3>&1 1>&2 2>&3) || true
    p2=$(dialog "${DIALOG_COMMON[@]}" --title " $title " \
      --insecure --passwordbox "\nConfirm password:" 10 60 3>&1 1>&2 2>&3) || true
    if [[ "$p1" == "$p2" && -n "$p1" ]]; then
      UI_RESULT="$p1"
      return 0
    fi
    dialog "${DIALOG_COMMON[@]}" --title " Error " \
      --msgbox "\nPasswords do not match or are empty. Try again." 8 50
  done
}

# ui_menu <title> <text> <item1> <desc1> ... → $UI_RESULT
ui_menu() {
  local title="$1" text="$2"; shift 2
  UI_RESULT=$(dialog "${DIALOG_COMMON[@]}" --title " $title " \
    --menu "\n$text" 20 70 10 "$@" 3>&1 1>&2 2>&3) || true
}

# ui_info <text>  (no button, temporary status message)
# dialog draws its SCREEN to stdout (the result goes to stderr). During the work
# phase stdout is redirected to the log, so send the screen to the saved terminal
# fd ($W_TTY, a dup of the real terminal). $W_TTY defaults to 1 before the work phase.
ui_info() {
  dialog "${DIALOG_COMMON[@]}" --title " $(t installing) " \
    --infobox "\n  $1\n" 6 60 1>&"${W_TTY:-1}"
}

# ui_prgbox <title> <command>  (scrolling output while command runs)
ui_prgbox() {
  dialog "${DIALOG_COMMON[@]}" --title " $1 " \
    --prgbox "$2" 30 80
}
