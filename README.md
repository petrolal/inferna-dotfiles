<div align="center">

<h1>inferna-dotfiles</h1>

<p><strong>Pure GNOME on NixOS — Declarative Flake & Minimal Rice.</strong><br>
A clean, stock-Adwaita GNOME workstation on NixOS with hardware/NVIDIA/gaming/dev modules and a standalone fastfetch dashboard.</p>

<p>
<img alt="NixOS" src="https://img.shields.io/badge/NixOS-unstable-5277C3?style=flat-square&logo=nixos&logoColor=white">
<img alt="GNOME" src="https://img.shields.io/badge/GNOME-Wayland-4A86CF?style=flat-square&logo=gnome&logoColor=white">
<a href="LICENSE"><img alt="GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square"></a>
</p>

</div>

## What's Included

- **Pure GNOME + GDM ([`nixos/modules/gnome.nix`](nixos/modules/gnome.nix)):**
  - Complete default GNOME app suite (Nautilus, GNOME Console, Loupe, Papers, Showtime, Calculator, Text Editor, Calendar, Clocks, Weather, System Monitor, Disks, File Roller).
  - Essential customization tools (`gnome-tweaks`, `gnome-extension-manager`, `dconf-editor`), `adw-gtk3`, and extensions (`appindicator`, `clipboard-indicator`, `user-themes`).
  - Non-locking GSettings defaults (dark mode, flame orange accent, bundled default wallpaper in `nixos/assets/wallpapers/inferna.jpeg`, Nerd Font monospace, window buttons, clock weekday, battery percentage, touchpad gestures, centered windows).
- **Editable GNOME Theme Base ([`gnome/`](gnome/)):** Ready-to-hack `Inferna` theme (`gtk-4.0/gtk.css`, `gtk-3.0/gtk.css`, `gnome-shell/gnome-shell.css`, `theme.env`) plus `inferna-theme` helper to apply, live-reload, switch, or reset themes.
- **Workstation Modules ([`nixos/modules/`](nixos/modules/)):** Graphics acceleration (OpenGL/Vulkan + 32-bit + Intel VA-API), NVIDIA PRIME offload, PipeWire audio, gaming (Steam, Lutris, Heroic, RetroArch, TETR.IO), dev/IDEs (Neovim, Emacs, VS Code), Docker/Kubernetes, Ollama CUDA, and per-project Nix devshells via `direnv`.
- **Standalone fastfetch Dashboard ([`fastfetch/`](fastfetch/)):** Live hardware, telemetry, GNOME desktop, and network cards.

## Install on NixOS

### 1. Apply NixOS System Configuration

```bash
cd ~/inferna-dotfiles/nixos
sudo nixos-rebuild switch --flake .#default
```

### 2. Deploy User Dotfiles (`fastfetch`, `fish`, `gnome`)

```bash
cd ~/inferna-dotfiles
./install.sh
```

Existing files are backed up to `~/.config/inferna-dotfiles-backup/<time>/`, and obsolete Hyprland/core symlinks in `~/.local/` are cleaned up automatically.

## Docs

- [Como funciona o rice no GNOME + NixOS](docs/gnome-rice-guide.md)
- [Plano e registro de limpeza da migração](docs/gnome-migration-cleanup.md)

## License

GNU General Public License v3.0 (GPL-3.0-or-later). See [LICENSE](LICENSE).
