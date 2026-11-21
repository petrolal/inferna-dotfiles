{ pkgs, ... }:

{
  # ============================================================================
  # GNOME Desktop & GDM (NixOS)
  # ============================================================================
  # Enabling desktopManager.gnome ships the complete standard GNOME app suite:
  # Nautilus (Files), GNOME Console (kgx), Loupe (Image Viewer), Papers (PDF),
  # Showtime (Video), Calculator, Text Editor, Calendar, Clocks, Weather,
  # System Monitor, Disks, Characters, Font Viewer, Baobab, Snapshot, Decibels,
  # and Extensions, plus xdg-desktop-portal-gnome, gnome-keyring, and IBus.
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;

  # ============================================================================
  # Minimal GNOME Rice (Default Adwaita Theme Preserved)
  # ============================================================================
  # extraGSettingsOverrides sets declarative schema *defaults* without locking
  # dconf: you can freely tweak anything live in GNOME Settings, GNOME Tweaks,
  # or via `gsettings set ...`. See docs/gnome-rice-guide.md for how to explore
  # keys with `dconf watch /` and move your favorite tweaks back here.
  services.desktopManager.gnome.extraGSettingsOverridePackages = [
    pkgs.gsettings-desktop-schemas
    pkgs.gnome-shell
    pkgs.gnome-settings-daemon
    pkgs.mutter
  ];

  services.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.desktop.interface]
    # Monospace Nerd Font for GNOME Console & code views
    monospace-font-name='JetBrainsMono Nerd Font 10'

    # Small quality-of-life top bar tweaks
    clock-show-weekday=true
    show-battery-percentage=true

    # --- Theme & appearance examples (commented to keep stock GNOME default) ---
    # color-scheme='prefer-dark'          # 'default' | 'prefer-dark' | 'prefer-light'
    # accent-color='red'                  # 'blue' | 'teal' | 'green' | 'yellow' | 'orange' | 'red' | 'pink' | 'purple' | 'slate'
    # font-name='Adwaita Sans 11'
    # document-font-name='Adwaita Sans 12'
    # icon-theme='Adwaita'
    # cursor-theme='Adwaita'

    [org.gnome.desktop.wm.preferences]
    # Add minimize and maximize buttons to window titlebars
    button-layout='appmenu:minimize,maximize,close'

    [org.gnome.mutter]
    # Ergonomic window placement and workspaces
    center-new-windows=true
    dynamic-workspaces=true
    edge-tiling=true

    [org.gnome.desktop.peripherals.touchpad]
    tap-to-click=true
    natural-scroll=true
    two-finger-scrolling-enabled=true

    [org.gnome.shell]
    # Only functional extensions enabled by default (visual theme untouched):
    # - AppIndicator: system tray icons (Steam, Spotify, Telegram)
    # - Clipboard Indicator: clipboard history in the top bar
    enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'clipboard-indicator@tudmotu.com']
  '';

  # Run Chromium/Chrome/Electron apps natively on Wayland under GNOME.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # Essential GNOME utilities and minimal functional extensions.
  environment.systemPackages = with pkgs; [
    file-roller              # Native GNOME archive manager
    gnome-tweaks             # Fonts, window buttons, startup apps, appearance
    gnome-extension-manager  # Browse/enable/configure GNOME Shell extensions
    dconf-editor             # Inspect & experiment with GSettings/dconf keys

    # Minimal utility extensions (do not alter the default GNOME theme)
    gnomeExtensions.appindicator
    gnomeExtensions.clipboard-indicator

    # --- Optional visual extensions (uncomment when ready to customize look) ---
    # gnomeExtensions.blur-my-shell   # UUID: blur-my-shell@aunetx
    # gnomeExtensions.dash-to-dock    # UUID: dash-to-dock@micxgx.gmail.com
    # gnomeExtensions.user-themes     # UUID: user-theme@gnome-shell-extensions.gcampax.github.com
  ];
}
