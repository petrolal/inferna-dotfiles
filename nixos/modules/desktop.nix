{
  config,
  lib,
  ...
}:

let
  cfg = config.dotfiles;
in
{
  options.dotfiles = {
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "America/Sao_Paulo";
      description = "System timezone.";
    };

    defaultLocale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
      description = "Default system locale (UI language).";
    };

    extraLocale = lib.mkOption {
      type = lib.types.str;
      default = "pt_BR.UTF-8";
      description = "Regional locale for dates, currency, numbers, and measurements.";
    };

    consoleKeyMap = lib.mkOption {
      type = lib.types.str;
      default = "us-acentos";
      description = "Virtual console keyboard layout.";
    };

    screenRecorder.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.dotfiles.gpu.vendor != "vm";
      description = "Enable gpu-screen-recorder (ShadowPlay-style hardware screen capture).";
    };
  };

  config = {
    # Time & Locale
    time.timeZone = lib.mkDefault cfg.timeZone;
    i18n.defaultLocale = lib.mkDefault cfg.defaultLocale;
    i18n.extraLocaleSettings = {
      LC_ADDRESS = lib.mkDefault cfg.extraLocale;
      LC_IDENTIFICATION = lib.mkDefault cfg.extraLocale;
      LC_MEASUREMENT = lib.mkDefault cfg.extraLocale;
      LC_MONETARY = lib.mkDefault cfg.extraLocale;
      LC_NAME = lib.mkDefault cfg.extraLocale;
      LC_NUMERIC = lib.mkDefault cfg.extraLocale;
      LC_PAPER = lib.mkDefault cfg.extraLocale;
      LC_TELEPHONE = lib.mkDefault cfg.extraLocale;
      LC_TIME = lib.mkDefault cfg.extraLocale;
    };

    console.keyMap = lib.mkDefault cfg.consoleKeyMap;

    # Pipewire Sound
    services.printing.enable = true;
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Portal and dconf management
    programs.dconf.enable = true;

    # Hardware-accelerated screen recorder (ShadowPlay-style instant replay & capture)
    programs.gpu-screen-recorder = lib.mkIf cfg.screenRecorder.enable {
      enable = true;
      ui.enable = true;
    };

    # Expose ~/.local/bin (e.g. inferna-theme, inferna-extensions) across all shells & GUI sessions
    environment.localBinInPath = true;

    # Dotfiles repository location
    environment.sessionVariables = {
      INFERNA_DOTFILES = cfg.repoPath;
    };
  };
}
