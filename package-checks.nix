{
  lib,
  linkFarm,
  plugins ? [ ],
  plugins-async ? [ ],
  local ? [ ],
  local-async ? [ ],
}:
let
  executableName = p: p.meta.mainProgram or (lib.getName p);

  mkChecksDirectory =
    name: checks: asyncChecks:
    linkFarm name (
      map (p: {
        name = executableName p;
        path = lib.getExe p;
      }) checks
      ++ map (
        p:
        assert builtins.isInt p.interval && p.interval > 0;
        {
          name = "${toString p.interval}/${executableName p.package}";
          path = lib.getExe p.package;
        }
      ) asyncChecks
    );
in
linkFarm "checkmk-agent-lib" [
  {
    name = "plugins";
    path = mkChecksDirectory "checkmk-plugins" plugins plugins-async;
  }
  {
    name = "local";
    path = mkChecksDirectory "checkmk-local" local local-async;
  }
]
