#!/usr/bin/env bash
# Inferna NixOS Dotfiles — One-line multi-machine bootstrapper
#
# Usage (from a freshly formatted NixOS machine):
#   curl -fsSL https://raw.githubusercontent.com/petrolal/inferna-dotfiles/main/bootstrap.sh | bash
#
# Non-interactive / profile examples:
#   curl -fsSL https://raw.githubusercontent.com/petrolal/inferna-dotfiles/main/bootstrap.sh | bash -s -- --yes --profile full
#   curl -fsSL https://raw.githubusercontent.com/petrolal/inferna-dotfiles/main/bootstrap.sh | bash -s -- --yes --profile minimal
#   curl -fsSL https://raw.githubusercontent.com/petrolal/inferna-dotfiles/main/bootstrap.sh | bash -s -- --dry-run
#
# Environment overrides:
#   INFERNA_REPO_URL  Git repository URL (default: https://github.com/petrolal/inferna-dotfiles.git)
#   INFERNA_BRANCH    Git branch/tag to track (default: main)
#   INFERNA_DIR       Local checkout directory (default: $HOME/inferna-dotfiles)

set -euo pipefail

main() {
  local repo_url="${INFERNA_REPO_URL:-https://github.com/petrolal/inferna-dotfiles.git}"
  local branch="${INFERNA_BRANCH:-main}"
  local repo_dir="${INFERNA_DIR:-$HOME/inferna-dotfiles}"

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "Error: Do not run bootstrap.sh as root. Run it as your regular user (sudo will be used when needed)." >&2
    exit 1
  fi

  if [[ ! -f /etc/NIXOS ]]; then
    echo "Error: /etc/NIXOS not found. This installer targets NixOS machines." >&2
    exit 1
  fi

  run_git() {
    if command -v git >/dev/null 2>&1; then
      git "$@"
    elif command -v nix >/dev/null 2>&1; then
      nix --extra-experimental-features "nix-command flakes" shell nixpkgs#git -c git "$@"
    elif command -v nix-shell >/dev/null 2>&1; then
      nix-shell -p git --run "git $(printf '%q ' "$@")"
    else
      echo "Error: neither git nor nix is available on PATH." >&2
      exit 1
    fi
  }

  echo "==> Preparing Inferna dotfiles at $repo_dir..."
  if [[ -d "$repo_dir/.git" ]]; then
    if [[ -z "$(run_git -C "$repo_dir" status --porcelain 2>/dev/null || true)" ]]; then
      echo "==> Updating existing clean checkout ($branch)..."
      run_git -C "$repo_dir" fetch origin "$branch" || true
      run_git -C "$repo_dir" checkout "$branch" 2>/dev/null || true
      run_git -C "$repo_dir" pull --ff-only origin "$branch" || true
    else
      echo "==> Keeping existing checkout with local changes at $repo_dir."
    fi
  elif [[ -e "$repo_dir" ]]; then
    echo "Error: $repo_dir already exists and is not a git repository. Move it or set INFERNA_DIR." >&2
    exit 1
  else
    run_git clone --branch "$branch" "$repo_url" "$repo_dir"
  fi

  local installer="$repo_dir/scripts/bootstrap.sh"
  if [[ ! -f "$installer" ]]; then
    echo "Error: Expected installer script at $installer" >&2
    exit 1
  fi
  chmod +x "$installer" "$repo_dir/install.sh"

  # Reconnect stdin to /dev/tty when piped through `curl ... | bash` so prompts work.
  if [[ ! -t 0 && -r /dev/tty ]]; then
    exec "$installer" "$@" < /dev/tty
  else
    exec "$installer" "$@"
  fi
}

main "$@"
