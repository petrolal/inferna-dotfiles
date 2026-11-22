{ pkgs, ... }:

# Docker and Kubernetes CLI tooling. `virtualisation.docker.enable` runs the
# real daemon (systemd service) and adds the `docker` CLI to
# environment.systemPackages on its own -- installing `pkgs.docker` directly
# without this would give a client with no daemon to talk to.
{
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
}
