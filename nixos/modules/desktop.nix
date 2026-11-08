{ config, pkgs, ... }:

{
  # Time & Locale
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_BR.UTF-8";
    LC_IDENTIFICATION = "pt_BR.UTF-8";
    LC_MEASUREMENT = "pt_BR.UTF-8";
    LC_MONETARY = "pt_BR.UTF-8";
    LC_NAME = "pt_BR.UTF-8";
    LC_NUMERIC = "pt_BR.UTF-8";
    LC_PAPER = "pt_BR.UTF-8";
    LC_TELEPHONE = "pt_BR.UTF-8";
    LC_TIME = "pt_BR.UTF-8";
  };

  console.keyMap = "us-acentos";

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

  # Bluetooth manager with tray applet (consumed by Inferna shell tray widget)
  services.blueman.enable = true;

  # Hardware-accelerated screen recorder (ShadowPlay-style instant replay & capture)
  programs.gpu-screen-recorder = {
    enable = true;
    ui.enable = true;
  };

  # Inferna environment variables
  environment.sessionVariables = {
    INFERNA_PATH = "/home/petrolal/inferna-dotfiles/core";
    INFERNA_DOTFILES = "/home/petrolal/inferna-dotfiles";

    # nixpkgs nests each package's gsettings schemas under its own
    # share/gsettings-schemas/<name>/ subdir (to avoid collisions when several
    # schema providers are installed), so plain systemPackages membership
    # alone never puts them on XDG_DATA_DIRS the way a normal
    # share/glib-2.0/schemas tree would. NixOS merges every module's
    # sessionVariables into one list (see /etc/set-environment), so this adds
    # to the existing dirs rather than replacing them. Without this, gsettings
    # (and every GTK3/4 app reading it -- Thunar included) can't find
    # org.gnome.desktop.interface at all and silently renders unthemed.
    XDG_DATA_DIRS = [
      "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
      "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
    ];
  };
}