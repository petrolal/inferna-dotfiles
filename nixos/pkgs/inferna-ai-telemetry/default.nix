{
  stdenvNoCC,
  python3,
  libsecret,
  makeWrapper,
}:

stdenvNoCC.mkDerivation {
  pname = "inferna-ai-telemetry";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m 755 inferna-ai-usage.py $out/bin/inferna-ai-usage
    patchShebangs $out/bin/inferna-ai-usage
    wrapProgram $out/bin/inferna-ai-usage \
      --prefix PATH : "${python3}/bin:${libsecret}/bin"

    extDir="$out/share/gnome-shell/extensions/ai-telemetry@inferna"
    mkdir -p "$extDir"
    cp extension/metadata.json "$extDir/"
    cp extension/extension.js "$extDir/"
    cp extension/stylesheet.css "$extDir/"
    cp extension/inferna-ai-symbolic.svg "$extDir/"

    runHook postInstall
  '';
}
