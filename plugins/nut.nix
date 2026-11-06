{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  bash,
  coreutils,
  gnugrep,
  gawk,
  nut,
}:
let
  version = "3.0.4";
  src = fetchFromGitHub {
    owner = "virus2500";
    repo = "checkmk_nut";
    tag = "v${version}";
    hash = "sha256-Flp7xIvyrtzIL62+6BMBPeT6bic/nImTtRO+xhvslSw=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "checkmk-plugin-nut";
  inherit src version;
  dontUnpack = true;
  dontBuild = true;
  strictDeps = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src/local/share/check_mk/agents/plugins/nut.sh" "$out/bin/nut"
    install -Dm644 "$src/LICENSE" "$out/share/licenses/checkmk-plugin-nut/LICENSE"
    substituteInPlace "$out/bin/nut" \
      --replace-fail "which upsc" "command -v upsc" \
      --replace-fail "which awk" "command -v awk"
    wrapProgram "$out/bin/nut" \
      --set PATH ${
        lib.makeBinPath [
          nut
          coreutils
          gnugrep
          gawk
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Checkmk agent plugin for Network UPS Tools";
    homepage = "https://github.com/virus2500/checkmk_nut";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "nut";
  };
}
