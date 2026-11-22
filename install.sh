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
  - Ghostty terminal config        -> ~/.config/ghostty/config
  - Inferna TUI suite              -> ~/.config/{btop,yazi,cava,bat}/
  - MangoHud & Qt6 Inferna themes  -> ~/.config/{MangoHud,qt6ct}/
  - GNOME themes (Inferna, etc.)   -> ~/.themes/
  - GTK4 / GTK3 CSS overrides      -> ~/.config/gtk-{4,3}.0/gtk.css
  - Default wallpapers             -> ~/.local/share/backgrounds/inferna/
  - Theme & extension helpers      -> ~/.local/bin/inferna-{theme,extensions}

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

echo "Installing fastfetch dashboard..."
place "$here/fastfetch/config.jsonc" "$config/fastfetch/config.jsonc"
place "$here/fastfetch/compact.jsonc" "$config/fastfetch/compact.jsonc"
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

echo "Installing Fish config, Starship prompt, Ghostty config, Inferna TUI suite, and dynamic rice paths..."
place "$here/fish/config.fish" "$config/fish/config.fish"
place "$here/starship/starship.toml" "$config/starship.toml"
place "$here/ghostty/config" "$config/ghostty/config"
place "$here/btop/btop.conf" "$config/btop/btop.conf"
place "$here/btop/themes/inferna.theme" "$config/btop/themes/inferna.theme"
place "$here/yazi/yazi.toml" "$config/yazi/yazi.toml"
place "$here/yazi/theme.toml" "$config/yazi/theme.toml"
place "$here/cava/config" "$config/cava/config"
place "$here/bat/config" "$config/bat/config"
place "$here/mangohud/MangoHud.conf" "$config/MangoHud/MangoHud.conf"
place "$here/qt6ct/colors/inferna.conf" "$config/qt6ct/colors/inferna.conf"
mkdir -p "$config/qt6ct"
save "$config/qt6ct/qt6ct.conf"
sed "s|@HOME@|$HOME|g" "$here/qt6ct/qt6ct.conf" > "$config/qt6ct/qt6ct.conf"

if command -v dconf >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  # Bind Ctrl+Alt+T to open a new Ghostty window (preserving any other custom shortcuts)
  term_kb="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/inferna-terminal/"
  dconf write "${term_kb}name" "'Terminal (Ghostty)'" 2>/dev/null || true
  dconf write "${term_kb}command" "'ghostty'" 2>/dev/null || true
  dconf write "${term_kb}binding" "'<Control><Alt>t'" 2>/dev/null || true
  existing_kbs="$(dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings 2>/dev/null || true)"
  if [[ -z "$existing_kbs" || "$existing_kbs" == "@as []" ]]; then
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "['$term_kb']" 2>/dev/null || true
  elif [[ "$existing_kbs" != *"$term_kb"* ]]; then
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "${existing_kbs%]}, '$term_kb']" 2>/dev/null || true
  fi
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
