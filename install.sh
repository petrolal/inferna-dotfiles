#!/usr/bin/env bash
# Install Inferna dotfiles (pure GNOME on NixOS)
# Anything replaced is copied to ~/.config/inferna-dotfiles-backup/<time>-<id>/ first.
#
#   ./install.sh          install, asking once before changing anything
#   ./install.sh --yes    install without asking
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="$HOME/.config"

if [[ -n "${XDG_CONFIG_HOME:-}" && "$(realpath -m "$XDG_CONFIG_HOME")" != "$(realpath -m "$config")" ]]; then
  echo "XDG_CONFIG_HOME is set to $XDG_CONFIG_HOME. These dots only support ~/.config." >&2
  exit 1
fi

if [[ "${1:-}" != "--yes" ]]; then
  cat <<EOF
This will symlink the GNOME dotfiles into your home folder:
  - fastfetch dashboard & branding -> ~/.config/fastfetch/

Any obsolete symlinks left over from previous Hyprland/core installs in
~/.local/bin and ~/.local/share will be cleaned up.
Anything replaced is backed up to ~/.config/inferna-dotfiles-backup/.
EOF
  read -r -p "Continue? [y/N] " answer || answer=""
  [[ "$answer" == [yY]* ]] || { echo "Nothing changed."; exit 0; }
fi

mkdir -p "$config/inferna-dotfiles-backup"
backup="$(mktemp -d "$config/inferna-dotfiles-backup/$(date +%Y%m%d-%H%M%S)-XXXX")"

save() {
  local dest="$1" rel="${1#"$HOME"/}"
  [[ -e "$dest" && ! -e "$backup/$rel" ]] || return 0
  mkdir -p "$backup/$(dirname "$rel")"
  cp -a "$dest" "$backup/$rel"
}

place() {
  local src="$1" dest="$2"
  save "$dest"
  rm -rf -- "$dest"
  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
}

echo "Cleaning obsolete symlinks from ~/.local/..."
for obsolete in \
  "$HOME/.local/bin/hypr-all-full-width" \
  "$HOME/.local/bin/hypr-smart-focus" \
  "$HOME/.local/bin/denon-agent-usage-update" \
  "$HOME/.local/bin/denon-wifi-other" \
  "$HOME/.local/share/denon-agent-usage" \
  "$HOME/.local/share/inferna-glass" \
  "$HOME/.local/share/inferna-recess" \
  "$HOME/.local/share/omarchy-glass" \
  "$HOME/.local/share/omarchy-recess" \
  "$HOME/.local/share/touchpad-control"; do
  [[ -L "$obsolete" ]] && rm -f -- "$obsolete"
done

# Remove symlinks in ~/.local/bin that previously pointed into this repo's old core/bin
if [[ -d "$HOME/.local/bin" ]]; then
  for link in "$HOME/.local/bin"/inferna*; do
    [[ -L "$link" ]] || continue
    target=$(readlink "$link" 2>/dev/null || true)
    if [[ ! -e "$link" || "$target" == "$here/core/"* ]]; then
      rm -f -- "$link"
    fi
  done
fi

echo "Installing fastfetch dashboard..."
place "$here/fastfetch/config.jsonc" "$config/fastfetch/config.jsonc"
place "$here/fastfetch/dashboard.py" "$config/fastfetch/dashboard.py"
place "$here/branding/about.txt" "$config/fastfetch/about.txt"

cat <<EOF

Done. Backups of anything replaced are in:
  $backup
EOF
