#!/usr/bin/env bash
# Save or restore GNOME Shell extension settings (dconf) in gnome/extensions.dconf.
#
# Usage:
#   inferna-extensions save   Dump /org/gnome/shell/extensions/ into gnome/extensions.dconf
#   inferna-extensions load   Restore gnome/extensions.dconf into dconf
set -euo pipefail

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
repo_root="$(cd "$(dirname "$script_path")/.." && pwd)"
dconf_file="$repo_root/gnome/extensions.dconf"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") save   Snapshot GNOME extension settings to $dconf_file
  $(basename "$0") load   Restore GNOME extension settings from $dconf_file
EOF
}

require_dconf() {
  if ! command -v dconf >/dev/null 2>&1; then
    echo "dconf command not found." >&2
    exit 1
  fi
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    echo "No active GNOME D-Bus session detected." >&2
    exit 1
  fi
}

save_extensions() {
  require_dconf
  # Exclude [user-theme] since inferna-theme manages the active Shell theme.
  dconf dump /org/gnome/shell/extensions/ | awk '
    /^\[user-theme\]$/ { skip = 1; next }
    /^\[/              { skip = 0 }
    !skip              { print }
  ' > "$dconf_file"
  echo "Saved GNOME extension settings to $dconf_file"
}

load_extensions() {
  require_dconf
  if [[ ! -f "$dconf_file" ]]; then
    echo "No extension preset file found at $dconf_file (run '$(basename "$0") save' first)." >&2
    exit 1
  fi
  dconf load /org/gnome/shell/extensions/ < "$dconf_file"
  echo "Restored GNOME extension settings from $dconf_file"
}

case "${1:-}" in
  save) save_extensions ;;
  load) load_extensions ;;
  ""|-h|--help) usage ;;
  *) usage >&2; exit 1 ;;
esac
