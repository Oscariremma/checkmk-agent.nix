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
    # import systemd units from package
    systemd.packages = [ cfg.package ];

    # setup dirs for data
    systemd.tmpfiles.settings."10-checkmk" =
      let
        cfg = {
          group = "cmk-agent";
          user = "cmk-agent";
          mode = 700;
        };
      in
      {
        "/var/lib/check_mk_agent".d = cfg;
        "/var/lib/check_mk_agent/spool".d = cfg;
        "/etc/check_mk".d = cfg;
      };

    # create mandatory user
    users.users.cmk-agent = {
      packages = [ cfg.package ];
      isSystemUser = true;
      group = "cmk-agent";
    };
    users.groups.cmk-agent = { };

    # create unit instance
    systemd.services."check-mk-agent@main".enable = true;
  };
}
