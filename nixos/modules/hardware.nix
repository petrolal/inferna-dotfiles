{
  config,
  pkgs,
  lib,
  ...
}:

let
  gpuVendor = config.dotfiles.gpu.vendor;
  isIntel = lib.elem gpuVendor [
    "intel"
    "hybrid-intel-nvidia"
  ];
  bootloader = config.dotfiles.bootloader;

  infernaRebuild = pkgs.writeShellScriptBin "inferna-rebuild" ''
    set -euo pipefail
    flake_path="${config.dotfiles.flakePath}"
    if [[ -f "$flake_path/flake.nix" ]] && grep -q 'inferna' "$flake_path/flake.nix"; then
      echo "Updating local inferna flake input lock in $flake_path..."
      sudo nix flake update inferna --flake "$flake_path"
    fi
    exec nh os switch "$flake_path" "$@"
  '';
in
{
  options.dotfiles = {
    bootloader = lib.mkOption {
      type = lib.types.enum [
        "systemd-boot"
        "grub"
        "none"
      ];
      default = "systemd-boot";
      description = "Bootloader managed by Inferna (systemd-boot for UEFI, grub for BIOS, none for custom/VM).";
    };

    grubDevice = lib.mkOption {
      type = lib.types.str;
      default = "nodev";
      description = "GRUB target device when dotfiles.bootloader = \"grub\" (e.g. /dev/sda or nodev).";
    };

    gpu.vendor = lib.mkOption {
      type = lib.types.enum [
        "intel"
        "amd"
        "nvidia"
        "hybrid-intel-nvidia"
        "hybrid-amd-nvidia"
        "vm"
        "generic"
      ];
      default = "generic";
      description = "Primary GPU topology detected for this machine.";
    };

    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "Flake directory used by `nh os switch` and `inferna-rebuild`.";
    };
  };

  config = {
    # Bootloader (UEFI systemd-boot by default, BIOS GRUB fallback, or disabled)
    boot.loader = lib.mkMerge [
      (lib.mkIf (bootloader == "systemd-boot") {
        systemd-boot = {
          enable = lib.mkDefault true;
          configurationLimit = lib.mkDefault 5;
        };
        efi.canTouchEfiVariables = lib.mkDefault true;
      })
      (lib.mkIf (bootloader == "grub") {
        grub = {
          enable = lib.mkDefault true;
          device = lib.mkDefault config.dotfiles.grubDevice;
          configurationLimit = lib.mkDefault 5;
        };
      })
    ];

    # Firmware
    hardware.enableRedistributableFirmware = true;
    hardware.enableAllFirmware = true;
    nixpkgs.config.allowUnfree = true;

    # Device firmware updates (fwupdmgr)
    services.fwupd.enable = lib.mkIf (gpuVendor != "vm") (lib.mkDefault true);

    # WebHID / QMK / VIA keyboard configurators (e.g. qmk.top, usevia.app)
    services.udev.extraRules = ''
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666", TAG+="uaccess", TAG+="udev-acl"
    '';
    hardware.keyboard.qmk.enable = true;

    # Graphics acceleration (OpenGL/Vulkan, 32-bit for gaming, Intel VA-API when present)
    hardware.graphics = {
      enable = true;
      enable32Bit = lib.mkDefault true;
      extraPackages = lib.optionals isIntel (
        with pkgs;
        [
          intel-media-driver
          libvdpau-va-gl
        ]
      );
    };

    # Bluetooth (GNOME enables hardware.bluetooth.enable with mkDefault true;
    # avoid a mkDefault conflict on VMs by only disabling powerOnBoot there).
    hardware.bluetooth = {
      enable = lib.mkDefault true;
      powerOnBoot = lib.mkDefault (gpuVendor != "vm");
    };

    # Performance, thermal & storage health
    zramSwap.enable = true;
    services.fstrim.enable = true;
    services.thermald.enable = lib.mkDefault isIntel;
    services.earlyoom = {
      enable = true;
      freeMemThreshold = 5;
    };

    # Nix store optimization + nh (prettier rebuilds/diffs & weekly GC)
    nix.settings.auto-optimise-store = true;
    programs.nh = {
      enable = true;
      flake = config.dotfiles.flakePath;
      clean = {
        enable = true;
        extraArgs = "--keep-since 14d --keep 5";
      };
    };

    environment.systemPackages = [ infernaRebuild ];
  };
}
