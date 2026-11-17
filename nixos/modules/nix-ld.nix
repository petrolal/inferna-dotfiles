# nix-ld lets unpatched/FHS dynamic binaries find their dynamic linker and
# libraries without polluting every process on the system via a global
# LD_LIBRARY_PATH. Centralized here since it's a single host-wide concern,
# not scoped to any one tool.
{ pkgs, ... }:
{
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Generic X11/GL, for unpatched AppImages (packages.nix's appimage-run).
    libx11
    libGL
  ];
}
