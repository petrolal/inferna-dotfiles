{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dotfiles.packages;

  # libx11/libGL also appear in nix-ld.nix's `programs.nix-ld.libraries`
  # (nix-ld needs its own copy of the option's value) -- here they're genuine
  # environment.systemPackages entries appimage-run and other unpatched
  # binaries can dlopen directly.
  dynamicLibs = with pkgs; [
    stdenv.cc.cc.lib
    libx11
    libGL
    libxkbfile
    libsecret
    libkrb5
  ];

  buildTools =
    with pkgs;
    [
      gnumake
      cmake
      ninja
      pkg-config
      gcc # C compiler for Tree-sitter parsers & telescope-fzf-native (TetraVim/nvim)
      gdb # GNU Debugger for Qt Creator, C/C++ development
      graalvmPackages.graalvm-ce
    ]
    ++ dynamicLibs;

  mediaTools = with pkgs; [
    mpv
    mangohud # FPS/frametime/GPU overlay
  ];

  devTools = with pkgs; [
    emacs
    neovim
    vscode
    claude-code
    claude-desktop # Official Claude Desktop (incl. Claude Code GUI) via claude-desktop flake overlay
    bruno
  ];

  searchTools = with pkgs; [
    ripgrep
    fd
  ];

  nvimTools = with pkgs; [
    jdk21
    lazygit
    grpcurl
    grpcui
    osv-scanner
    tflint
    trivy
    awscli2
    aws-sam-cli
    lazydocker
    jq
    stylua
    yamlfmt
    mermaid-cli
    sonar-scanner-cli
  ];

  nvimRuntimes = with pkgs; [
    nodejs_24 # includes npm/npx
    python3 # includes pip/venv
    go
    pnpm
  ];

  languageTools = with pkgs; [
    nixd
    glslls
    glslang
    shaderc
    shellcheck
    terraform
    terraform-ls
    protobuf
    postgresql
    pandoc
    google-cloud-sdk
  ];

  # Always installed as part of the core Inferna rice experience.
  systemTools = with pkgs; [
    git
    pciutils
    htop
    btop # Resource monitor TUI with Inferna theme (CPU/RAM/Net/GPU)
    eza # Modern ls with Nerd Font icons & git status
    bat # Syntax-highlighted cat inheriting Ghostty Inferna palette
    zoxide # Smart directory jumper (z)
    yazi # Blazing-fast TUI file manager with Kitty image previews
    cava # Audio visualizer with Inferna fire gradient
    fastfetch
    curl
    wget
    zip
    unzip
    which
    less
    rlwrap
    wl-clipboard
    fzf # Fuzzy finder CLI
    starship # Minimal, fast shell prompt (configured in starship/starship.toml)
    (callPackage ../pkgs/inferna-ring { }) # Real-time OpenGL/GLSL 3D Inferna NixOS ring renderer
  ];

  mediaUtils = with pkgs; [
    shotcut
    appimage-run
    spotify
  ];

  threeDTools = with pkgs; [
    blender
    blockbench
    f3d
    meshlab
    qtcreator
    qt6.qtdeclarative
    qt6.qtquick3d
    qt6.qtquicktimeline
    qt6.qtshadertools
  ];

  imageEditors = with pkgs; [
    gimp
    krita
    inkscape
    pinta
  ];

  dailyTools = with pkgs; [
    telegram-desktop
    google-chrome
  ];
in
{
  options.dotfiles.packages = {
    devExtras.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install full developer toolchain (Emacs, Neovim, VS Code, Claude Code & Desktop, LSPs, compilers, runtimes).";
    };

    creative3d.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install 3D and image creation suite (Blender, Krita, GIMP, Inkscape, Qt Creator, MeshLab).";
    };

    dailyApps.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install daily desktop apps (Google Chrome, Telegram, Spotify, Shotcut, appimage-run).";
    };
  };

  config = {
    environment.systemPackages =
      systemTools
      ++ mediaTools
      ++ lib.optionals cfg.devExtras.enable (
        buildTools ++ devTools ++ searchTools ++ nvimTools ++ nvimRuntimes ++ languageTools
      )
      ++ lib.optionals cfg.creative3d.enable (threeDTools ++ imageEditors)
      ++ lib.optionals cfg.dailyApps.enable (dailyTools ++ mediaUtils);
  };
}
