# Hyprland is now the only session: XFCE/X11/LightDM (desktop.nix) have been
# removed outright (see docs/migration_plan.md section 0A). greetd + tuigreet
# replaces LightDM as a minimal, Wayland-native login manager with no GTK
# theme/greeter dependency.
{ config, lib, pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true; # some apps are still X11-only and need Xwayland
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      # `start-hyprland` (not the bare `Hyprland` binary) is Hyprland's own
      # uwsm-integration entrypoint: it registers the session as a proper
      # systemd user unit, which is what gives a crashing/closing session a
      # clean handoff back to the greeter instead of leaving the VT in a
      # half-torn-down state. Previously this was "Hyprland", which tuigreet
      # happened to resolve to the same session via its wayland-sessions
      # desktop-file matching -- spelling it out removes that indirection.
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
      user = "greeter";
    };
  };

  xdg.portal = {
    enable = true;
    # xdg-desktop-portal-hyprland doesn't implement org.freedesktop.portal.
    # Settings (color-scheme/gtk-theme), so apps asking the portal whether to
    # render dark (Chrome, GTK4 apps) got no answer and fell back to light
    # even with gtk-application-prefer-dark-theme set. xdg-desktop-portal-gtk
    # backs that interface by reading the GTK/dconf settings directly.
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "hyprland" "gtk" ];
  };


  security.polkit.enable = true;

  # Hyprland has no polkit agent of its own, so run the Hyprland-maintained
  # one for its sessions.
  systemd.user.services.hyprpolkitagent = {
    description = "Hyprland polkit authentication agent";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
      Restart = "on-failure";
    };
  };

  # Required for any Wayland compositor.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libvdpau-va-gl
    ];
  };

  # NVIDIA modesetting kernel parameters when discrete GPU is enabled
  boot.kernelParams = lib.mkIf config.dotfiles.nvidia.enable [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
  ];

  environment.sessionVariables = {
    # Tell Chromium/Chrome/Electron to use native Wayland
    NIXOS_OZONE_WL = "1";

    # QML2_IMPORT_PATH ensures Quickshell / QML finds QtQuick3D, Quickshell, and Inferna shell modules
    QML2_IMPORT_PATH = (lib.makeSearchPath "lib/qt-6/qml" [
      pkgs.qt6.qtquick3d
      pkgs.quickshell
    ]) + ":/home/petrolal/inferna-dotfiles/core/shell";
  };

  environment.systemPackages = with pkgs; [
    # Hyprland session daemons
    hyprpaper
    hyprlock
    hypridle

    # Cursor theme
    vanilla-dmz

    # Inferna Pebble Shell (Quickshell Qt6 ecosystem)
    quickshell
    qt6.qtquick3d
    qt6.qtshadertools
    ffmpeg
    libnotify

    # Wayland runtime/client libraries
    wayland
    libxkbcommon
  ];
}
