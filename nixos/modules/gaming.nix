{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };

  # 32-bit Vulkan/NVIDIA userspace for Steam/Lutris/Heroic/umu-launcher is
  # already declared unconditionally in hyprland.nix
  # (hardware.graphics.enable32Bit) -- nothing to add here (see
  # core/bin/inferna-install-gaming-gpu-lib32, a no-op on NixOS).

  # xpadneo loads as a proper kernel module built against the running
  # kernel and blacklists the stock xpad driver itself -- no DKMS, no manual
  # modprobe/usermod dance (see core/bin/inferna-install-gaming-xbox-controllers).
  hardware.xpadneo.enable = true;

  environment.systemPackages = with pkgs; [
    heroic
    lutris
    umu-launcher # also used directly by inferna-install-gaming-battlenet

    # Core set confirmed to exist under pkgs.libretro; add more from there as
    # needed (ported from the Arch libretro-* package list in
    # core/bin/inferna-install-gaming-retroarch).
    (retroarch.withCores (
      cores: with cores; [
        mgba
        snes9x
        genesis-plus-gx
        beetle-psx
        beetle-pce-fast
        bsnes
        mupen64plus
        dolphin
        flycast
        mesen
        picodrive
        ppsspp
        scummvm
        fbneo
      ]
    ))
  ];
}
