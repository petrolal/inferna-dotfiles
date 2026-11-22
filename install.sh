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
  - Fish base config               -> ~/.config/fish/config.fish
  - Fish dynamic rice paths        -> ~/.config/fish/conf.d/inferna-paths.fish
  - Fish user config (if missing)  -> ~/.config/fish/user-fish.fish
  - Starship prompt config         -> ~/.config/starship.toml
  - Ptyxis Inferna palette         -> ~/.local/share/org.gnome.Ptyxis/palettes/Inferna.palette
  - GNOME themes (Inferna, etc.)   -> ~/.themes/
  - GTK4 / GTK3 CSS overrides      -> ~/.config/gtk-{4,3}.0/gtk.css
  - Default wallpapers             -> ~/.local/share/backgrounds/inferna/
  - Theme & extension helpers      -> ~/.local/bin/inferna-{theme,extensions}

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

echo "Installing GNOME themes, wallpapers, and inferna helpers..."
chmod +x "$here/gnome/apply-theme.sh" "$here/gnome/extensions-dconf.sh"
place "$here/gnome/apply-theme.sh" "$HOME/.local/bin/inferna-theme"
place "$here/gnome/extensions-dconf.sh" "$HOME/.local/bin/inferna-extensions"

if [[ -f "$here/gnome/extensions.dconf" && -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  "$here/gnome/extensions-dconf.sh" load || true
fi

if [[ -d "$here/nixos/assets/wallpapers" ]]; then
  for wp in "$here/nixos/assets/wallpapers"/*; do
    [[ -f "$wp" ]] || continue
    place "$wp" "$HOME/.local/share/backgrounds/inferna/$(basename "$wp")"
  done
fi

if [[ -d "$here/gnome/themes" ]]; then
  for theme_dir in "$here/gnome/themes"/*/; do
    [[ -d "$theme_dir" ]] || continue
    theme_name="$(basename "$theme_dir")"
    place "${theme_dir%/}" "$HOME/.themes/$theme_name"
  done
fi

if [[ -d "$here/gnome/themes/Inferna" ]]; then
  save "$config/gtk-4.0/gtk.css"
  save "$config/gtk-3.0/gtk.css"
  "$here/gnome/apply-theme.sh" Inferna
fi

echo "Installing Fish config, Starship prompt, Ptyxis palette, and dynamic rice paths..."
place "$here/fish/config.fish" "$config/fish/config.fish"
place "$here/starship/starship.toml" "$config/starship.toml"
place "$here/ptyxis/Inferna.palette" "$HOME/.local/share/org.gnome.Ptyxis/palettes/Inferna.palette"

if command -v dconf >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  ptyxis_uuid="$(dconf read /org/gnome/Ptyxis/default-profile-uuid 2>/dev/null | tr -d "'" || true)"
  if [[ -z "$ptyxis_uuid" ]]; then
    ptyxis_uuid="10fe24a0000040008000000000000001"
    dconf write /org/gnome/Ptyxis/profile-uuids "['$ptyxis_uuid']" 2>/dev/null || true
    dconf write /org/gnome/Ptyxis/default-profile-uuid "'$ptyxis_uuid'" 2>/dev/null || true
  fi
  dconf write /org/gnome/Ptyxis/interface-style "'dark'" 2>/dev/null || true
  dconf write /org/gnome/Ptyxis/use-system-font "true" 2>/dev/null || true
  dconf write /org/gnome/Ptyxis/audible-bell "false" 2>/dev/null || true
  dconf write /org/gnome/Ptyxis/scrollbar-policy "'never'" 2>/dev/null || true
  dconf write "/org/gnome/Ptyxis/Profiles/$ptyxis_uuid/label" "'Inferna'" 2>/dev/null || true
  dconf write "/org/gnome/Ptyxis/Profiles/$ptyxis_uuid/palette" "'Inferna'" 2>/dev/null || true
  dconf write "/org/gnome/Ptyxis/Profiles/$ptyxis_uuid/opacity" "0.94" 2>/dev/null || true
fi

mkdir -p "$config/fish/conf.d"
fish_paths_file="$config/fish/conf.d/inferna-paths.fish"
rice_bin_dirs=("$HOME/.local/bin")
for extra_bin in "$here/bin" "$here/gnome/bin"; do
  [[ -d "$extra_bin" ]] && rice_bin_dirs+=("$extra_bin")
done

{
  cat <<EOF
# Auto-generated by $here/install.sh — do not edit manually.
# Re-run ./install.sh to regenerate, or put personal tweaks in ~/.config/fish/user-fish.fish.

set -gx INFERNA_DOTFILES "$here"
set -gx INFERNA_THEMES_DIR "$here/gnome/themes"

EOF
  for bin_dir in "${rice_bin_dirs[@]}"; do
    printf 'if test -d "%s"\n    fish_add_path --path --prepend "%s"\nend\n' "$bin_dir" "$bin_dir"
  done
} > "$fish_paths_file"

user_fish="$config/fish/user-fish.fish"
if [[ ! -e "$user_fish" ]]; then
  cp "$here/fish/user-fish.fish.example" "$user_fish"
  echo "Created personal Fish config at $user_fish"
else
  echo "Keeping existing personal Fish config at $user_fish"
fi

cat <<EOF

Done. Backups of anything replaced are in:
  $backup
EOF
