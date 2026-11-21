# Limpeza e Migração para GNOME Puro (`refactor/gnome`)

Registro completo do expurgo de resíduos do **Hyprland**, **Quickshell / Pebble Shell**, **UWSM**, **fcitx5**, **KDE Plasma** e do antigo runtime `core/` nesta branch, deixando o repositório focado exclusivamente em **GNOME + NixOS**.

---

## 1. Expurgo Realizado

- **`core/`** (removido integralmente): antigo runtime CLI (`core/bin/*`), Quickshell/Pebble Shell (`core/shell/*`), defaults de Hyprland/UWSM/fcitx5/SDDM/Plymouth (`core/default/*`) e temas acoplados ao Hyprland (`core/themes/*`).
- **`local/`** (removido integralmente): `hypr-all-full-width`, `hypr-smart-focus`, `inferna-glass`, `inferna-recess`, `touchpad-control`, `omarchy-*` e coletores do antigo painel.
- **`kitty/`** (removido): terminal substituído pelo GNOME Console (`kgx`) nativo.
- **`nixos/modules/packages-adhoc.nix`** (removido): módulo vazio usado apenas pelo antigo `core/bin/inferna-pkg-add`.
- **Screenshots do antigo Hyprland/Pebble Shell** em `docs/*.webp` e `docs/wordmark.svg` (removidos).

---

## 2. Ajustes nos Módulos NixOS (`nixos/`)

- **[`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix)** (novo):
  - Habilita `services.desktopManager.gnome` e `services.displayManager.gdm` (trazendo toda a suíte padrão do GNOME).
  - Adiciona `file-roller`, `gnome-tweaks`, `gnome-extension-manager`, `dconf-editor` e apenas 2 extensões utilitárias (`appindicator`, `clipboard-indicator`).
  - Aplica um rice mínimo não-bloqueante via `extraGSettingsOverrides`, mantendo o tema padrão **Adwaita** intocado, com exemplos comentados para customização futura (ver [`docs/gnome-rice-guide.md`](gnome-rice-guide.md)).
  - Exporta `NIXOS_OZONE_WL = "1"`.
- **[`nixos/modules/desktop.nix`](../nixos/modules/desktop.nix)**:
  - Removidos o workaround manual de `XDG_DATA_DIRS` (do Hyprland) e `INFERNA_PATH`.
- **[`nixos/modules/hardware.nix`](../nixos/modules/hardware.nix)**, **[`nixos/modules/nvidia.nix`](../nixos/modules/nvidia.nix)** e **[`nixos/modules/gaming.nix`](../nixos/modules/gaming.nix)**:
  - Restaurados `hardware.graphics` (`enable`, `enable32Bit`, `intel-media-driver`, `libvdpau-va-gl`) e `boot.kernelParams` (`nvidia_drm.modeset=1`, `nvidia_drm.fbdev=1`), que haviam sido perdidos ao deletar `hyprland.nix`.
- **[`nixos/modules/packages.nix`](../nixos/modules/packages.nix)**:
  - Removidos pacotes incompatíveis com GNOME Wayland ou exclusivos do antigo runtime: `grim`, `slurp`, `xwinwrap`, `feh`, `glib`, `gsettings-desktop-schemas`, `gum`, `imagemagick`.
  - Removidas duplicatas dos apps nativos do GNOME: `galculator`, `xarchiver`, `evince`.
- **[`nixos/modules/development.nix`](../nixos/modules/development.nix)**:
  - Trocado `pinentry-qt` (workaround de Hyprland) por `pinentry-gnome3`.

---

## 3. Fastfetch e Instalador

- **[`fastfetch/dashboard.py`](../fastfetch/dashboard.py)**: reescrito para ser 100% independente de `core/`, sem referências a `konsole`/KDE ou `inferna` CLI, detectando GNOME Console (`kgx`), fonte monospace e aparência diretamente via `gsettings`.
- **[`install.sh`](../install.sh)**: simplificado para instalar apenas `fastfetch/` + `branding/about.txt` em `~/.config/fastfetch/` e limpar automaticamente symlinks antigos de `core/bin/inferna*`, `hypr-*` e `denon-*` em `~/.local/`.
