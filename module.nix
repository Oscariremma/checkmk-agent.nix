{ package }:
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.services.cmk_agent;
in
{
  options.services.cmk_agent = {
    enable = lib.mkEnableOption "checkmk agent";
    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "agent derivation";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.packages = [ cfg.package ];
  };
}
