# Como Funciona o Rice no GNOME + NixOS

Este guia explica a estrutura de temas, CSS, papel de parede e extensões do GNOME configurada neste repositório.

---

## Estrutura de Arquivos do Rice

```text
inferna-dotfiles/
├── nixos/
│   ├── assets/wallpapers/
│   │   └── inferna.jpeg                  # Papel de parede default embutido no NixOS
│   └── modules/gnome.nix                 # Extensões, adw-gtk3 e defaults (GSettings)
├── gnome/
│   ├── apply-theme.sh                    # Helper `inferna-theme` (aplicar / recarregar / resetar)
│   └── themes/
│       └── Inferna/                      # Tema base editável
│           ├── theme.env                 # color-scheme, accent-color, gtk-theme e wallpaper opcional
│           ├── gtk-4.0/gtk.css           # Cores/CSS dos apps GTK4 & Libadwaita
│           ├── gtk-3.0/gtk.css           # Cores/CSS dos apps GTK3 (adw-gtk3-dark)
│           └── gnome-shell/
│               └── gnome-shell.css       # CSS da barra superior, menus, overview, dock e OSD
└── install.sh                            # Instala symlinks em ~/.themes, ~/.config/gtk-* e ~/.local/bin/inferna-theme
```

---

## O que já vem ativo no bootstrap

- **NixOS ([`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix)):**
  - Suíte padrão completa do GNOME + `file-roller`, `gnome-tweaks`, `gnome-extension-manager`, `dconf-editor` e `adw-gtk3`.
  - Extensões habilitadas (compatíveis com GNOME 51): `AppIndicator`, `Clipboard Indicator`, `User Themes`, `Space Bar`, `Revived Media Controls`, `Caffeine`, `Vitals`, `Rounded Window Corners Reborn`, `Blur my Shell`, `GameMode Shell Extension` e `Transparent Move`.
  - Defaults não-bloqueantes (`extraGSettingsOverrides`): modo escuro (`prefer-dark`), accent `orange` (chama), `adw-gtk3-dark`, papel de parede padrão [`nixos/assets/wallpapers/inferna.jpeg`](../nixos/assets/wallpapers/inferna.jpeg), fonte `JetBrainsMono Nerd Font 10`, botões `minimizar, maximizar, fechar`, relógio com dia da semana, bateria em %, janelas centralizadas e gestos de touchpad.
- **Dotfiles ([`install.sh`](../install.sh)):**
  - Symlinka todos os temas de `gnome/themes/*` em `~/.themes/`.
  - Symlinka o wallpaper padrão em `~/.local/share/backgrounds/inferna/`.
  - Instala o comando `inferna-theme` em `~/.local/bin/inferna-theme` e aplica o tema `Inferna`.

---

## Como editar cores, CSS e papel de parede

### 1. Editar cores e CSS dos aplicativos (`GTK4 / Libadwaita` e `GTK3`)
- **Apps GTK4 / Libadwaita** (Nautilus, GNOME Console, Configurações, etc.): edite [`gnome/themes/Inferna/gtk-4.0/gtk.css`](../gnome/themes/Inferna/gtk-4.0/gtk.css) (variáveis `--accent-bg-color`, `--window-bg-color`, `--headerbar-bg-color`, `--card-bg-color`, etc.).
- **Apps GTK3**: edite [`gnome/themes/Inferna/gtk-3.0/gtk.css`](../gnome/themes/Inferna/gtk-3.0/gtk.css).
- Para ver o resultado, feche e reabra o aplicativo.

### 2. Editar o CSS do GNOME Shell (barra superior, menus, overview, OSD)
- Edite [`gnome/themes/Inferna/gnome-shell/gnome-shell.css`](../gnome/themes/Inferna/gnome-shell/gnome-shell.css).
- O arquivo importa primeiro o stylesheet oficial do GNOME Shell (`@import url("resource:///org/gnome/shell/theme/gnome-shell-dark.css");`), então só o que você sobrescrever é alterado — seguro entre atualizações do GNOME.
- **Recarregar ao vivo sem reiniciar a sessão:**
  ```bash
  inferna-theme Inferna
  ```
- **Inspecionar classes CSS do GNOME Shell:** pressione `Alt+F2`, digite `lg` (*Looking Glass*) e use o seletor de elementos.

### 3. Criar novos temas e alternar entre eles
1. Duplique o tema base:
   ```bash
   cp -r ~/inferna-dotfiles/gnome/themes/Inferna ~/inferna-dotfiles/gnome/themes/MeuTema
   ```
2. Edite `theme.env`, `gtk-4.0/gtk.css`, `gtk-3.0/gtk.css` e `gnome-shell/gnome-shell.css` dentro de `MeuTema/`.
   - Opcional: coloque um arquivo `wallpaper.png` / `.jpg` / `.jpeg` / `.webp` na pasta `MeuTema/` (ou defina `WALLPAPER="..."` em `theme.env`) para o tema trocar o papel de parede automaticamente.
3. Aplique ou liste temas:
   ```bash
   inferna-theme --list
   inferna-theme MeuTema
   ```
4. Voltar para os padrões limpos sem CSS customizado:
   ```bash
   inferna-theme --reset
   ```

### 4. Trocar o papel de parede default do sistema (bootstrap) e estilizar o login (GDM)
- **Wallpaper default (desktop + GDM):** substitua [`nixos/assets/wallpapers/inferna.jpeg`](../nixos/assets/wallpapers/inferna.jpeg) (ou adicione outro arquivo em `nixos/assets/wallpapers/` e atualize `defaultWallpaper` em [`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix)).
- **CSS da tela de login e bloqueio (GDM):** edite [`nixos/assets/gdm/gdm.css`](../nixos/assets/gdm/gdm.css) (injetado declarativamente no `gnome-shell-theme.gresource` junto com o perfil dconf do GDM).
- **Desligar o tema do GDM rapidamente:** defina `dotfiles.gdmTheme.enable = false;` em [`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix).
- Depois de alterar qualquer item acima, aplique com `sudo nixos-rebuild switch --flake ~/inferna-dotfiles/nixos#default`.

---

## Descobrir chaves GSettings e adicionar extensões

- **Descobrir qualquer chave modificada na interface:**
  ```bash
  dconf watch /
  ```
- **Testar ajustes rápidos sem rebuild:**
  ```bash
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface accent-color 'red'
  gsettings reset org.gnome.desktop.interface accent-color
  ```
- **Adicionar novas extensões declarativamente:** teste pelo **Extension Manager** (`gnome-extension-manager`) e depois declare `pkgs.gnomeExtensions.<nome>` + o UUID em `enabled-extensions` dentro de [`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix) (exemplos já comentados: `blur-my-shell`, `dash-to-dock`, `just-perfection`).
