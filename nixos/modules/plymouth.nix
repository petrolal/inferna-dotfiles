{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dotfiles.plymouth;
  gpuVendor = config.dotfiles.gpu.vendor;
  defaultKms =
    if
      lib.elem gpuVendor [
        "intel"
        "hybrid-intel-nvidia"
      ]
    then
      [ "i915" ]
    else if
      lib.elem gpuVendor [
        "amd"
        "hybrid-amd-nvidia"
      ]
    then
      [ "amdgpu" ]
    else
      [ ];

  infernaRing = pkgs.callPackage ../pkgs/inferna-ring { };
  infernaPlymouth = pkgs.callPackage ../pkgs/inferna-plymouth {
    inferna-ring = infernaRing;
  };
in
{
  options.dotfiles.plymouth = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the animated 3D Inferna ring Plymouth boot splash screen.";
    };

    earlyKmsModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultKms;
      description = "Kernel modules loaded in stage-1 initrd for flicker-free native-resolution Plymouth KMS.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = "inferna";
      themePackages = [ infernaPlymouth ];
    };

    # Load appropriate KMS module early in stage-1 so Plymouth renders immediately at native resolution
    boot.initrd.kernelModules = cfg.earlyKmsModules;

    # Silent, flicker-free graphical boot straight into the spinning 3D Inferna ring -> GDM
    boot.consoleLogLevel = 0;
    boot.kernelParams = [
      "quiet"
      "splash"
      "boot.shell_on_fail"
      "loglevel=3"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];

    # Snappier bootloader menu timeout (still enough time to pick an older generation)
    boot.loader.timeout = lib.mkDefault 2;
  };
}
