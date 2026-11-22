{ config, lib, pkgs, ... }:

let
  cfg = config.dotfiles.gdmTheme;

  # Default Inferna wallpaper bundled directly into the NixOS closure so fresh
  # installs get it immediately on first boot (no manual path setup required).
  defaultWallpaper = ../assets/wallpapers/inferna.jpeg;
  gdmCss = ../assets/gdm/gdm.css;

  # Level 2 GDM Theme: repack GNOME Shell's gnome-shell-theme.gresource with
  # the Inferna login/lock-screen CSS and wallpaper without recompiling GNOME Shell.
  infernaGdmThemeGresource = pkgs.runCommand "inferna-gdm-gnome-shell-theme.gresource" {
    nativeBuildInputs = [ pkgs.glib.dev ];
  } ''
    orig="${pkgs.gnome-shell}/share/gnome-shell/gnome-shell-theme.gresource"
    mkdir -p work/theme

    while IFS= read -r res; do
      rel="''${res#/org/gnome/shell/theme/}"
      mkdir -p "work/theme/$(dirname "$rel")"
      gresource extract "$orig" "$res" > "work/theme/$rel"
    done < <(gresource list "$orig")

    cp "${defaultWallpaper}" work/theme/inferna-gdm-wallpaper.jpeg
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
  options.dotfiles.gdmTheme.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Style the GDM login screen with Inferna dconf defaults (Level 1) and themed gresource wallpaper/CSS (Level 2).";
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
      # Dark mode + Inferna flame accent + adw-gtk3-dark so GTK3 apps match Libadwaita
      color-scheme='prefer-dark'
      accent-color='orange'
      gtk-theme='adw-gtk3-dark'

      # Monospace Nerd Font for GNOME Console & code views
      monospace-font-name='JetBrainsMono Nerd Font 10'

      # Small quality-of-life top bar tweaks
      clock-show-weekday=true
      show-battery-percentage=true

      # --- Additional appearance knobs (uncomment to customize defaults) ---
      # font-name='Adwaita Sans 11'
      # document-font-name='Adwaita Sans 12'
      # icon-theme='Adwaita'
      # cursor-theme='Adwaita'

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
      # Enabled extensions:
      # - AppIndicator: system tray icons (Steam, Spotify, Telegram)
      # - Clipboard Indicator: clipboard history in the top bar
      # - User Themes: loads custom ~/.themes/<Name>/gnome-shell/gnome-shell.css
      enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'clipboard-indicator@tudmotu.com', 'user-theme@gnome-shell-extensions.gcampax.github.com']
    '';

    # Run Chromium/Chrome/Electron apps natively on Wayland under GNOME.
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };

    # Essential GNOME utilities, GTK3 Libadwaita theme, and Shell extensions.
    environment.systemPackages = with pkgs; [
      file-roller              # Native GNOME archive manager
      gnome-tweaks             # Fonts, window buttons, startup apps, appearance
      gnome-extension-manager  # Browse/enable/configure GNOME Shell extensions
      dconf-editor             # Inspect & experiment with GSettings/dconf keys
      adw-gtk3                 # GTK3 port of Libadwaita (pairs with gtk-3.0/gtk.css)

      # Enabled GNOME Shell extensions
      gnomeExtensions.appindicator
      gnomeExtensions.clipboard-indicator
      gnomeExtensions.user-themes

      # --- Optional visual/layout extensions (uncomment when ready) ---
      # gnomeExtensions.blur-my-shell   # UUID: blur-my-shell@aunetx
      # gnomeExtensions.dash-to-dock    # UUID: dash-to-dock@micxgx.gmail.com
      # gnomeExtensions.just-perfection # UUID: just-perfection-desktop@just-perfection
    ];
  };
}
