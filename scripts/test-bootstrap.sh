#!/usr/bin/env bash
# Automated test suite for Inferna multi-machine bootstrap & hardware detection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/lib/hardware.sh
source "$SCRIPT_DIR/lib/hardware.sh"

passed=0
failed=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  [PASS] %s\n' "$label"
    passed=$((passed + 1))
  else
    printf '  [FAIL] %s: expected=%q actual=%q\n' "$label" "$expected" "$actual" >&2
    failed=$((failed + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf '  [PASS] %s\n' "$label"
    passed=$((passed + 1))
  else
    printf '  [FAIL] %s: missing substring %q\n' "$label" "$needle" >&2
    failed=$((failed + 1))
  fi
}

echo "==> 1. Bash syntax checks"
for f in \
  "$REPO_DIR/bootstrap.sh" \
  "$REPO_DIR/install.sh" \
  "$REPO_DIR/scripts/bootstrap.sh" \
  "$REPO_DIR/scripts/lib/hardware.sh" \
  "$REPO_DIR/scripts/test-bootstrap.sh"; do
  bash -n "$f"
  assert_eq "bash -n $(basename "$f")" "0" "$?"
done

echo "==> 2. PCI address hex->decimal conversion"
assert_eq "0000:00:02.0" "PCI:0:2:0" "$(pci_addr_to_nix_bus_id "0000:00:02.0")"
assert_eq "01:00.0" "PCI:1:0:0" "$(pci_addr_to_nix_bus_id "01:00.0")"
assert_eq "0000:c4:00.0 (hex bus c4=196)" "PCI:196:0:0" "$(pci_addr_to_nix_bus_id "0000:c4:00.0")"
assert_eq "0000:0a:1f.2 (hex dev 1f=31)" "PCI:10:31:2" "$(pci_addr_to_nix_bus_id "0000:0a:1f.2")"
assert_eq "0001:02:00.0 (non-zero domain)" "PCI:2@1:0:0" "$(pci_addr_to_nix_bus_id "0001:02:00.0")"

echo "==> 3. GPU topology detection across machine types"

# 3a. Intel + NVIDIA hybrid laptop
lspci_intel_nv=$'0000:00:02.0 VGA compatible controller [0300]: Intel Corporation Raptor Lake-P [8086:a7a0] (rev 04)\n0000:01:00.0 3D controller [0302]: NVIDIA Corporation AD107M [GeForce RTX 4050 Max-Q / Mobile] [10de:28a1] (rev a1)'
classify_gpu_records "$(extract_gpu_records_from_lspci "$lspci_intel_nv")" "false"
assert_eq "Intel+NVIDIA vendor" "hybrid-intel-nvidia" "$DETECTED_GPU_VENDOR"
assert_eq "Intel+NVIDIA intelBusId" "PCI:0:2:0" "$DETECTED_INTEL_BUS_ID"
assert_eq "Intel+NVIDIA nvidiaBusId" "PCI:1:0:0" "$DETECTED_NVIDIA_BUS_ID"

# 3b. AMD + NVIDIA hybrid laptop (hex bus c4)
lspci_amd_nv=$'0000:c4:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Phoenix1 [1002:15bf]\n0000:01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA106M [10de:2520]'
classify_gpu_records "$(extract_gpu_records_from_lspci "$lspci_amd_nv")" "false"
assert_eq "AMD+NVIDIA vendor" "hybrid-amd-nvidia" "$DETECTED_GPU_VENDOR"
assert_eq "AMD+NVIDIA amdBusId" "PCI:196:0:0" "$DETECTED_AMD_BUS_ID"
assert_eq "AMD+NVIDIA nvidiaBusId" "PCI:1:0:0" "$DETECTED_NVIDIA_BUS_ID"

# 3c. Dedicated NVIDIA desktop
lspci_nv_only=$'0000:0b:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD103 [GeForce RTX 4080] [10de:2704]'
classify_gpu_records "$(extract_gpu_records_from_lspci "$lspci_nv_only")" "false"
assert_eq "NVIDIA-only vendor" "nvidia" "$DETECTED_GPU_VENDOR"
assert_eq "NVIDIA-only nvidiaBusId" "PCI:11:0:0" "$DETECTED_NVIDIA_BUS_ID"

# 3d. Intel-only laptop (e.g. ThinkPad)
lspci_intel_only=$'00:02.0 VGA compatible controller [0300]: Intel Corporation Alder Lake-UP3 GT2 [8086:46a8]'
classify_gpu_records "$(extract_gpu_records_from_lspci "$lspci_intel_only")" "false"
assert_eq "Intel-only vendor" "intel" "$DETECTED_GPU_VENDOR"

# 3e. AMD-only desktop
lspci_amd_only=$'0000:03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [1002:744c]'
classify_gpu_records "$(extract_gpu_records_from_lspci "$lspci_amd_only")" "false"
assert_eq "AMD-only vendor" "amd" "$DETECTED_GPU_VENDOR"

# 3f. QEMU/VirtIO VM
lspci_vm=$'00:01.0 VGA compatible controller [0300]: Red Hat, Inc. Virtio 1.0 GPU [1af4:1050]'
classify_gpu_records "$(extract_gpu_records_from_lspci "$lspci_vm")" "true"
assert_eq "VM vendor" "vm" "$DETECTED_GPU_VENDOR"

# 3g. Pure sysfs fallback (no lspci installed)
tmp_sys="$(mktemp -d)"
trap 'rm -rf "$tmp_sys"' EXIT
mkdir -p "$tmp_sys/0000:00:02.0" "$tmp_sys/0000:01:00.0" "$tmp_sys/0000:00:1f.3"
echo "0x030000" > "$tmp_sys/0000:00:02.0/class"
echo "0x8086"   > "$tmp_sys/0000:00:02.0/vendor"
echo "0x030200" > "$tmp_sys/0000:01:00.0/class"
echo "0x10de"   > "$tmp_sys/0000:01:00.0/vendor"
echo "0x040300" > "$tmp_sys/0000:00:1f.3/class"
echo "0x8086"   > "$tmp_sys/0000:00:1f.3/vendor"
classify_gpu_records "$(extract_gpu_records_from_sysfs "$tmp_sys")" "false"
assert_eq "sysfs fallback Intel+NVIDIA" "hybrid-intel-nvidia" "$DETECTED_GPU_VENDOR"
assert_eq "sysfs fallback intelBusId" "PCI:0:2:0" "$DETECTED_INTEL_BUS_ID"
assert_eq "sysfs fallback nvidiaBusId" "PCI:1:0:0" "$DETECTED_NVIDIA_BUS_ID"

echo "==> 4. Host flake generation & dry-run end-to-end"
dry_out="$("$REPO_DIR/scripts/bootstrap.sh" --dry-run --yes --profile minimal --hostname test-vm --user alice --gpu vm --bootloader grub)"
assert_contains "dry-run sets hostname" 'hostname = "test-vm";' "$dry_out"
assert_contains "dry-run sets username" 'username = "alice";' "$dry_out"
assert_contains "dry-run sets bootloader grub" 'bootloader = "grub";' "$dry_out"
assert_contains "dry-run disables nvidia" 'nvidia.enable = false;' "$dry_out"
assert_contains "dry-run minimal disables gaming" 'gaming.enable = false;' "$dry_out"
assert_contains "dry-run minimal disables ollama" 'ollama.enable = false;' "$dry_out"

echo "==> 5. Generated host flake pure Nix evaluation (when nix is available)"
if command -v nix >/dev/null 2>&1; then
  tmp_host="$tmp_sys/host-flake"
  mkdir -p "$tmp_host"
  cat > "$tmp_host/hardware-configuration.nix" <<'EOF'
{ ... }:
{
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };
}
EOF
  HOST_HOSTNAME="ci-test-host" \
  HOST_USERNAME="alice" \
  HOST_USER_DESC="Alice" \
  HOST_REPO_DIR="$REPO_DIR" \
  HOST_FLAKE_DIR="$tmp_host" \
  HOST_STATE_VERSION="26.05" \
  HOST_BOOTLOADER="systemd-boot" \
  HOST_GPU_VENDOR="amd" \
  HOST_NVIDIA_ENABLE="false" \
  HOST_GAMING="false" \
  HOST_OLLAMA="true" \
  HOST_DEV="true" \
  HOST_CONTAINERS="true" \
  HOST_CREATIVE3D="false" \
  HOST_DEV_EXTRAS="true" \
  HOST_DAILY_APPS="true" \
  HOST_ANTIGRAVITY="false" \
    generate_host_flake > "$tmp_host/flake.nix"

  eval_json="$(nix --extra-experimental-features "nix-command flakes" eval --json "path:${tmp_host}#nixosConfigurations.ci-test-host.config" --apply 'c: {
    hostname = c.networking.hostName;
    user = c.dotfiles.username;
    earlyKms = c.boot.initrd.kernelModules;
    ollamaEnable = c.services.ollama.enable;
    ollamaDrv = builtins.unsafeDiscardStringContext c.services.ollama.package.drvPath;
    firstLogin = c.systemd.user.services ? inferna-first-login;
    failedAssertions = builtins.map (x: x.message) (builtins.filter (x: !x.assertion) c.assertions);
    etcDrv = builtins.unsafeDiscardStringContext c.system.build.etc.drvPath;
  }')"
  assert_contains "generated host flake evaluates purely (etc.drv)" ".drv" "$eval_json"
  assert_contains "generated host flake resolves hostname" '"hostname":"ci-test-host"' "$eval_json"
  assert_contains "generated host flake sets amdgpu early KMS" '"amdgpu"' "$eval_json"
  assert_contains "generated host flake enables ollama" '"ollamaEnable":true' "$eval_json"
  assert_contains "generated host flake resolves ollama drv" 'ollama-' "$eval_json"
  assert_contains "generated host flake enables inferna-first-login" '"firstLogin":true' "$eval_json"
  assert_contains "generated host flake has zero failed assertions" '"failedAssertions":[]' "$eval_json"
else
  echo "  [SKIP] nix not found on PATH"
fi

printf '\nSummary: %d passed, %d failed\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
