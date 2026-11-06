{ pkgs, self }:
let
  inherit (pkgs) lib;
  plugins = self.legacyPackages.${pkgs.stdenv.hostPlatform.system}.checkmkAgentPlugins;
  smart = plugins.smart-posix.override {
    smartmontools = pkgs.writeShellScriptBin "smartctl" ''
      case "$1" in
        -V) echo 'smartctl 7.5' ;;
        --scan) echo '/dev/test -d sat # simulated disk' ;;
        --all) echo '{"smart_status":{"passed":true}}' ;;
        *) exit 1 ;;
      esac
    '';
  };
  nut = plugins.nut.override {
    nut = pkgs.writeShellScriptBin "upsc" ''
      case "$*" in
        '-l localhost') echo testups ;;
        testups@localhost) printf 'battery.charge: 100\nups.status: OL\n' ;;
        *) exit 1 ;;
      esac
    '';
  };
in
pkgs.runCommand "checkmk-plugin-packages-test"
  {
    nativeBuildInputs = [
      plugins.smart-posix
      plugins.nut
    ];
  }
  ''
    env -i PATH=/nonexistent ${lib.getExe smart} > smart-output
    grep -Fx '<<<smart_posix_all:sep(0)>>>' smart-output
    grep -Fx '<<<smart_posix_scan_arg:sep(0)>>>' smart-output
    grep -Fx '{"smart_status":{"passed":true}}' smart-output

    env -i PATH=/nonexistent ${lib.getExe nut} > nut-output
    grep -Fx '<<<nut>>>' nut-output
    grep -Fx '==> testups <==' nut-output
    grep -Fx 'battery.charge: 100' nut-output
    grep -Fx 'ups.status: OL' nut-output

    env -i PATH=/nonexistent ${lib.getExe plugins.docker} --help > docker-help
    grep -F -- '--config-file' docker-help
    touch "$out"
  ''
