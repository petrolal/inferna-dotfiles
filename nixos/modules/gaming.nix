{ pkgs, ... }:

let
  # Force TETR.IO Desktop to run via XWayland instead of native Ozone Wayland.
  # Electron 45+ defaults to Wayland when WAYLAND_DISPLAY is set and ignores
  # ELECTRON_OZONE_PLATFORM_HINT=x11, hitting `eglCreateImage failed with
  # 0x00003004` (EGL_BAD_ATTRIBUTE) on hybrid Intel/NVIDIA graphics and looping
  # `RasterDecoderImpl: Context lost` at 100% CPU with no visible window.
  # Passing `--ozone-platform=x11` explicitly (and unsetting NIXOS_OZONE_WL so
  # nixpkgs' inner wrapper does not inject Wayland flags) forces XWayland while
  # keeping full GPU WebGL2 acceleration.
  tetrioDesktop = pkgs.tetrio-desktop.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/tetrio \
        --unset NIXOS_OZONE_WL \
        --add-flags "--ozone-platform=x11"
    '';
  });
in
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };

  # GameMode CPU governor & process priority optimizations for games
  # (paired with gnomeExtensions.gamemode-shell-extension in gnome.nix).
  programs.gamemode.enable = true;

  # 32-bit Vulkan/NVIDIA userspace for Steam/Lutris/Heroic/umu-launcher is
  # already declared unconditionally in hardware.nix
  # (hardware.graphics.enable32Bit) -- nothing to add here.

  # xpadneo loads as a proper kernel module built against the running
  # kernel and blacklists the stock xpad driver itself -- no DKMS, no manual
  # modprobe/usermod dance.
  hardware.xpadneo.enable = true;

  environment.systemPackages = with pkgs; [
    heroic
    lutris
    umu-launcher
    tetrioDesktop

    # Core set confirmed to exist under pkgs.libretro; add more as needed.
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
