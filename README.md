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
  - Custom `Inferna` Shell/GTK4/GTK3 theme, `Bibata-Modern-Amber` cursor across GNOME & GDM, custom native **`ai-telemetry@inferna`** top-bar widget (Claude Code, Antigravity & Ollama quotas), and 8 verified lightweight GNOME 51 extensions (`space-bar`, `revived-media-controls`, `caffeine`, `vitals`, `rounded-window-corners-reborn`, lightweight `blur-my-shell`, `gamemode-shell-extension`, `transparent-move`).
  - Helpers: `inferna-theme <ThemeName|--list|--reset>` and `inferna-extensions <save|load>`.
- **Terminal & TUI Suite ([`ghostty/`](ghostty/), [`fish/`](fish/), [`starship/`](starship/), [`fastfetch/`](fastfetch/)):**
  - **Ghostty** (`Ctrl + Alt + T`) + **Fish** (with preserved `~/.config/fish/user-fish.fish` local overrides) + **Starship** prompt.
  - Full Inferna TUI kit: **`btop`** (with GPU telemetry), **`yazi`** (`y` wrapper with Kitty image previews), **`cava`** (6-stop hellfire audio visualizer), **`eza`**, **`bat`**, **`zoxide`**, and **`fzf`**.
- **Multi-Machine Portable NixOS Flake ([`nixos/modules/`](nixos/modules/), [`bootstrap.sh`](bootstrap.sh)):**
  - Auto-detects Intel, AMD, dedicated NVIDIA, Intel/AMD + NVIDIA PRIME offload (PCI bus IDs), VMs, and UEFI (`systemd-boot`) vs BIOS (`grub`).
  - Generates a **100% pure** `/etc/nixos/flake.nix` per machine (no `--impure` needed, keeps `~/inferna-dotfiles` clean for `git pull`).
  - Automatic first-login GNOME setup (`inferna-first-login` user service) applies themes, `dconf` extensions, and keybindings on first graphical login after reboot.

## Quick Install on Any Fresh NixOS Machine

From a freshly installed NixOS machine (logged in as your regular user with `sudo`):

```bash
curl -fsSL https://raw.githubusercontent.com/petrolal/inferna-dotfiles/main/bootstrap.sh | bash
```

What the bootstrapper does automatically:
1. Clones `~/inferna-dotfiles` (automatically fetches `git` via `nix` if not installed yet).
2. Detects your hostname, user, UEFI/BIOS bootloader, GPU topology (Intel / AMD / NVIDIA / PRIME bus IDs / VM), timezone, keymap, and `system.stateVersion`.
3. Lets you pick a profile:
   - **`full`** *(default)* — Complete workstation (GNOME 51 rice + Dev + Docker + Gaming + 3D/Image suite + Ollama)
   - **`dev`** — Developer desktop (GNOME 51 rice + Dev + Docker + Daily apps)
   - **`minimal`** — Pure Inferna rice only (GNOME 51, Plymouth, GDM, Ghostty, Fish, TUI suite, Firefox)
4. Backs up `/etc/nixos`, writes a pure `/etc/nixos/flake.nix` pointing to your local `hardware-configuration.nix`, runs `nixos-rebuild switch`, and deploys dotfiles.
5. After you **reboot** and log into GNOME, `inferna-first-login` automatically finishes applying the GNOME Shell theme, `extensions.dconf`, and `Ctrl+Alt+T` shortcut.

### Non-Interactive & Dry-Run Examples

```bash
# Preview detected hardware and generated /etc/nixos/flake.nix without touching the system
curl -fsSL https://raw.githubusercontent.com/petrolal/inferna-dotfiles/main/bootstrap.sh | bash -s -- --dry-run

# Unattended full workstation install
curl -fsSL https://raw.githubusercontent.com/petrolal/inferna-dotfiles/main/bootstrap.sh | bash -s -- --yes --profile full

# Unattended minimal rice install (great for laptops/VMs)
curl -fsSL https://raw.githubusercontent.com/petrolal/inferna-dotfiles/main/bootstrap.sh | bash -s -- --yes --profile minimal
```

### Manual Dotfiles-Only Redeploy

```bash
cd ~/inferna-dotfiles
./install.sh
```

Replaced files are backed up to `~/.config/inferna-dotfiles-backup/<time>/`. Personal Fish overrides in `~/.config/fish/user-fish.fish` are always preserved.

## Useful Commands

| Command | Description |
| --- | --- |
| `inferna-rebuild` | Update local `/etc/nixos` flake lock and switch with `nh os switch` |
| `inferna-theme Inferna` | Apply / live-reload the Inferna GNOME, GTK & cursor theme |
| `inferna-extensions save` | Snapshot current GNOME extension dconf settings to the repo |
| `ring3d` | Interactive high-resolution live 3D GLSL Inferna ring in Ghostty |
| `dash` | Full `fastfetch` system dashboard |
| `btop` / `y` / `cava` | Inferna resource monitor, Yazi file manager, and hellfire audio visualizer |
| `nh os switch` | Rebuild & switch NixOS with pretty diffs |

## Docs

- [Como funciona o rice no GNOME + NixOS](docs/gnome-rice-guide.md)

## License

GNU General Public License v3.0 (GPL-3.0-or-later). See [LICENSE](LICENSE).
