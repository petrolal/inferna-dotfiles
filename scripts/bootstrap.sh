#!/usr/bin/env bash
# Inferna NixOS Dotfiles — Multi-machine interactive & automated installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/lib/hardware.sh
source "$SCRIPT_DIR/lib/hardware.sh"

# Defaults
ASSUME_YES="${INFERNA_YES:-false}"
PROFILE="${INFERNA_PROFILE:-full}"
DRY_RUN=false
NO_REBUILD=false
OVERRIDE_HOSTNAME=""
OVERRIDE_USERNAME=""
OVERRIDE_GPU=""
OVERRIDE_BOOTLOADER=""
OVERRIDE_NVIDIA_OPEN=""
FLAKE_DIR="/etc/nixos"

# Colors (disabled if stdout is not a TTY)
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_EMBER=$'\033[38;2;255;98;46m'
  C_GOLD=$'\033[38;2;242;169;73m'
  C_RED=$'\033[38;2;217;56;30m'
  C_DIM=$'\033[38;2;148;122;108m'
  C_GREEN=$'\033[38;2;152;185;106m'
else
  C_RESET="" C_BOLD="" C_EMBER="" C_GOLD="" C_RED="" C_DIM="" C_GREEN=""
fi

log()  { printf '%s==>%s %s\n' "$C_EMBER" "$C_RESET" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_GOLD" "$C_RESET" "$*" >&2; }
die()  { printf '%s[error]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Inferna NixOS Multi-Machine Installer

Usage:
  $(basename "$0") [options]

Options:
  -y, --yes                  Non-interactive mode (accept detected defaults)
  -p, --profile <name>       Package profile: full (default) | dev | minimal
      --dry-run              Detect hardware and print generated flake.nix without changing system
      --no-rebuild           Write /etc/nixos/flake.nix and backup, but skip nixos-rebuild switch
      --hostname <name>      Override detected hostname
      --user <name>          Override detected username
      --gpu <vendor>         Override GPU vendor (intel|amd|nvidia|hybrid-intel-nvidia|hybrid-amd-nvidia|vm|generic)
      --nvidia-legacy        Use closed NVIDIA kernel module (for GTX 10xx/9xx pre-Turing GPUs)
      --bootloader <type>    Override bootloader (systemd-boot|grub|none)
      --flake-dir <path>     Target host flake directory (default: /etc/nixos)
  -h, --help                 Show this help message

Profiles:
  full     Core GNOME 51 Inferna rice + Dev/Containers + Gaming + 3D/Image suite + Ollama
  dev      Core GNOME 51 Inferna rice + Dev/Containers + Daily apps (no Gaming, 3D suite, or Ollama)
  minimal  Core GNOME 51 Inferna rice only (GNOME, Plymouth, GDM, Ghostty, Fish, TUI kit, Firefox)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)
        ASSUME_YES=true
        shift
        ;;
      -p|--profile)
        [[ $# -ge 2 ]] || die "--profile requires an argument (full|dev|minimal)"
        PROFILE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --no-rebuild)
        NO_REBUILD=true
        shift
        ;;
      --hostname)
        [[ $# -ge 2 ]] || die "--hostname requires an argument"
        OVERRIDE_HOSTNAME="$2"
        shift 2
        ;;
      --user)
        [[ $# -ge 2 ]] || die "--user requires an argument"
        OVERRIDE_USERNAME="$2"
        shift 2
        ;;
      --gpu)
        [[ $# -ge 2 ]] || die "--gpu requires an argument"
        OVERRIDE_GPU="$2"
        shift 2
        ;;
      --nvidia-legacy)
        OVERRIDE_NVIDIA_OPEN="false"
        shift
        ;;
      --bootloader)
        [[ $# -ge 2 ]] || die "--bootloader requires an argument"
        OVERRIDE_BOOTLOADER="$2"
        shift 2
        ;;
      --flake-dir)
        [[ $# -ge 2 ]] || die "--flake-dir requires an argument"
        FLAKE_DIR="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1 (use --help for usage)"
        ;;
    esac
  done

  case "$PROFILE" in
    full|dev|minimal) ;;
    *) die "Invalid profile '$PROFILE'. Expected: full, dev, or minimal." ;;
  esac
}

apply_profile_flags() {
  case "$1" in
    full)
      HOST_GAMING=true
      HOST_OLLAMA=true
      HOST_DEV=true
      HOST_CONTAINERS=true
      HOST_CREATIVE3D=true
      HOST_DEV_EXTRAS=true
      HOST_DAILY_APPS=true
      HOST_ANTIGRAVITY=true
      ;;
    dev)
      HOST_GAMING=false
      HOST_OLLAMA=false
      HOST_DEV=true
      HOST_CONTAINERS=true
      HOST_CREATIVE3D=false
      HOST_DEV_EXTRAS=true
      HOST_DAILY_APPS=true
      HOST_ANTIGRAVITY=true
      ;;
    minimal)
      HOST_GAMING=false
      HOST_OLLAMA=false
      HOST_DEV=false
      HOST_CONTAINERS=false
      HOST_CREATIVE3D=false
      HOST_DEV_EXTRAS=false
      HOST_DAILY_APPS=false
      HOST_ANTIGRAVITY=false
      ;;
  esac
}

preflight_checks() {
  if [[ "$DRY_RUN" != "true" ]]; then
    [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Do not run as root; run as your normal user."
    [[ -f /etc/NIXOS ]] || die "/etc/NIXOS not found. This installer only supports NixOS."
    command -v sudo >/dev/null 2>&1 || die "sudo is required."
    command -v nixos-rebuild >/dev/null 2>&1 || die "nixos-rebuild not found on PATH."
  fi

  if [[ "$DRY_RUN" != "true" && ! -f "$FLAKE_DIR/hardware-configuration.nix" ]]; then
    warn "$FLAKE_DIR/hardware-configuration.nix not found."
    if [[ "$ASSUME_YES" == "true" ]]; then
      log "Generating hardware configuration with nixos-generate-config..."
      sudo nixos-generate-config --dir "$FLAKE_DIR"
    else
      local ans=""
      read -r -p "Run 'sudo nixos-generate-config --dir $FLAKE_DIR' now? [Y/n] " ans || ans="y"
      if [[ -z "$ans" || "$ans" == [yY]* ]]; then
        sudo nixos-generate-config --dir "$FLAKE_DIR"
      else
        die "Cannot continue without $FLAKE_DIR/hardware-configuration.nix."
      fi
    fi
  fi

  # Disk space advisory (full profile needs ~25 GB+; minimal needs ~10 GB+)
  local free_gb min_gb
  free_gb="$(df -BG --output=avail / 2>/dev/null | tail -n1 | tr -dc '0-9' || echo 0)"
  min_gb=12
  [[ "$PROFILE" == "full" ]] && min_gb=25
  if [[ "$free_gb" -gt 0 && "$free_gb" -lt "$min_gb" ]]; then
    warn "Low disk space on /: ${free_gb}G free (profile '$PROFILE' recommends >= ${min_gb}G)."
  fi
}

detect_host_defaults() {
  HOST_USERNAME="${OVERRIDE_USERNAME:-$(id -un)}"
  HOST_USER_DESC="$(getent passwd "$HOST_USERNAME" 2>/dev/null | cut -d: -f5 | cut -d, -f1 || true)"
  [[ -n "$HOST_USER_DESC" ]] || HOST_USER_DESC="$HOST_USERNAME"

  HOST_HOSTNAME="${OVERRIDE_HOSTNAME:-$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo nixos)}"
  HOST_HOSTNAME="$(printf '%s' "$HOST_HOSTNAME" | tr -d '[:space:]')"
  [[ -n "$HOST_HOSTNAME" ]] || HOST_HOSTNAME="inferna-nixos"

  HOST_REPO_DIR="$REPO_DIR"
  HOST_FLAKE_DIR="$FLAKE_DIR"
  HOST_STATE_VERSION="$(detect_state_version "$FLAKE_DIR/configuration.nix")"
  HOST_BOOTLOADER="${OVERRIDE_BOOTLOADER:-$(detect_bootloader)}"
  HOST_GRUB_DEVICE="$(detect_grub_device)"
  HOST_TIMEZONE="$(detect_timezone)"
  HOST_KEYMAP="$(detect_keymap)"
  HOST_WHEEL_NEEDS_PW="false"

  detect_gpu_system
  HOST_GPU_VENDOR="${OVERRIDE_GPU:-$DETECTED_GPU_VENDOR}"
  HOST_INTEL_BUS_ID="$DETECTED_INTEL_BUS_ID"
  HOST_AMD_BUS_ID="$DETECTED_AMD_BUS_ID"
  HOST_NVIDIA_BUS_ID="$DETECTED_NVIDIA_BUS_ID"
  HOST_NVIDIA_OPEN="${OVERRIDE_NVIDIA_OPEN:-$DETECTED_NVIDIA_OPEN}"
  HOST_CUDA_CAP=""

  case "$HOST_GPU_VENDOR" in
    nvidia|hybrid-intel-nvidia|hybrid-amd-nvidia)
      HOST_NVIDIA_ENABLE="true"
      HOST_CUDA_CAP="$(detect_nvidia_cuda_cap || true)"
      ;;
    *)
      HOST_NVIDIA_ENABLE="false"
      ;;
  esac

  apply_profile_flags "$PROFILE"
}

interactive_review() {
  [[ "$ASSUME_YES" == "true" ]] && return 0

  printf '\n%s%sSelect installation profile:%s\n' "$C_BOLD" "$C_GOLD" "$C_RESET"
  printf '  1) %sfull%s    - Complete workstation (GNOME 51 rice + Dev + Docker + Gaming + 3D/Image + Ollama)\n' "$C_EMBER" "$C_RESET"
  printf '  2) %sdev%s     - Developer desktop (GNOME 51 rice + Dev + Docker + Daily apps)\n' "$C_EMBER" "$C_RESET"
  printf '  3) %sminimal%s - Pure Inferna rice only (GNOME 51, Plymouth, GDM, Ghostty, Fish, TUI, Firefox)\n' "$C_EMBER" "$C_RESET"

  local choice=""
  read -r -p "Profile [1/2/3] (default: $PROFILE): " choice || choice=""
  case "$choice" in
    1|full) PROFILE="full" ;;
    2|dev) PROFILE="dev" ;;
    3|minimal) PROFILE="minimal" ;;
    "") ;;
    *) warn "Unrecognized choice '$choice'; keeping '$PROFILE'." ;;
  esac
  apply_profile_flags "$PROFILE"

  local input=""
  read -r -p "Hostname [$HOST_HOSTNAME]: " input || input=""
  [[ -n "$input" ]] && HOST_HOSTNAME="$input"

  if [[ "$HOST_NVIDIA_ENABLE" == "true" ]]; then
    read -r -p "Use NVIDIA open kernel module (RTX 20xx/30xx/40xx/50xx)? [Y/n]: " input || input=""
    if [[ "$input" == [nN]* ]]; then
      HOST_NVIDIA_OPEN="false"
    fi
  fi

  if [[ "$HOST_BOOTLOADER" == "grub" ]]; then
    read -r -p "BIOS GRUB device [$HOST_GRUB_DEVICE]: " input || input=""
    [[ -n "$input" ]] && HOST_GRUB_DEVICE="$input"
  fi
}

print_summary() {
  printf '\n%s%s╔══════════════════════════════════════════════════════════╗%s\n' "$C_BOLD" "$C_EMBER" "$C_RESET"
  printf '%s%s║              Inferna NixOS Bootstrap Summary             ║%s\n' "$C_BOLD" "$C_EMBER" "$C_RESET"
  printf '%s%s╚══════════════════════════════════════════════════════════╝%s\n' "$C_BOLD" "$C_EMBER" "$C_RESET"
  printf '  %sRepository%s   : %s\n' "$C_GOLD" "$C_RESET" "$HOST_REPO_DIR"
  printf '  %sHost Flake%s   : %s/flake.nix\n' "$C_GOLD" "$C_RESET" "$HOST_FLAKE_DIR"
  printf '  %sHostname%s     : %s\n' "$C_GOLD" "$C_RESET" "$HOST_HOSTNAME"
  printf '  %sUser%s         : %s (%s)\n' "$C_GOLD" "$C_RESET" "$HOST_USERNAME" "$HOST_USER_DESC"
  printf '  %sProfile%s      : %s\n' "$C_GOLD" "$C_RESET" "$PROFILE"
  printf '  %sBootloader%s   : %s%s\n' "$C_GOLD" "$C_RESET" "$HOST_BOOTLOADER" "$( [[ "$HOST_BOOTLOADER" == "grub" ]] && printf ' (%s)' "$HOST_GRUB_DEVICE" )"
  printf '  %sState Version%s: %s\n' "$C_GOLD" "$C_RESET" "$HOST_STATE_VERSION"
  printf '  %sLocale/TZ%s    : %s / %s\n' "$C_GOLD" "$C_RESET" "$HOST_TIMEZONE" "$HOST_KEYMAP"
  printf '  %sGPU Topology%s : %s (NVIDIA=%s' "$C_GOLD" "$C_RESET" "$HOST_GPU_VENDOR" "$HOST_NVIDIA_ENABLE"
  [[ "$HOST_NVIDIA_ENABLE" == "true" ]] && printf ', open=%s' "$HOST_NVIDIA_OPEN"
  [[ -n "$HOST_INTEL_BUS_ID" && "$HOST_NVIDIA_ENABLE" == "true" ]] && printf ', intel=%s' "$HOST_INTEL_BUS_ID"
  [[ -n "$HOST_AMD_BUS_ID" && "$HOST_NVIDIA_ENABLE" == "true" ]] && printf ', amd=%s' "$HOST_AMD_BUS_ID"
  [[ -n "$HOST_NVIDIA_BUS_ID" && "$HOST_NVIDIA_ENABLE" == "true" ]] && printf ', nvidia=%s' "$HOST_NVIDIA_BUS_ID"
  [[ -n "$HOST_CUDA_CAP" ]] && printf ', cuda=%s' "$HOST_CUDA_CAP"
  printf ')\n'
  printf '  %sModules%s      : dev=%s docker=%s gaming=%s 3d=%s ollama=%s daily=%s\n\n' \
    "$C_GOLD" "$C_RESET" "$HOST_DEV" "$HOST_CONTAINERS" "$HOST_GAMING" "$HOST_CREATIVE3D" "$HOST_OLLAMA" "$HOST_DAILY_APPS"
}

main() {
  parse_args "$@"

  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/inferna"
  mkdir -p "$state_dir"
  local log_file="$state_dir/bootstrap.log"

  if [[ "$DRY_RUN" != "true" ]]; then
    exec > >(tee -a "$log_file") 2>&1
    log "Logging installation output to $log_file"
  fi

  preflight_checks
  detect_host_defaults
  interactive_review
  print_summary

  export HOST_HOSTNAME HOST_USERNAME HOST_USER_DESC HOST_REPO_DIR HOST_FLAKE_DIR
  export HOST_STATE_VERSION HOST_BOOTLOADER HOST_GRUB_DEVICE HOST_TIMEZONE HOST_KEYMAP
  export HOST_GPU_VENDOR HOST_NVIDIA_ENABLE HOST_NVIDIA_OPEN HOST_INTEL_BUS_ID
  export HOST_AMD_BUS_ID HOST_NVIDIA_BUS_ID HOST_CUDA_CAP
  export HOST_GAMING HOST_OLLAMA HOST_DEV HOST_CONTAINERS HOST_CREATIVE3D
  export HOST_DEV_EXTRAS HOST_DAILY_APPS HOST_ANTIGRAVITY HOST_WHEEL_NEEDS_PW

  local generated_flake
  generated_flake="$(generate_host_flake)"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry-run mode — generated $HOST_FLAKE_DIR/flake.nix:"
    printf '%s\n' "$generated_flake"
    exit 0
  fi

  if [[ "$ASSUME_YES" != "true" ]]; then
    local confirm=""
    read -r -p "Proceed with installation? [y/N] " confirm || confirm=""
    [[ "$confirm" == [yY]* ]] || { echo "Aborted. Nothing changed."; exit 0; }
  fi

  # Backup existing /etc/nixos cleanly (never touching hardware-configuration.nix in place).
  # Guard against legacy setups where /etc/nixos is a symlink to $REPO_DIR/nixos:
  # writing the generated wrapper flake through that symlink would overwrite
  # $REPO_DIR/nixos/flake.nix and create a circular flake import.
  local real_flake_dir real_repo_nixos
  real_flake_dir="$(readlink -f "$FLAKE_DIR" 2>/dev/null || printf '%s' "$FLAKE_DIR")"
  real_repo_nixos="$(readlink -f "$REPO_DIR/nixos" 2>/dev/null || printf '%s' "$REPO_DIR/nixos")"

  if [[ ! -L "$FLAKE_DIR" && "$real_flake_dir" == "$real_repo_nixos" ]]; then
    die "Target --flake-dir ($FLAKE_DIR) is the same directory as $REPO_DIR/nixos; choose a separate host flake directory (e.g. /etc/nixos)."
  fi

  local ts backup_dir
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_dir="${FLAKE_DIR}.backup-${ts}"
  if [[ -L "$FLAKE_DIR" ]]; then
    log "Detaching symlink $FLAKE_DIR (-> $real_flake_dir) and backing it up to $backup_dir..."
    sudo mv "$FLAKE_DIR" "$backup_dir"
    sudo mkdir -p "$FLAKE_DIR"
    if [[ -f "$real_flake_dir/hardware-configuration.nix" ]]; then
      sudo cp -a "$real_flake_dir/hardware-configuration.nix" "$FLAKE_DIR/hardware-configuration.nix"
      ok "Copied hardware-configuration.nix into new $FLAKE_DIR directory"
    fi
    ok "Backup symlink saved at $backup_dir"
  elif [[ -d "$FLAKE_DIR" ]]; then
    log "Backing up $FLAKE_DIR to $backup_dir..."
    sudo cp -a "$FLAKE_DIR" "$backup_dir"
    ok "Backup created at $backup_dir"
  else
    sudo mkdir -p "$FLAKE_DIR"
  fi

  log "Writing pure host flake to $FLAKE_DIR/flake.nix..."
  printf '%s\n' "$generated_flake" | sudo tee "$FLAKE_DIR/flake.nix" >/dev/null
  sudo chmod 644 "$FLAKE_DIR/flake.nix"

  log "Locking host flake inputs..."
  sudo nix --extra-experimental-features "nix-command flakes" flake update inferna --flake "$FLAKE_DIR"

  if [[ "$NO_REBUILD" == "true" ]]; then
    ok "Host flake generated at $FLAKE_DIR/flake.nix (--no-rebuild set)."
    exit 0
  fi

  log "Applying NixOS configuration (pure flake build: $FLAKE_DIR#$HOST_HOSTNAME)..."
  sudo nixos-rebuild switch \
    --flake "${FLAKE_DIR}#${HOST_HOSTNAME}" \
    --option extra-experimental-features "nix-command flakes"
  ok "NixOS system configuration applied!"

  log "Deploying user dotfiles via $REPO_DIR/install.sh..."
  "$REPO_DIR/install.sh" --yes

  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    ok "Active GNOME D-Bus session detected — theme & extensions applied live."
  else
    # Ensure inferna-first-login runs automatically on the first graphical GNOME login
    rm -f "$state_dir/initialized"
    ok "No graphical D-Bus session yet — inferna-first-login will automatically apply GNOME theme & extensions on your first login after reboot."
  fi

  printf '\n%s%sInferna installation complete!%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
  printf '  Next step: %sreboot%s and log into GNOME.\n' "$C_BOLD" "$C_RESET"
  printf '  Future updates: %scd %s && git pull && inferna-rebuild%s\n\n' "$C_DIM" "$HOST_REPO_DIR" "$C_RESET"
}

main "$@"
