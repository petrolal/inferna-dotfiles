# Como Funciona o Rice no GNOME + NixOS

Este guia explica como o GNOME é configurado nesta branch antes de você começar a mudar cores, temas ou layout.

---

## O que já vem ativo (rice mínimo, tema padrão intocado)

Tudo está centralizado em [`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix). O tema padrão do GNOME (**Adwaita**) não foi alterado. Apenas ajustes mínimos de ergonomia foram aplicados:

- **Apps padrão do GNOME**: Nautilus, GNOME Console (`kgx`), Loupe (imagens), Papers (PDF), Showtime (vídeos), Calculator, Text Editor, Calendar, Clocks, Weather, System Monitor, Disks, Characters, Font Viewer, Baobab, Snapshot, Decibels, Extensions + `file-roller` (compactador).
- **Ferramentas de personalização**: `gnome-tweaks`, `gnome-extension-manager`, `dconf-editor`.
- **Extensões ativas (apenas utilidade, sem alterar o visual)**:
  - `AppIndicator` — ícones de bandeja na barra superior (Steam, Spotify, Telegram).
  - `Clipboard Indicator` — histórico do clipboard na barra superior.
- **Padrões de ergonomia (`extraGSettingsOverrides`)**:
  - Fonte monospace `JetBrainsMono Nerd Font 10` no terminal.
  - Botões `minimizar, maximizar, fechar` nas janelas.
  - Dia da semana no relógio + porcentagem da bateria.
  - Janelas novas centralizadas (`center-new-windows`), workspaces dinâmicos e tiling nas bordas (`edge-tiling`).
  - Touchpad com `tap-to-click`, `natural-scroll` e rolagem com dois dedos.

---

## As 3 Camadas do Rice no GNOME (no NixOS)

Diferente de um tiling WM (onde você edita arquivos `.conf`/`.lua` e recarrega o compositor), no GNOME tudo passa por **3 camadas**:

### 1. GSettings / dconf (comportamento, fontes, atalhos, tema nativo)
Quase toda configuração do GNOME fica no banco **dconf**, acessado via `gsettings`.

- **Por que usamos `extraGSettingsOverrides` em `gnome.nix`?**
  Ele define **valores padrão (defaults)** nos schemas do sistema **sem travar o dconf**. Isso significa que você pode testar qualquer mudança ao vivo nas **Configurações do GNOME**, no **GNOME Tweaks** ou pelo terminal (`gsettings set ...`).
- **Como descobrir a chave exata de qualquer ajuste que você fizer na interface:**
  Abra o terminal e rode:
  ```bash
  dconf watch /
  ```
  Depois mude qualquer opção nas Configurações do GNOME, Tweaks ou em uma extensão — o terminal imprime na hora o caminho e o valor exato!
- **Como testar um ajuste pelo terminal (efeito imediato, sem rebuild):**
  ```bash
  # Alternar modo escuro / claro
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

  # Trocar cor de destaque nativa do GNOME (Adwaita)
  # Valores: 'blue' | 'teal' | 'green' | 'yellow' | 'orange' | 'red' | 'pink' | 'purple' | 'slate'
  gsettings set org.gnome.desktop.interface accent-color 'red'

  # Reverter uma chave para o padrão declarado no NixOS
  gsettings reset org.gnome.desktop.interface accent-color
  ```
  Quando gostar do resultado, basta descomentar/colar a chave no bloco `extraGSettingsOverrides` em [`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix) e rodar `nixos-rebuild switch`.

> **Dica:** chaves que você já alterou manualmente no seu usuário ficam gravadas no seu dconf local (`~/.config/dconf/user`) e têm prioridade sobre `extraGSettingsOverrides`. Para voltar ao padrão do `gnome.nix`, use `gsettings reset <schema> <chave>`.

### 2. Extensões do GNOME Shell (barra, dock, blur, tiling, etc.)
Extensões modificam o **GNOME Shell** em si (painel superior, dock, blur, tiling de janelas, etc.).

- **Testando rápido:** abra o app **Extension Manager** (`gnome-extension-manager`) para procurar, testar e configurar extensões com 1 clique.
- **Tornando declarativo no NixOS:** adicione o pacote `pkgs.gnomeExtensions.<nome>` em `environment.systemPackages` e o UUID dela em `enabled-extensions` dentro de [`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix).
  Exemplos já comentados em `gnome.nix`:
  - `gnomeExtensions.blur-my-shell` (blur no painel, overview e tela de bloqueio)
  - `gnomeExtensions.dash-to-dock` (dock permanente/auto-hide)
  - `gnomeExtensions.user-themes` (permite carregar temas CSS customizados do GNOME Shell)

### 3. Temas e CSS (quando você quiser mudar o visual além do Adwaita)
Quando quiser ir além de `color-scheme` + `accent-color` nativos do Adwaita:

- **Apps GTK4 / Libadwaita**: leem `~/.config/gtk-4.0/gtk.css` (e apps GTK3 leem `~/.config/gtk-3.0/gtk.css`).
- **GNOME Shell (painel, menus, overview)**: com a extensão `user-themes` ativa, lê `~/.themes/<NomeDoTema>/gnome-shell/gnome-shell.css`.
- **Ícones e Cursor**: pacotes Nix (ex.: `pkgs.papirus-icon-theme`, `pkgs.bibata-cursors`) + chaves `icon-theme` / `cursor-theme` em `[org.gnome.desktop.interface]`.

---

## Fluxo recomendado para começar a editar

1. Use o GNOME como está por 1–2 dias para sentir o fluxo padrão (Super para Overview, atalhos de workspaces, `Print` para captura/gravação nativa).
2. Abra `dconf watch /` enquanto ajusta preferências no **Configurações** / **GNOME Tweaks** / **Extension Manager**.
3. Copie para [`nixos/modules/gnome.nix`](../nixos/modules/gnome.nix) apenas o que você realmente quiser manter declarativo no sistema.
