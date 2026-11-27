# NVIDIA graphics support (dedicated single-GPU or Intel/AMD + NVIDIA PRIME
# offload). Opt-in per host so the shared Inferna profile stays portable across
# Intel-only, AMD-only, NVIDIA desktop, hybrid laptop, and VM hosts.
{
  config,
  lib,
  ...
}:

let
  cfg = config.dotfiles.nvidia;
in
{
  options.dotfiles.nvidia = {
    enable = lib.mkEnableOption "NVIDIA proprietary/open graphics driver";

    open = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use the open-source NVIDIA kernel module (Turing/RTX 20xx+ recommended; set false for Pascal/Maxwell).";
    };

    cudaCapabilities = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Optional CUDA compute capability filter (e.g. [ \"8.9\" ] for RTX 4050) to speed up local CUDA builds.";
    };

    prime = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.prime.intelBusId != null || cfg.prime.amdgpuBusId != null;
        description = "Enable NVIDIA PRIME render offload (automatically enabled when intelBusId or amdgpuBusId is set).";
      };
      intelBusId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PCI bus ID of the integrated Intel GPU (e.g. PCI:0:2:0).";
      };
      amdgpuBusId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PCI bus ID of the integrated AMD GPU (e.g. PCI:5:0:0).";
      };
      nvidiaBusId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PCI bus ID of the discrete NVIDIA GPU (e.g. PCI:1:0:0).";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.cudaCapabilities != [ ]) {
      nixpkgs.config.cudaCapabilities = cfg.cudaCapabilities;
    })

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion =
            !cfg.prime.enable
            || (
              cfg.prime.nvidiaBusId != null
              && (cfg.prime.intelBusId != null || cfg.prime.amdgpuBusId != null)
            );
          message = "dotfiles.nvidia.prime.enable requires dotfiles.nvidia.prime.nvidiaBusId and either intelBusId or amdgpuBusId.";
        }
      ];

      # hardware.graphics.enable/enable32Bit is declared in hardware.nix.
      boot.kernelParams = [
        "nvidia_drm.modeset=1"
        "nvidia_drm.fbdev=1"
      ];

      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        powerManagement.finegrained = cfg.prime.enable;
        open = cfg.open;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;

        prime = lib.mkIf cfg.prime.enable (
          {
            offload = {
              enable = true;
              enableOffloadCmd = true;
            };
            inherit (cfg.prime) nvidiaBusId;
          }
          // lib.optionalAttrs (cfg.prime.intelBusId != null) {
            inherit (cfg.prime) intelBusId;
          }
          // lib.optionalAttrs (cfg.prime.amdgpuBusId != null) {
            inherit (cfg.prime) amdgpuBusId;
          }
        );
      };
    })
  ];
}
