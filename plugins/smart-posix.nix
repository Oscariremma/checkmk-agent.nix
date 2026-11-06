{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  gnugrep,
  gawk,
  findutils,
  smartmontools,
  src,
  version,
}:
stdenvNoCC.mkDerivation {
  pname = "checkmk-plugin-smart-posix";
  inherit src version;
  dontUnpack = true;
  dontBuild = true;
  strictDeps = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src/agents/plugins/smart_posix" "$out/bin/smart_posix"
    wrapProgram "$out/bin/smart_posix" \
      --set PATH ${
        lib.makeBinPath [
          smartmontools
          coreutils
          gnugrep
          gawk
          findutils
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Checkmk SMART monitoring plugin";
    homepage = "https://docs.checkmk.com/latest/en/agent_linux.html";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "smart_posix";
  };
}
