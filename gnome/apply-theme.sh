#!/usr/bin/env bash
# Apply, live-reload, list, or reset GNOME themes from gnome/themes/.
#
# Usage:
#   inferna-theme <ThemeName>   Apply a theme (symlinks GTK CSS + reloads Shell CSS)
#   inferna-theme --list        List available themes in gnome/themes/
#   inferna-theme --reset       Revert to stock GNOME Adwaita + NixOS defaults
set -euo pipefail

script_path="$(readlink -f "${BASH_SOURCE[0]}")"
repo_root="$(cd "$(dirname "$script_path")/.." && pwd)"
themes_src="$repo_root/gnome/themes"
themes_dest="$HOME/.themes"
gtk4_css="$HOME/.config/gtk-4.0/gtk.css"
gtk3_css="$HOME/.config/gtk-3.0/gtk.css"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") <ThemeName>   Apply or live-reload a GNOME theme
  $(basename "$0") --list        List themes available in $themes_src
  $(basename "$0") --reset       Remove custom CSS overrides and reset GSettings to defaults
EOF
}

has_session() {
  [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v gsettings >/dev/null 2>&1
}

list_themes() {
  if [[ ! -d "$themes_src" ]]; then
    echo "No themes directory found at $themes_src" >&2
    exit 1
  fi
  for dir in "$themes_src"/*/; do
    [[ -d "$dir" ]] || continue
    basename "$dir"
  done
}

reset_theme() {
  rm -f -- "$gtk4_css" "$gtk3_css"
  if has_session; then
    gsettings reset org.gnome.desktop.interface color-scheme 2>/dev/null || true
    gsettings reset org.gnome.desktop.interface accent-color 2>/dev/null || true
    gsettings reset org.gnome.desktop.interface gtk-theme 2>/dev/null || true
    gsettings reset org.gnome.desktop.background picture-uri 2>/dev/null || true
    gsettings reset org.gnome.desktop.background picture-uri-dark 2>/dev/null || true
    gsettings reset org.gnome.desktop.screensaver picture-uri 2>/dev/null || true
    if command -v dconf >/dev/null 2>&1; then
      dconf reset /org/gnome/shell/extensions/user-theme/name 2>/dev/null || true
    fi
  fi
  echo "Reset complete: removed custom GTK CSS symlinks and reverted GNOME settings to NixOS defaults."
}

apply_theme() {
  local name="$1"
  local src="$themes_src/$name"

  if [[ ! -d "$src" ]]; then
    echo "Theme '$name' not found in $themes_src" >&2
    echo "Available themes:" >&2
    list_themes | sed 's/^/  - /' >&2
    exit 1
  fi

  # Symlink the theme directory into ~/.themes/ for GNOME Shell (user-themes)
  mkdir -p "$themes_dest"
  rm -rf -- "$themes_dest/$name"
  ln -sfn "$src" "$themes_dest/$name"

  # Symlink GTK4 / Libadwaita CSS override
  if [[ -f "$src/gtk-4.0/gtk.css" ]]; then
    mkdir -p "$(dirname "$gtk4_css")"
    ln -sfn "$src/gtk-4.0/gtk.css" "$gtk4_css"
  else
    rm -f -- "$gtk4_css"
  fi

  # Symlink GTK3 CSS override
  if [[ -f "$src/gtk-3.0/gtk.css" ]]; then
    mkdir -p "$(dirname "$gtk3_css")"
    ln -sfn "$src/gtk-3.0/gtk.css" "$gtk3_css"
  else
    rm -f -- "$gtk3_css"
  fi

  # Load optional theme metadata
  local COLOR_SCHEME="" ACCENT_COLOR="" GTK_THEME="" WALLPAPER=""
  if [[ -f "$src/theme.env" ]]; then
    # shellcheck source=/dev/null
    source "$src/theme.env"
  fi

  # Auto-detect theme wallpaper.* if WALLPAPER is not explicitly set
  local wallpaper_file=""
  if [[ -n "$WALLPAPER" ]]; then
    if [[ "$WALLPAPER" == /* ]]; then
      wallpaper_file="$WALLPAPER"
    else
      wallpaper_file="$src/$WALLPAPER"
    fi
  else
    for candidate in "$src"/wallpaper.{png,jpg,jpeg,webp}; do
      if [[ -f "$candidate" ]]; then
        wallpaper_file="$candidate"
        break
      fi
    done
  fi

  if has_session; then
    [[ -n "$COLOR_SCHEME" ]] && gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME" 2>/dev/null || true
    [[ -n "$ACCENT_COLOR" ]] && gsettings set org.gnome.desktop.interface accent-color "$ACCENT_COLOR" 2>/dev/null || true
    [[ -n "$GTK_THEME" ]] && gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" 2>/dev/null || true

    if [[ -n "$wallpaper_file" && -f "$wallpaper_file" ]]; then
      local uri="file://$(readlink -f "$wallpaper_file")"
      gsettings set org.gnome.desktop.background picture-uri "$uri" 2>/dev/null || true
      gsettings set org.gnome.desktop.background picture-uri-dark "$uri" 2>/dev/null || true
      gsettings set org.gnome.desktop.screensaver picture-uri "$uri" 2>/dev/null || true
    elif [[ -f "$repo_root/nixos/assets/wallpapers/inferna.jpeg" ]]; then
      local default_wp="$HOME/.local/share/backgrounds/inferna/inferna.jpeg"
      [[ -e "$default_wp" ]] || default_wp="$repo_root/nixos/assets/wallpapers/inferna.jpeg"
      local uri="file://$(readlink -f "$default_wp")"
      gsettings set org.gnome.desktop.background picture-uri "$uri" 2>/dev/null || true
      gsettings set org.gnome.desktop.background picture-uri-dark "$uri" 2>/dev/null || true
      gsettings set org.gnome.desktop.screensaver picture-uri "$uri" 2>/dev/null || true
    else
      gsettings reset org.gnome.desktop.background picture-uri 2>/dev/null || true
      gsettings reset org.gnome.desktop.background picture-uri-dark 2>/dev/null || true
      gsettings reset org.gnome.desktop.screensaver picture-uri 2>/dev/null || true
    fi

    # Enable user-themes extension if GNOME Shell already sees it, and force
    # live-reload of GNOME Shell CSS via dconf.
    if [[ -f "$src/gnome-shell/gnome-shell.css" ]]; then
      if command -v gnome-extensions >/dev/null 2>&1; then
        gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com 2>/dev/null || true
      fi
      if command -v dconf >/dev/null 2>&1; then
        dconf write /org/gnome/shell/extensions/user-theme/name "''" 2>/dev/null || true
        dconf write /org/gnome/shell/extensions/user-theme/name "'$name'" 2>/dev/null || true
      fi
    fi
  else
    echo "No active GNOME D-Bus session detected; CSS symlinks are in place and GSettings will apply on next run in GNOME."
  fi

  echo "Applied GNOME theme '$name'."
  echo "  Shell CSS : $themes_dest/$name/gnome-shell/gnome-shell.css"
  [[ -L "$gtk4_css" ]] && echo "  GTK4 CSS  : $gtk4_css"
  [[ -L "$gtk3_css" ]] && echo "  GTK3 CSS  : $gtk3_css"
  echo "Reopen GTK apps to pick up gtk.css changes."
}

case "${1:-}" in
  ""|-h|--help)
    usage
    ;;
  --list|-l)
    list_themes
    ;;
  --reset|-r)
    reset_theme
    ;;
  *)
    apply_theme "$1"
    ;;
esac
