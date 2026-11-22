{ config, lib, pkgs, ... }:

let
  cfg = config.dotfiles.gdmTheme;

  # Default Inferna wallpaper bundled directly into the NixOS closure so fresh
  # installs get it immediately on first boot (no manual path setup required).
  defaultWallpaper = ../assets/wallpapers/inferna.jpeg;
  gdmCss = ../assets/gdm/gdm.css;

  # Level 2 GDM Theme: repack GNOME Shell's gnome-shell-theme.gresource with
  # the Inferna login/lock-screen CSS and pre-blurred wallpaper (matching GNOME's
  # lock screen BLUR_RADIUS=90 / BLUR_BRIGHTNESS=0.65) without recompiling GNOME Shell.
  infernaGdmThemeGresource = pkgs.runCommand "inferna-gdm-gnome-shell-theme.gresource" {
    nativeBuildInputs = [
      pkgs.glib.dev
      pkgs.imagemagick
    ];
  } ''
    orig="${pkgs.gnome-shell}/share/gnome-shell/gnome-shell-theme.gresource"
    mkdir -p work/theme

    while IFS= read -r res; do
      rel="''${res#/org/gnome/shell/theme/}"
      mkdir -p "work/theme/$(dirname "$rel")"
      gresource extract "$orig" "$res" > "work/theme/$rel"
    done < <(gresource list "$orig")

    ${if cfg.blurSigma > 0 then ''
      magick "${defaultWallpaper}" \
        -blur "0x${toString cfg.blurSigma}" \
        -evaluate Multiply "${cfg.brightness}" \
        -quality 92 \
        work/theme/inferna-gdm-wallpaper.jpeg
    '' else ''
      cp "${defaultWallpaper}" work/theme/inferna-gdm-wallpaper.jpeg
    ''}
    printf '\n' >> work/theme/gnome-shell-dark.css
    cat "${gdmCss}" >> work/theme/gnome-shell-dark.css

    {
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      echo '<gresources>'
      echo '  <gresource prefix="/org/gnome/shell/theme">'
      (cd work/theme && find . -type f | sort | sed 's|^\./||' | while IFS= read -r f; do
        printf '    <file>%s</file>\n' "$f"
      done)
      echo '  </gresource>'
      echo '</gresources>'
    } > work/gnome-shell-theme.gresource.xml

    glib-compile-resources \
      --sourcedir=work/theme \
      --target="$out" \
      work/gnome-shell-theme.gresource.xml
  '';

  # Fast runtime replacement for pkgs.gnome-shell (exact same store-path name
  # length as pkgs.gnome-shell so system.replaceDependencies works cleanly and
  # never triggers a C/Meson rebuild of GNOME Shell).
  gnomeShellWithGdmTheme = pkgs.runCommand pkgs.gnome-shell.name {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cp -a "${pkgs.gnome-shell}/." "$out"
    chmod -R u+w "$out"

    cp -f "${infernaGdmThemeGresource}" "$out/share/gnome-shell/gnome-shell-theme.gresource"

    python3 - "${pkgs.gnome-shell}" "$out" <<'PY'
import os, sys

old = sys.argv[1].encode()
new = sys.argv[2].encode()
assert len(old) == len(new), f"store path length mismatch: {len(old)} != {len(new)}"

for root, _, files in os.walk(sys.argv[2]):
    for name in files:
        path = os.path.join(root, name)
        if os.path.islink(path):
            continue
        with open(path, "rb") as f:
            data = f.read()
        if old in data:
            st = os.stat(path)
            with open(path, "wb") as f:
                f.write(data.replace(old, new))
            os.chmod(path, st.st_mode)
PY
  '';
in
{
  options.dotfiles.gdmTheme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Style the GDM login screen with Inferna dconf defaults (Level 1) and themed gresource wallpaper/CSS (Level 2).";
    };
    blurSigma = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 42;
      description = "Gaussian blur sigma applied to the GDM login wallpaper (0 disables blur; 42 matches GNOME lock screen).";
    };
    brightness = lib.mkOption {
      type = lib.types.str;
      default = "0.65";
      description = "Brightness multiplier applied to the blurred GDM login wallpaper (matches GNOME Shell's BLUR_BRIGHTNESS=0.65).";
    };
  };

  config = {
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

    # Replace stock GNOME Console (kgx) with Ghostty (native GTK4/Libadwaita +
    # OpenGL GPU rendering + Kitty Graphics Protocol for high-res 3D ring).
    environment.gnome.excludePackages = [ pkgs.gnome-console ];
    environment.etc."xdg/xdg-terminals.list".text = ''
      com.mitchellh.ghostty.desktop
    '';

    services.desktopManager.gnome.favoriteAppsOverride = ''
      [org.gnome.shell]
      favorite-apps=['com.mitchellh.ghostty.desktop', 'google-chrome.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Calendar.desktop']
    '';

    # ============================================================================
    # GDM Login Screen Theme (Level 1: dconf + Level 2: gresource CSS/wallpaper)
    # ============================================================================
    # Set `dotfiles.gdmTheme.enable = false;` to revert GDM cleanly to stock.
    programs.dconf.profiles.gdm.databases = lib.mkIf cfg.enable [
      {
        settings = {
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            accent-color = "orange";
            cursor-theme = "Bibata-Modern-Amber";
            cursor-size = lib.gvariant.mkInt32 24;
            monospace-font-name = "JetBrainsMono Nerd Font 10";
            clock-show-weekday = true;
            show-battery-percentage = true;
          };
          "org/gnome/desktop/peripherals/touchpad" = {
            tap-to-click = true;
            natural-scroll = true;
            two-finger-scrolling-enabled = true;
          };
        };
      }
    ];

    system.replaceDependencies.replacements = lib.mkIf cfg.enable [
      {
        oldDependency = pkgs.gnome-shell;
        newDependency = gnomeShellWithGdmTheme;
      }
    ];

    # ============================================================================
    # GNOME Rice Defaults (Non-Locking GSettings)
    # ============================================================================
    # extraGSettingsOverrides sets declarative schema *defaults* without locking
    # dconf: you can freely tweak anything live in GNOME Settings, GNOME Tweaks,
    # via `gsettings set ...`, or with `inferna-theme <ThemeName>`.
    # See docs/gnome-rice-guide.md for how to edit CSS, themes, and wallpapers.
    services.desktopManager.gnome.extraGSettingsOverridePackages = [
      pkgs.gsettings-desktop-schemas
      pkgs.gnome-shell
      pkgs.gnome-settings-daemon
      pkgs.mutter
    ];

    services.desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.desktop.interface]
      # Dark mode + Inferna flame accent + adw-gtk3-dark + Bibata-Modern-Amber cursor
      color-scheme='prefer-dark'
      accent-color='orange'
      gtk-theme='adw-gtk3-dark'
      cursor-theme='Bibata-Modern-Amber'
      cursor-size=24

      # Monospace Nerd Font for terminal & code views
      monospace-font-name='JetBrainsMono Nerd Font 10'

      # Small quality-of-life top bar tweaks
      clock-show-weekday=true
      show-battery-percentage=true

      # --- Additional appearance knobs (uncomment to customize defaults) ---
      # font-name='Adwaita Sans 11'
      # document-font-name='Adwaita Sans 12'
      # icon-theme='Adwaita'

      [org.gnome.desktop.default-applications.terminal]
      exec='ghostty'
      exec-arg='-e'

      [org.gnome.desktop.background]
      picture-uri='file://${defaultWallpaper}'
      picture-uri-dark='file://${defaultWallpaper}'
      picture-options='zoom'

      [org.gnome.desktop.screensaver]
      picture-uri='file://${defaultWallpaper}'

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
      # Enabled extensions (all verified for GNOME 51):
      # - AppIndicator: system tray icons (Steam, Spotify, Telegram)
      # - Clipboard Indicator: clipboard history in the top bar
      # - User Themes: loads custom ~/.themes/<Name>/gnome-shell/gnome-shell.css
      # - Space Bar: numbered workspaces in the top bar (WM-style)
      # - Revived Media Controls: track info & media controls in the top bar
      # - Caffeine: inhibit sleep/screensaver (with fullscreen auto-mode)
      # - Vitals: CPU, RAM, temperature & network telemetry in the top bar
      # - Rounded Window Corners Reborn: uniform rounded corners for Electron/XWayland
      # - Blur my Shell: blur for top bar, overview, menus & lock screen
      # - GameMode Shell Extension: top bar indicator for programs.gamemode
      # - Transparent Move: semi-transparent windows while dragging
      enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'clipboard-indicator@tudmotu.com', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'space-bar@luchrioh', 'mediacontrols@GitPowerInc.github.com', 'caffeine@patapon.info', 'Vitals@CoreCoding.com', 'rounded-window-corners@fxgn', 'blur-my-shell@aunetx', 'gamemodeshellextension@trsnaqe.com', 'transparent-move@edjenn1998']
    '';

    # Run Chromium/Chrome/Electron natively on Wayland, unify Qt6 apps with the
    # Inferna palette (qt6ct), and export Bibata-Modern-Amber for XWayland/apps.
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      QT_QPA_PLATFORMTHEME = "qt6ct";
      XCURSOR_THEME = "Bibata-Modern-Amber";
      XCURSOR_SIZE = "24";
    };

    # Essential GNOME utilities, GTK3/Qt6/cursor theming, and Shell extensions.
    environment.systemPackages = with pkgs; [
      ghostty                  # GPU-accelerated GTK4/Libadwaita terminal (Kitty Graphics Protocol)
      file-roller              # Native GNOME archive manager
      gnome-tweaks             # Fonts, window buttons, startup apps, appearance
      gnome-extension-manager  # Browse/enable/configure GNOME Shell extensions
      dconf-editor             # Inspect & experiment with GSettings/dconf keys
      adw-gtk3                 # GTK3 port of Libadwaita (pairs with gtk-3.0/gtk.css)
      bibata-cursors           # Bibata-Modern-Amber ember cursor for GNOME & GDM
      kdePackages.qt6ct        # Warm Inferna dark palette for Qt6 apps (Qt Creator, Shotcut, MeshLab)

      # Enabled GNOME Shell extensions (GNOME 51 compatible)
      gnomeExtensions.appindicator
      gnomeExtensions.clipboard-indicator
      gnomeExtensions.user-themes
      gnomeExtensions.space-bar
      gnomeExtensions.revived-media-controls
      gnomeExtensions.caffeine
      gnomeExtensions.vitals
      gnomeExtensions.rounded-window-corners-reborn
      gnomeExtensions.blur-my-shell
      gnomeExtensions.gamemode-shell-extension
      gnomeExtensions.transparent-move

      # --- Optional visual/layout extensions (uncomment when ready) ---
      # gnomeExtensions.dash-to-dock       # UUID: dash-to-dock@micxgx.gmail.com
      # gnomeExtensions.just-perfection    # UUID: just-perfection-desktop@just-perfection
      # gnomeExtensions.dynamic-music-pill # UUID: dynamic-music-pill@andbal (visualizer pill alternative to revived-media-controls)
    ];
  };
}
