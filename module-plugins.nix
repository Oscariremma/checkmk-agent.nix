{ package }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  dirPerm = {
    group = "cmk-agent";
    user = "cmk-agent";
    mode = "700";
  };

  linkEntry =
    pkg:
    dirPerm
    // {
      argument = lib.getExe pkg;
    };

  name = p: p.meta.mainProgram or p.name;

  cfg = config.services.checkmk-agent;
in
{
  options.services.checkmk-agent = {
    enable = lib.mkEnableOption "checkmk agent";
    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "agent derivation";
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;

      default = [ ];

      example = [
        (pkgs.writeShellApplication {
          name = "netstat";
          runtimeInputs = [ pkgs.unixtools.netstat ];
          text = builtins.readFile "${config.services.checkmk-agent.package.src}/agents/plugins/netstat.linux";
          bashOptions = [ "errexit" ];
        })
      ];

      description = ''
        A list of plugins for the Checkmk agent.
        For more information on plugins, see the [official documentation].

        [official documentation]: https://docs.checkmk.com/latest/en/devel_check_plugins.html
      '';
    };

    plugins-async = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            interval = lib.mkOption {
              type = lib.types.ints.positive;
              description = ''
                Interval (in seconds) at which this plugin is executed.
              '';
            };

            package = lib.mkOption {
              type = lib.types.package;
              description = ''
                The plugin package to install and run.
              '';
            };
          };
        }
      );

      default = [ ];

      example = [
        {
          interval = 600;
          package = pkgs.writeShellApplication {
            name = "netstat";
            runtimeInputs = [ pkgs.unixtools.netstat ];
            text = builtins.readFile "${config.services.checkmk-agent.package.src}/agents/plugins/netstat.linux";
            bashOptions = [ "errexit" ];
          };
        }
      ];

      description = ''
        A list of asynchronous plugins.
        For more information on asynchronous plugins execution, see the [official documentation].

        [official documentation]: https://docs.checkmk.com/latest/en/agent_linux.html#async_plugins
      '';
    };

    local = lib.mkOption {
      type = lib.types.listOf lib.types.package;

      default = [ ];

      description = ''
        A list of local checks for the Checkmk agent.
        For more information on local checks and an example, see the [official documentation].

        [official documentation]: https://docs.checkmk.com/latest/en/localchecks.html
      '';
    };

    local-async = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            interval = lib.mkOption {
              type = lib.types.ints.positive;
              description = ''
                Interval (in seconds) at which this local check is executed.
              '';
            };
            package = lib.mkOption {
              type = lib.types.package;
              description = ''
                The local check package to install and run.
              '';
            };
          };
        }
      );

      default = [ ];

      description = ''
        A list of local asynchronous checks.
        For more information on asynchronous execution and an example, see the [official documentation].

        [official documentation]: https://docs.checkmk.com/latest/en/localchecks.html#cache
      '';
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

      tmpfiles.settings = {
        "10-checkmk" = {
          "/etc/check_mk".d = dirPerm;
          "/var/log/check_mk_agent".d = dirPerm;
          "/var/lib/check_mk_agent".d = dirPerm;
          "/var/lib/check_mk_agent/spool".d = dirPerm;
          "/var/lib/check_mk_agent/lib".d = dirPerm;
          "/var/lib/check_mk_agent/lib/plugins".d = dirPerm;
          "/var/lib/check_mk_agent/lib/local".d = dirPerm;
        };
        "20-checkmk-plugins" = builtins.listToAttrs (
          map (p: {
            name = "/var/lib/check_mk_agent/lib/plugins/${name p}";
            value."L+" = linkEntry p;
          }) cfg.plugins
        );
        "20-checkmk-plugins-async" = builtins.listToAttrs (
          map (p: {
            name = "/var/lib/check_mk_agent/lib/plugins/${toString p.interval}/${name p.package}";
            value."L+" = linkEntry p.package;
          }) cfg.plugins-async
        );
        "20-checkmk-local" = builtins.listToAttrs (
          map (p: {
            name = "/var/lib/check_mk_agent/lib/local/${name p}";
            value."L+" = linkEntry p;
          }) cfg.plugins
        );
        "20-checkmk-local-async" = builtins.listToAttrs (
          map (p: {
            name = "/var/lib/check_mk_agent/lib/local/${toString p.interval}/${name p.package}";
            value."L+" = linkEntry p.package;
          }) cfg.plugins-async
        );
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
