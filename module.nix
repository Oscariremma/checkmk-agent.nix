{ package }:
{ config, lib, ... }:
let
  cfg = config.services.checkmk_agent;
in
{
  options.services.checkmk-agent = {
    enable = lib.mkEnableOption "checkmk agent";
    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "agent derivation";
    };
  };

  config = lib.mkIf cfg.enable {
    users = {
      users.cmk-agent = {
        packages = [ cfg.package ];
        isSystemUser = true;
        home = "/var/lib/check_mk_agent";
        group = "cmk-agent";
      };
      groups.cmk-agent = { };
    };

    systemd = {
      packages = [ cfg.package ];

      tmpfiles.settings."10-checkmk" =
        let
          cfg = {
            group = "cmk-agent";
            user = "cmk-agent";
            mode = "700";
          };
        in
        {
          "/var/lib/check_mk_agent".d = cfg;
          "/var/lib/check_mk_agent/spool".d = cfg;
          "/etc/check_mk".d = cfg;
        };

      services = {
        "check-mk-agent@".enable = true;
        cmk-agent-ctl-daemon = {
          enable = true;
          wantedBy = [ "multi-user.target" ];
        };
      };
      sockets.check-mk-agent = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
