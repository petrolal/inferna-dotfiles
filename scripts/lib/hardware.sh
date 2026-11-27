#!/usr/bin/env bash
# Hardware detection & pure /etc/nixos/flake.nix generation helpers for Inferna.
# Designed to have zero non-core runtime dependencies (falls back to /sys when lspci is absent).

# Convert a PCI address such as "0000:01:00.0", "01:00.0", or "0000:c4:00.0"
# into the decimal format required by NixOS hardware.nvidia.prime.*BusId ("PCI:1:0:0").
pci_addr_to_nix_bus_id() {
  local raw="${1:-}"
  local domain="0" bus="" dev="" func="" rest=""

  raw="${raw##*/}"
  raw="${raw,,}"

  if [[ "$raw" =~ ^([0-9a-f]{4}):([0-9a-f]{2}):([0-9a-f]{2})\.([0-9a-f]+)$ ]]; then
    domain="${BASH_REMATCH[1]}"
    bus="${BASH_REMATCH[2]}"
    dev="${BASH_REMATCH[3]}"
    func="${BASH_REMATCH[4]}"
  elif [[ "$raw" =~ ^([0-9a-f]{2}):([0-9a-f]{2})\.([0-9a-f]+)$ ]]; then
    bus="${BASH_REMATCH[1]}"
    dev="${BASH_REMATCH[2]}"
    func="${BASH_REMATCH[3]}"
  else
    return 1
  fi

  local dom_dec=$((16#$domain))
  local bus_dec=$((16#$bus))
  local dev_dec=$((16#$dev))
  local func_dec=$((16#$func))

  if [[ "$dom_dec" -eq 0 ]]; then
    printf 'PCI:%d:%d:%d\n' "$bus_dec" "$dev_dec" "$func_dec"
  else
    printf 'PCI:%d@%d:%d:%d\n' "$bus_dec" "$dom_dec" "$dev_dec" "$func_dec"
  fi
}

# Escape a string for safe inclusion inside Nix double quotes.
nix_escape_str() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\$\{/\\\$\{}"
  printf '%s' "$s"
}

# Parse normalized "pci_addr vendor_hex" lines (one per display adapter) and set:
#   DETECTED_GPU_VENDOR      (hybrid-intel-nvidia | hybrid-amd-nvidia | nvidia | intel | amd | vm | generic)
#   DETECTED_INTEL_BUS_ID
#   DETECTED_AMD_BUS_ID
#   DETECTED_NVIDIA_BUS_ID
#   DETECTED_NVIDIA_OPEN     (true | false)
classify_gpu_records() {
  local records="${1:-}"
  local is_vm_hint="${2:-false}"

  export DETECTED_GPU_VENDOR="generic"
  export DETECTED_INTEL_BUS_ID=""
  export DETECTED_AMD_BUS_ID=""
  export DETECTED_NVIDIA_BUS_ID=""
  export DETECTED_NVIDIA_OPEN="true"

  local has_intel=0 has_amd=0 has_nvidia=0 has_vm_gpu=0
  local addr vendor bus_id

  while read -r addr vendor _; do
    [[ -z "$addr" || -z "$vendor" ]] && continue
    vendor="${vendor#0x}"
    vendor="${vendor,,}"
    bus_id="$(pci_addr_to_nix_bus_id "$addr" 2>/dev/null || true)"

    case "$vendor" in
      8086)
        has_intel=1
        [[ -z "$DETECTED_INTEL_BUS_ID" && -n "$bus_id" ]] && DETECTED_INTEL_BUS_ID="$bus_id"
        ;;
      1002)
        has_amd=1
        [[ -z "$DETECTED_AMD_BUS_ID" && -n "$bus_id" ]] && DETECTED_AMD_BUS_ID="$bus_id"
        ;;
      10de)
        has_nvidia=1
        [[ -z "$DETECTED_NVIDIA_BUS_ID" && -n "$bus_id" ]] && DETECTED_NVIDIA_BUS_ID="$bus_id"
        ;;
      1af4|1b36|1234|15ad|80ee|1414)
        has_vm_gpu=1
        ;;
    esac
  done <<< "$records"

  if [[ "$has_nvidia" -eq 1 && "$has_intel" -eq 1 ]]; then
    DETECTED_GPU_VENDOR="hybrid-intel-nvidia"
  elif [[ "$has_nvidia" -eq 1 && "$has_amd" -eq 1 ]]; then
    DETECTED_GPU_VENDOR="hybrid-amd-nvidia"
  elif [[ "$has_nvidia" -eq 1 ]]; then
    DETECTED_GPU_VENDOR="nvidia"
  elif [[ "$has_intel" -eq 1 ]]; then
    DETECTED_GPU_VENDOR="intel"
  elif [[ "$has_amd" -eq 1 ]]; then
    DETECTED_GPU_VENDOR="amd"
  elif [[ "$has_vm_gpu" -eq 1 || "$is_vm_hint" == "true" ]]; then
    DETECTED_GPU_VENDOR="vm"
  else
    DETECTED_GPU_VENDOR="generic"
  fi
}

# Parse raw `lspci -Dnn` or `lspci -nn` output into normalized display adapter records.
extract_gpu_records_from_lspci() {
  local lspci_text="${1:-}"
  local line addr vendor

  while IFS= read -r line; do
    # Match PCI class 0300 (VGA), 0302 (3D controller), 0380 (Display controller)
    if [[ "$line" =~ ^([0-9a-fA-F:.]+)[[:space:]].*\[03(00|02|80)\]:.*\[([0-9a-fA-F]{4}):[0-9a-fA-F]{4}\] ]]; then
      addr="${BASH_REMATCH[1]}"
      vendor="${BASH_REMATCH[3]}"
      printf '%s %s\n' "$addr" "$vendor"
    fi
  done <<< "$lspci_text"
}

# Pure-sysfs fallback (works on minimal NixOS installs without pciutils/lspci).
extract_gpu_records_from_sysfs() {
  local sys_root="${1:-/sys/bus/pci/devices}"
  local dev class vendor addr

  [[ -d "$sys_root" ]] || return 0
  for dev in "$sys_root"/*; do
    [[ -r "$dev/class" && -r "$dev/vendor" ]] || continue
    class="$(<"$dev/class")"
    class="${class,,}"
    # 0x0300xx = VGA, 0x0302xx = 3D controller, 0x0380xx = Display controller
    if [[ "$class" == 0x0300* || "$class" == 0x0302* || "$class" == 0x0380* ]]; then
      vendor="$(<"$dev/vendor")"
      addr="${dev##*/}"
      printf '%s %s\n' "$addr" "$vendor"
    fi
  done
}

detect_is_vm() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    if systemd-detect-virt --vm --quiet 2>/dev/null; then
      echo "true"
      return 0
    fi
  fi
  if [[ -r /sys/class/dmi/id/product_name ]]; then
    local prod
    prod="$(</sys/class/dmi/id/product_name)"
    case "${prod,,}" in
      *qemu*|*kvm*|*virtualbox*|*vmware*|*bochs*|*hyper-v*|*parallels*|*xen*)
        echo "true"
        return 0
        ;;
    esac
  fi
  echo "false"
}

detect_gpu_system() {
  local records="" is_vm="false"
  is_vm="$(detect_is_vm)"

  if command -v lspci >/dev/null 2>&1; then
    records="$(extract_gpu_records_from_lspci "$(lspci -Dnn 2>/dev/null || true)")"
  fi
  if [[ -z "$records" ]]; then
    records="$(extract_gpu_records_from_sysfs /sys/bus/pci/devices)"
  fi

  classify_gpu_records "$records" "$is_vm"
}

detect_nvidia_cuda_cap() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    local cap
    cap="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
    if [[ "$cap" =~ ^[0-9]+\.[0-9]+$ ]]; then
      printf '%s\n' "$cap"
      return 0
    fi
  fi
  return 0
}

detect_bootloader() {
  if [[ -d /sys/firmware/efi ]]; then
    echo "systemd-boot"
  else
    echo "grub"
  fi
}

detect_grub_device() {
  if command -v findmnt >/dev/null 2>&1 && command -v lsblk >/dev/null 2>&1; then
    local root_src pkname
    root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
    if [[ -n "$root_src" && -b "$root_src" ]]; then
      pkname="$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n1 || true)"
      if [[ -n "$pkname" && -b "/dev/$pkname" ]]; then
        printf '/dev/%s\n' "$pkname"
        return 0
      fi
    fi
  fi
  echo "/dev/sda"
}

detect_state_version() {
  local config_file="${1:-/etc/nixos/configuration.nix}"
  if [[ -r "$config_file" ]]; then
    local ver
    ver="$(sed -nE 's/^[[:space:]]*system\.stateVersion[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$config_file" | head -n1 || true)"
    if [[ -n "$ver" ]]; then
      printf '%s\n' "$ver"
      return 0
    fi
  fi
  echo "26.05"
}

detect_timezone() {
  if [[ -L /etc/localtime ]]; then
    local target
    target="$(readlink -f /etc/localtime 2>/dev/null || true)"
    if [[ "$target" == */zoneinfo/* ]]; then
      printf '%s\n' "${target#*/zoneinfo/}"
      return 0
    fi
  fi
  echo "America/Sao_Paulo"
}

detect_keymap() {
  if [[ -r /etc/vconsole.conf ]]; then
    local km
    km="$(sed -nE 's/^[[:space:]]*KEYMAP="?([^"[:space:]]+)"?.*/\1/p' /etc/vconsole.conf | head -n1 || true)"
    if [[ -n "$km" ]]; then
      printf '%s\n' "$km"
      return 0
    fi
  fi
  echo "us-acentos"
}

# Generate a 100% pure /etc/nixos/flake.nix for any machine.
# Reads parameters from environment variables prefixed with HOST_:
#   HOST_HOSTNAME, HOST_USERNAME, HOST_USER_DESC, HOST_REPO_DIR, HOST_FLAKE_DIR,
#   HOST_STATE_VERSION, HOST_BOOTLOADER, HOST_GRUB_DEVICE, HOST_TIMEZONE, HOST_KEYMAP,
#   HOST_GPU_VENDOR, HOST_NVIDIA_ENABLE, HOST_NVIDIA_OPEN, HOST_INTEL_BUS_ID,
#   HOST_AMD_BUS_ID, HOST_NVIDIA_BUS_ID, HOST_CUDA_CAP,
#   HOST_GAMING, HOST_OLLAMA, HOST_DEV, HOST_CONTAINERS, HOST_CREATIVE3D,
#   HOST_DEV_EXTRAS, HOST_DAILY_APPS, HOST_ANTIGRAVITY, HOST_WHEEL_NEEDS_PW
generate_host_flake() {
  local hostname="${HOST_HOSTNAME:?HOST_HOSTNAME required}"
  local username="${HOST_USERNAME:?HOST_USERNAME required}"
  local user_desc="${HOST_USER_DESC:-$username}"
  local repo_dir="${HOST_REPO_DIR:?HOST_REPO_DIR required}"
  local flake_dir="${HOST_FLAKE_DIR:-/etc/nixos}"
  local state_version="${HOST_STATE_VERSION:-26.05}"
  local bootloader="${HOST_BOOTLOADER:-systemd-boot}"
  local grub_device="${HOST_GRUB_DEVICE:-/dev/sda}"
  local timezone="${HOST_TIMEZONE:-America/Sao_Paulo}"
  local keymap="${HOST_KEYMAP:-us-acentos}"
  local gpu_vendor="${HOST_GPU_VENDOR:-generic}"
  local nvidia_enable="${HOST_NVIDIA_ENABLE:-false}"
  local nvidia_open="${HOST_NVIDIA_OPEN:-true}"
  local intel_bus_id="${HOST_INTEL_BUS_ID:-}"
  local amd_bus_id="${HOST_AMD_BUS_ID:-}"
  local nvidia_bus_id="${HOST_NVIDIA_BUS_ID:-}"
  local cuda_cap="${HOST_CUDA_CAP:-}"
  local gaming="${HOST_GAMING:-true}"
  local ollama="${HOST_OLLAMA:-true}"
  local development="${HOST_DEV:-true}"
  local containers="${HOST_CONTAINERS:-true}"
  local creative3d="${HOST_CREATIVE3D:-true}"
  local dev_extras="${HOST_DEV_EXTRAS:-true}"
  local daily_apps="${HOST_DAILY_APPS:-true}"
  local antigravity="${HOST_ANTIGRAVITY:-true}"
  local wheel_needs_pw="${HOST_WHEEL_NEEDS_PW:-false}"

  local esc_hostname esc_username esc_user_desc esc_repo_dir esc_flake_dir
  local esc_state_ver esc_bootloader esc_grub_dev esc_tz esc_km esc_gpu
  esc_hostname="$(nix_escape_str "$hostname")"
  esc_username="$(nix_escape_str "$username")"
  esc_user_desc="$(nix_escape_str "$user_desc")"
  esc_repo_dir="$(nix_escape_str "$repo_dir")"
  esc_flake_dir="$(nix_escape_str "$flake_dir")"
  esc_state_ver="$(nix_escape_str "$state_version")"
  esc_bootloader="$(nix_escape_str "$bootloader")"
  esc_grub_dev="$(nix_escape_str "$grub_device")"
  esc_tz="$(nix_escape_str "$timezone")"
  esc_km="$(nix_escape_str "$keymap")"
  esc_gpu="$(nix_escape_str "$gpu_vendor")"

  local grub_line=""
  if [[ "$bootloader" == "grub" ]]; then
    grub_line="              grubDevice = \"${esc_grub_dev}\";"
  fi

  local nvidia_block=""
  if [[ "$nvidia_enable" == "true" ]]; then
    local cuda_line=""
    if [[ -n "$cuda_cap" ]]; then
      cuda_line="                cudaCapabilities = [ \"$(nix_escape_str "$cuda_cap")\" ];"
    fi

    local prime_block=""
    if [[ -n "$nvidia_bus_id" && ( -n "$intel_bus_id" || -n "$amd_bus_id" ) ]]; then
      local igpu_line=""
      if [[ -n "$intel_bus_id" ]]; then
        igpu_line="                  intelBusId = \"$(nix_escape_str "$intel_bus_id")\";"
      else
        igpu_line="                  amdgpuBusId = \"$(nix_escape_str "$amd_bus_id")\";"
      fi
      prime_block=$(cat <<EOF
                prime = {
                  enable = true;
${igpu_line}
                  nvidiaBusId = "$(nix_escape_str "$nvidia_bus_id")";
                };
EOF
)
    fi

    nvidia_block=$(cat <<EOF
              nvidia = {
                enable = true;
                open = ${nvidia_open};
${cuda_line:+${cuda_line}
}${prime_block:+${prime_block}
}              };
EOF
)
  else
    nvidia_block="              nvidia.enable = false;"
  fi

  cat <<EOF
# Auto-generated by Inferna bootstrap.sh — pure per-machine NixOS flake.
# Update the rice anytime with:
#   cd ${esc_repo_dir} && git pull && inferna-rebuild
{
  description = "Inferna NixOS host configuration (${esc_hostname})";

  inputs = {
    inferna.url = "path:${esc_repo_dir}/nixos";
  };

  outputs =
    { inferna, ... }:
    {
      nixosConfigurations."${esc_hostname}" = inferna.lib.mkHost {
        hostname = "${esc_hostname}";
        hardwareConfig = ./hardware-configuration.nix;
        extraModules = [
          {
            system.stateVersion = "${esc_state_ver}";

            dotfiles = {
              username = "${esc_username}";
              userDescription = "${esc_user_desc}";
              repoPath = "${esc_repo_dir}";
              flakePath = "${esc_flake_dir}";
              wheelNeedsPassword = ${wheel_needs_pw};

              bootloader = "${esc_bootloader}";
${grub_line:+${grub_line}
}              timeZone = "${esc_tz}";
              consoleKeyMap = "${esc_km}";

              gpu.vendor = "${esc_gpu}";
${nvidia_block}

              gaming.enable = ${gaming};
              ollama.enable = ${ollama};
              development.enable = ${development};
              containers.enable = ${containers};
              antigravity.enable = ${antigravity};

              packages = {
                devExtras.enable = ${dev_extras};
                creative3d.enable = ${creative3d};
                dailyApps.enable = ${daily_apps};
              };
            };
          }
        ];
      };
    };
}
EOF
}
