{ config, pkgs, ... }:

{
  # Hostname is set per-config in flake.nix's mkConfig (one source of truth).

  networking.networkmanager.enable = true;

  # Don't block boot for ~5.5s waiting for an online network interface.
  systemd.services.NetworkManager-wait-online.enable = false;

  services.resolved.enable = true;
  services.openssh.enable = true;
}
