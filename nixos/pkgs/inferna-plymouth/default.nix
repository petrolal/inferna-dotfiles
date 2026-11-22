{
  stdenvNoCC,
  inferna-ring,
  imagemagick,
  mesa,
}:

stdenvNoCC.mkDerivation {
  pname = "inferna-plymouth-theme";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [
    inferna-ring
    imagemagick
  ];

  # Mesa llvmpipe provides headless software OpenGL ES 3.0 inside the Nix build sandbox
  # so the exact same GLSL shader (ring.frag) drives both Ghostty and the Plymouth boot splash!
  buildPhase = ''
    runHook preBuild

    export XDG_CACHE_HOME="$TMPDIR/cache"
    export HOME="$TMPDIR"
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    export EGL_PLATFORM=surfaceless
    export LD_LIBRARY_PATH="${mesa}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LIBGL_DRIVERS_PATH="${mesa}/lib/dri"
    export __EGL_VENDOR_LIBRARY_DIRS="${mesa}/share/glvnd/egl_vendor.d"

    mkdir -p "$XDG_CACHE_HOME" frames

    # Render 72 seamless 360-deg 3D frames at 320x320 composited over #0d0908
    inferna-ring --png-seq frames --size 320 --frames 72 --yaw 0 --pitch -12

    # Forged ember progress track (260x3) & gradient fill (crimson -> ember -> gold)
    magick -size 260x3 xc:"#2a1b16" PNG32:bar-track.png
    magick -size 3x260 gradient:"#b82412-#ff622e" \
      \( -size 3x130 gradient:"#ff622e-#f2a949" \) -gravity South -compose Over -composite \
      -rotate 90 PNG32:bar-fill.png

    # Sleek dark forged LUKS password box (260x32) & glowing ember bullet (8x8)
    magick -size 260x32 xc:"#160f0d" \
      -fill none -stroke "#a83219" -strokewidth 1 \
      -draw "roundrectangle 0,0 259,31 4,4" \
      PNG32:dialog-box.png

    magick -size 8x8 xc:none \
      -fill "#ff622e" -draw "circle 4,4 4,1" \
      PNG32:bullet.png

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    themeDir="$out/share/plymouth/themes/inferna"
    mkdir -p "$themeDir"

    cp frames/frame-*.png "$themeDir/"
    cp bar-track.png bar-fill.png dialog-box.png bullet.png "$themeDir/"
    cp inferna.script "$themeDir/inferna.script"
    substitute inferna.plymouth "$themeDir/inferna.plymouth" \
      --replace-fail "@themeDir@" "$themeDir"

    runHook postInstall
  '';
}
