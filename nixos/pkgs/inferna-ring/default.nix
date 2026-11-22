{
  stdenv,
  libGL,
  mesa,
  zlib,
}:

stdenv.mkDerivation {
  pname = "inferna-ring";
  version = "1.0.0";

  src = ./.;

  buildInputs = [
    libGL
    mesa
    zlib
  ];

  buildPhase = ''
    runHook preBuild
    mkdir -p $out/bin $out/share/inferna-ring
    cp ring.frag $out/share/inferna-ring/ring.frag
    $CC -O3 -Wall -Wextra \
      -DDEFAULT_SHADER_PATH="\"$out/share/inferna-ring/ring.frag\"" \
      main.c -o $out/bin/inferna-ring \
      -lEGL -lGLESv2 -lz -lm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    runHook postInstall
  '';
}
