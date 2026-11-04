#!/usr/bin/env bash
# Install Inferna dotfiles (rebranded Pebble Shell on NixOS / Linux)
# Everything it replaces is copied to ~/.config/inferna-dotfiles-backup/<time>-<id>/ first.
#
#   ./install.sh          install, asking once before changing anything
#   ./install.sh --yes    install without asking
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="$HOME/.config"

export INFERNA_PATH="${INFERNA_PATH:-$here/core}"
export OMARCHY_PATH="${OMARCHY_PATH:-$INFERNA_PATH}"
export PATH="$here/core/bin:$HOME/.local/bin:$PATH"

mkdir -p "$HOME/.local/bin"
ln -sf "$here/core/bin/inferna" "$HOME/.local/bin/inferna"
ln -sf "$here/core/bin/inferna-shell" "$HOME/.local/bin/inferna-shell"
ln -sf "$here/core/bin/inferna-launch-shell" "$HOME/.local/bin/inferna-launch-shell"
ln -sf "$here/core/bin/inferna-restart-shell" "$HOME/.local/bin/inferna-restart-shell"
ln -sf "$here/core/bin/omarchy" "$HOME/.local/bin/omarchy"
ln -sf "$here/core/bin/omarchy-shell" "$HOME/.local/bin/omarchy-shell"
ln -sf "$here/core/bin/omarchy-launch-shell" "$HOME/.local/bin/omarchy-launch-shell"
ln -sf "$here/core/bin/omarchy-restart-shell" "$HOME/.local/bin/omarchy-restart-shell"

if ! command -v inferna >/dev/null 2>&1; then
  echo "inferna not found in PATH or $here/core/bin." >&2
  exit 1
fi

if [[ -n "${XDG_CONFIG_HOME:-}" && "$(realpath -m "$XDG_CONFIG_HOME")" != "$(realpath -m "$config")" ]]; then
  echo "XDG_CONFIG_HOME is set to $XDG_CONFIG_HOME. These dots only support ~/.config." >&2
  exit 1
fi

# External plugins (pre-bundled in $here/plugins): "<git url> <plugin id>".
external=(
  "https://github.com/denonmaryland/hello-lock hello-lock"
  "https://github.com/denonmaryland/omarchy-theme-studio io.github.denonmaryland.theme-studio"
  "https://github.com/denonmaryland/omarchy-tricky-tiles io.github.denonmaryland.tricky-tiles"
  "https://github.com/denonmaryland/omarchy-softly io.github.denonmaryland.softly"
)

if [[ "${1:-}" != "--yes" ]]; then
  cat <<EOF
This will install Inferna Dotfiles into your home folder:
  - 24 shell plugins       -> ~/.config/inferna/plugins/
  - bar layout             -> ~/.config/inferna/shell.json
  - compat symlink         -> ~/.config/omarchy -> ~/.config/inferna
  - Hyprland look and keys -> ~/.config/hypr/ (monitors.lua is left alone)
  - fastfetch and foot     -> ~/.config/fastfetch/, ~/.config/foot/
  - helper scripts         -> ~/.local/share/, ~/.local/bin/
  - Hello Lock, Theme Studio, Tricky Tiles and Softly

Anything it replaces is backed up to a new folder in ~/.config/inferna-dotfiles-backup/.
EOF
  read -r -p "Continue? [y/N] " answer || answer=""
  [[ "$answer" == [yY]* ]] || { echo "Nothing changed."; exit 0; }
fi

# A fresh, unique backup folder for this run.
mkdir -p "$config/inferna-dotfiles-backup"
backup="$(mktemp -d "$config/inferna-dotfiles-backup/$(date +%Y%m%d-%H%M%S)-XXXX")"

# Save a copy of a path (if it exists) into the backup, keeping its place
# relative to $HOME. Only the first copy of each path is kept.
save() {
  local dest="$1" rel="${1#"$HOME"/}"
  [[ -e "$dest" && ! -e "$backup/$rel" ]] || return 0
  mkdir -p "$backup/$(dirname "$rel")"
  cp -a "$dest" "$backup/$rel"
}

# Replace a file or folder with ours, after saving the original.
place() {
  local src="$1" dest="$2"
  save "$dest"
  rm -rf -- "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

mkdir -p "$config/inferna/plugins"

# Symlink ~/.config/omarchy to ~/.config/inferna for backward compatibility with external plugins
if [[ ! -L "$config/omarchy" ]]; then
  if [[ -d "$config/omarchy" ]]; then
    save "$config/omarchy"
    rm -rf "$config/omarchy"
  fi
  ln -sfn "$config/inferna" "$config/omarchy"
fi

# The original bar layout, before plugins change it.
save "$config/inferna/shell.json"

echo "Installing plugins..."
for plugin in "$here"/plugins/*/; do
  place "${plugin%/}" "$config/inferna/plugins/$(basename "$plugin")"
done

echo "Installing helpers..."
for dir in "$here"/local/share/*/; do
  place "${dir%/}" "$HOME/.local/share/$(basename "$dir")"
done
for bin in "$here"/local/bin/*; do
  place "$bin" "$HOME/.local/bin/$(basename "$bin")"
  chmod +x "$HOME/.local/bin/$(basename "$bin")"
done

echo "Installing Hyprland, fastfetch and foot config..."
for file in "$here"/hypr/*.lua; do
  place "$file" "$config/hypr/$(basename "$file")"
done
place "$here/fastfetch/config.jsonc" "$config/fastfetch/config.jsonc"
place "$here/fastfetch/dashboard.py" "$config/fastfetch/dashboard.py"
place "$here/foot/foot.ini" "$config/foot/foot.ini"

# Touchpad drawer: write its settings file once, from the current values.
if [[ ! -e "$config/hypr/touchpad-control.lua" ]] &&
   hyprctl devices -j 2>/dev/null | grep -qi '"name": *"[^"]*touchpad'; then
  python3 "$HOME/.local/share/touchpad-control/control.py" init >/dev/null 2>&1 ||
    echo "  touchpad controls not set up (you can still use the defaults)"
fi

echo "Adding Hello Lock, Theme Studio, Tricky Tiles and Softly..."
missing=()
for entry in "${external[@]}"; do
  read -r repo id <<<"$entry"
  save "$config/inferna/plugins/$id"
  if [[ -f "$config/inferna/plugins/$id/manifest.json" ]]; then
    continue
  fi
  if ! omarchy plugin add "$repo" --enable --yes || [[ ! -f "$config/inferna/plugins/$id/manifest.json" ]]; then
    echo "  could not add $repo (try later: inferna plugin add $repo --enable)"
    missing+=("$id")
  fi
done

# The bar layout goes last: it names the plugins above.
place "$here/inferna/shell.json" "$config/inferna/shell.json"
if (( ${#missing[@]} )); then
  python3 - "$config/inferna/shell.json" "${missing[@]}" <<'PY'
import json, sys
path, missing = sys.argv[1], set(sys.argv[2:])
d = json.load(open(path))
d["plugins"] = [p for p in d.get("plugins", []) if p.get("id") not in missing]
for side, items in d.get("bar", {}).get("layout", {}).items():
    d["bar"]["layout"][side] = [w for w in items if w.get("id") not in missing]
if "hello-lock" in missing:
    d["disabledPlugins"] = [p for p in d.get("disabledPlugins", []) if p != "omarchy.lock"]
json.dump(d, open(path, "w"), indent=2)
PY
fi

echo "Reloading..."
hyprctl reload >/dev/null 2>&1 || true
inferna-restart-shell >/dev/null 2>&1 || true

cat <<EOF

Done. Backups of anything replaced are in:
  $backup
EOF
if (( ${#missing[@]} )); then
  echo "Not installed (left out of the bar): ${missing[*]}"
fi
echo 'To customize the menu and fastfetch, see the README.'
