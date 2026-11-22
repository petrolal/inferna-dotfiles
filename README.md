<div align="center">

<h1>inferna-dotfiles</h1>

<p><strong>Inferna GNOME 51 on NixOS — Declarative Flake, Real-Time 3D GLSL Ring & Unified Ember Rice.</strong><br>
A cohesive obsidian, forged-iron, ember-orange, and molten-gold NixOS workstation — from the animated 3D Plymouth boot splash and blurred GDM login screen to Ghostty, Fish, Starship, TUI tools, Qt6, and MangoHud.</p>

<p>
<img alt="NixOS" src="https://img.shields.io/badge/NixOS-unstable-d9381e?style=flat-square&logo=nixos&logoColor=white">
<img alt="GNOME" src="https://img.shields.io/badge/GNOME_51-Wayland-ff622e?style=flat-square&logo=gnome&logoColor=white">
<img alt="Ghostty" src="https://img.shields.io/badge/Ghostty-Kitty_Graphics-f2a949?style=flat-square">
<a href="LICENSE"><img alt="GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-8a160c?style=flat-square"></a>
</p>

</div>

## Highlights

- **Real-Time 3D GLSL Inferna Ring ([`nixos/pkgs/inferna-ring/`](nixos/pkgs/inferna-ring/)):**
  - Custom OpenGL ES 3.0 / EGL raymarched 3D forged-iron barbed hexagram ring with floating burnt-copper Elder Futhark runes, photographic domain-warped hellfire, and rising ember sparks.
  - Streams natively in Ghostty via Kitty Graphics Protocol (`--kitty-loop`, 240 frames @ 33 FPS, disk-cached ~25 ms startup) alongside a gradient fire-bar `fastfetch` panel — zero prompt blocking.
  - Run `ring3d` anytime for a live interactive high-res 3D spin.
- **Animated 3D Plymouth Boot Splash ([`nixos/modules/plymouth.nix`](nixos/modules/plymouth.nix), [`nixos/pkgs/inferna-plymouth/`](nixos/pkgs/inferna-plymouth/)):**
  - Declaratively renders 72 seamless 360° frames of the exact same `ring.frag` shader during `nixos-rebuild` (no binary PNG bloat in git), with an ember gradient progress bar and silent KMS boot straight into GDM.
- **GNOME 51 + Blurred GDM Login Theme ([`nixos/modules/gnome.nix`](nixos/modules/gnome.nix), [`gnome/`](gnome/)):**
  - Pre-blurred Inferna GDM login/lock screen via fast `gnome-shell-theme.gresource` replacement (no GNOME Shell recompile).
  - Custom `Inferna` Shell/GTK4/GTK3 theme, `Bibata-Modern-Amber` cursor across GNOME & GDM, and 8 verified lightweight GNOME 51 extensions (`space-bar`, `revived-media-controls`, `caffeine`, `vitals`, `rounded-window-corners-reborn`, lightweight `blur-my-shell`, `gamemode-shell-extension`, `transparent-move`).
  - Helpers: `inferna-theme <ThemeName|--list|--reset>` and `inferna-extensions <save|load>`.
- **Terminal & TUI Suite ([`ghostty/`](ghostty/), [`fish/`](fish/), [`starship/`](starship/), [`fastfetch/`](fastfetch/)):**
  - **Ghostty** (`Ctrl + Alt + T`) + **Fish** (with preserved `~/.config/fish/user-fish.fish` local overrides) + **Starship** prompt.
  - Full Inferna TUI kit: **`btop`** (with GPU telemetry), **`yazi`** (`y` wrapper with Kitty image previews), **`cava`** (6-stop hellfire audio visualizer), **`eza`**, **`bat`**, **`zoxide`**, and **`fzf`**.
- **Apps, Gaming & Performance ([`nixos/modules/`](nixos/modules/)):**
  - **MangoHud** Inferna overlay ([`mangohud/MangoHud.conf`](mangohud/MangoHud.conf)), **Qt6** warm Inferna palette ([`qt6ct/`](qt6ct/)), NVIDIA PRIME offload, GameMode, Steam/Lutris/Heroic/RetroArch/TETR.IO, and `nix-ld` Electron runtime libs.
  - Tuned for responsiveness: `zramSwap`, `thermald`, `earlyoom`, `fstrim`, `nh` automatic GC, `auto-optimise-store`, socket-activated Docker, and on-demand Ollama (`sudo systemctl start ollama`).

## Install on NixOS

### 1. Apply NixOS System Configuration

```bash
sudo nixos-rebuild switch --flake ~/inferna-dotfiles/nixos#default
```

### 2. Deploy User Dotfiles

```bash
cd ~/inferna-dotfiles
./install.sh
```

Replaced files are backed up to `~/.config/inferna-dotfiles-backup/<time>/`. Personal Fish overrides in `~/.config/fish/user-fish.fish` are always preserved.

## Useful Commands

| Command | Description |
| --- | --- |
| `inferna-theme Inferna` | Apply / live-reload the Inferna GNOME, GTK & cursor theme |
| `inferna-extensions save` | Snapshot current GNOME extension dconf settings to the repo |
| `ring3d` | Interactive high-resolution live 3D GLSL Inferna ring in Ghostty |
| `dash` | Full `fastfetch` system dashboard |
| `btop` / `y` / `cava` | Inferna resource monitor, Yazi file manager, and hellfire audio visualizer |
| `nh os switch` | Rebuild & switch NixOS with pretty diffs |

## Docs

- [Como funciona o rice no GNOME + NixOS](docs/gnome-rice-guide.md)
- [Plano e registro de limpeza da migração](docs/gnome-migration-cleanup.md)

## License

GNU General Public License v3.0 (GPL-3.0-or-later). See [LICENSE](LICENSE).
