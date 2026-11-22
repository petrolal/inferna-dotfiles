# nix-ld lets unpatched/FHS dynamic binaries find their dynamic linker and
# libraries without polluting every process on the system via a global
# LD_LIBRARY_PATH. Centralized here since it's a single host-wide concern,
# not scoped to any one tool.
{ pkgs, ... }:
{
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Generic X11/GL/Wayland & Electron/Chromium runtime libraries for
    # unpatched AppImages and local Electron builds (e.g. .build/electron/*).
    glib
    nss
    nspr
    at-spi2-core
    at-spi2-atk
    cups
    dbus
    cairo
    gtk3
    pango
    expat
    alsa-lib
    libpulseaudio
    libsecret
    libdrm
    libgbm
    mesa
    libGL
    vulkan-loader
    wayland
    libxkbcommon
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    libxshmfence
  ];
}
