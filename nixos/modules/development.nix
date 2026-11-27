{
  config,
  lib,
  pkgs,
  ...
}:

# Per-project toolchains the Nix way: each project carries a shell.nix and
# direnv loads it on `cd`. Replaces version managers such as SDKMAN!, nvm,
# pyenv and gvm.
let
  cfg = config.dotfiles.development;

  jvmTemplate = ../templates/jvm;
  nodeTemplate = ../templates/node;
  goTemplate = ../templates/go;
  pythonTemplate = ../templates/python;
  templates = ../templates;

  # mkLangInit --- single-language variant of dev-init below: drops that
  # language's shell.nix + .envrc into the current directory, pinned to
  # VERSION (default: `default`), and allows it in direnv.
  mkLangInit =
    {
      name,
      attr,
      label,
      default,
      template,
    }:
    pkgs.writeShellScriptBin name ''
      set -eu
      version="''${1:-${default}}"
      for f in shell.nix .envrc; do
        if [ -e "$f" ]; then
          echo "${name}: $f already exists, refusing to overwrite" >&2
          exit 1
        fi
      done
      ${pkgs.gnused}/bin/sed "s/${attr} ? \"${default}\"/${attr} ? \"$version\"/" \
        ${template}/shell.nix > shell.nix
      install -m 644 ${template}/.envrc .envrc
      ${pkgs.direnv}/bin/direnv allow .
      echo "${name}: ${label} $version environment created; it loads on cd."
    '';

  jvm-init = mkLangInit {
    name = "jvm-init";
    attr = "java";
    label = "JDK";
    default = "25";
    template = jvmTemplate;
  };

  node-init = mkLangInit {
    name = "node-init";
    attr = "node";
    label = "Node.js";
    default = "24";
    template = nodeTemplate;
  };

  go-init = mkLangInit {
    name = "go-init";
    attr = "go";
    label = "Go";
    default = "1.26";
    template = goTemplate;
  };

  python-init = mkLangInit {
    name = "python-init";
    attr = "python";
    label = "Python";
    default = "3.13";
    template = pythonTemplate;
  };

  dev-init = pkgs.writeShellScriptBin "dev-init" ''
    set -eu
    available=$(cd ${templates} && for d in */; do
      d=''${d%/}
      [ "$d" != full ] && [ -e "$d/shell.nix" ] && echo "$d"
    done)
    langs="''${*:-$available}"
    for f in shell.nix .envrc nix; do
      if [ -e "$f" ]; then
        echo "dev-init: $f already exists, refusing to overwrite" >&2
        exit 1
      fi
    done
    for l in $langs; do
      if [ ! -e "${templates}/$l/shell.nix" ]; then
        echo "dev-init: unknown language '$l' (available:" $available")" >&2
        exit 1
      fi
    done
    for l in $langs; do
      install -D -m 644 "${templates}/$l/shell.nix" "nix/$l/shell.nix"
    done
    ${pkgs.gnused}/bin/sed 's|templates ? \./\.\.|templates ? ./nix|' \
      ${templates}/full/shell.nix > shell.nix
    install -m 644 ${templates}/full/.envrc .envrc
    ${pkgs.direnv}/bin/direnv allow .
    echo "dev-init: environment with" $langs "created; it loads on cd."
  '';

  devshell = pkgs.writeShellScriptBin "devshell" ''
    export DEV_STATE_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/devshell"
    mkdir -p "$DEV_STATE_DIR"
    user_shell="''${SHELL:-${pkgs.fish}/bin/fish}"
    exec nix-shell ${templates}/full/shell.nix "$@" --command "exec $user_shell"
  '';

  buildTools = [
    (pkgs.gradle.override { java = pkgs.jdk21; })
    (pkgs.maven.override { jdk_headless = pkgs.jdk21; })
    pkgs.lombok
    pkgs.tomcat10
  ];
in
{
  options.dotfiles.development.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable direnv, GnuPG agent, dev-init/devshell templates, and JVM build tools.";
  };

  config = lib.mkMerge [
    {
      # Flakes and nix-command are always required by Inferna itself.
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
    }

    (lib.mkIf cfg.enable {
      # Hooks into fish, bash, and zsh automatically; nix-direnv is enabled by default
      # and provides `use nix` with caching.
      programs.direnv.enable = true;

      # GnuPG + agent with native GNOME pinentry.
      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-gnome3;
      };

      environment.systemPackages = [
        jvm-init
        node-init
        go-init
        python-init
        dev-init
        devshell
      ] ++ buildTools;
    })
  ];
}
