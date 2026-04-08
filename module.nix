{ package }:
{ config, lib, ... }:
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
    # create mandatory user
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
      # import systemd units from package
      packages = [ cfg.package ];

      # setup dirs for data
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

      # NOTE: the units still need to be enabled + installed
      services = {
        # socket activated template
        "check-mk-agent@".enable = true;
        # main cmk-agent-ctl daemon service
        cmk-agent-ctl-daemon = {
          enable = true;
          wantedBy = [ "multi-user.target" ];
        };
      };
      # socket for check-mk-agent@
      sockets.check-mk-agent = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
