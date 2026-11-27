{
  config,
  lib,
  pkgs,
  ...
}:

# Docker and Kubernetes CLI tooling. `virtualisation.docker.enable` runs the
# real daemon (systemd service) and adds the `docker` CLI to
# environment.systemPackages on its own.
let
  cfg = config.dotfiles.containers;
in
{
  options.dotfiles.containers.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable socket-activated Docker daemon, docker-compose, and kubectl.";
  };

  config = lib.mkIf cfg.enable {
    # Socket-activated: docker.socket starts dockerd transparently on the first
    # `docker` invocation instead of consuming RAM/CPU from boot.
    virtualisation.docker = {
      enable = true;
      enableOnBoot = false;
    };

    environment.systemPackages = with pkgs; [
      docker-compose
      kubectl
    ];
  };
}
