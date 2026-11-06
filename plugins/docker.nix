{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  docker-client,
  formats,
  src,
  version,
  baseUrl ? "unix://var/run/docker.sock",
  containerId ? "short",
  skipSections ? [ ],
  persistPeriodNodeDiskUsage ? 90,
}:
assert lib.assertMsg (builtins.elem containerId [
  "short"
  "long"
  "name"
  "combined"
]) "Docker containerId must be short, long, name, or combined";
assert lib.assertMsg (
  builtins.isList skipSections && builtins.all builtins.isString skipSections
) "Docker skipSections must be a list of section names";
assert lib.assertMsg (
  builtins.isInt persistPeriodNodeDiskUsage && persistPeriodNodeDiskUsage >= 0
) "Docker persistPeriodNodeDiskUsage must be a non-negative number of seconds";
let
  python = python3.withPackages (ps: [ ps.docker ]);
  configFile = (formats.ini { }).generate "checkmk-docker.cfg" {
    DOCKER = {
      base_url = baseUrl;
      container_id = containerId;
      skip_sections = lib.concatStringsSep "," skipSections;
      persist_period_node_disk_usage = persistPeriodNodeDiskUsage;
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "checkmk-plugin-docker";
  inherit src version;
  dontUnpack = true;
  dontBuild = true;
  strictDeps = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python ];

  installPhase = ''
    runHook preInstall
    install -Dm644 "$src/agents/plugins/mk_docker.py" "$out/libexec/mk_docker.py"
    substituteInPlace "$out/libexec/mk_docker.py" \
      --replace-fail 'default: $MK_CONFDIR/docker.cfg' 'default: packaged configuration'
    makeWrapper "${python}/bin/python3" "$out/bin/mk_docker" \
      --add-flags "$out/libexec/mk_docker.py" \
      --prefix PATH : ${lib.makeBinPath [ docker-client ]} \
      --add-flags ${lib.escapeShellArg "--config-file ${configFile}"}
    runHook postInstall
  '';

  meta = {
    description = "Checkmk Docker monitoring plugin";
    homepage = "https://docs.checkmk.com/latest/en/monitoring_docker.html";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "mk_docker";
  };
}
