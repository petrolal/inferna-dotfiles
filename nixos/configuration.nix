{
  lib,
  ...
}:

{
  imports = [
    ./modules/hardware.nix
    ./modules/plymouth.nix
    ./modules/networking.nix
    ./modules/desktop.nix
    ./modules/gnome.nix
    ./modules/nvidia.nix
    ./modules/fonts.nix
    ./modules/users.nix
    ./modules/packages.nix
    ./modules/gaming.nix
    ./modules/nix-ld.nix
    ./modules/development.nix
    ./modules/containers.nix
    ./modules/ollama.nix
    ./modules/first-login.nix
  ];

  system.stateVersion = lib.mkDefault "26.05";
}
