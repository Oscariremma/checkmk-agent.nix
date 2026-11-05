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

  cfg = config.services.checkmk-agent;
  feature =
    description: default: defaultText:
    lib.mkOption {
      type = lib.types.bool;
      inherit description default;
      defaultText = lib.literalExpression defaultText;
    };

  features = {
    lnxSupport = feature "Enable Linux network interface monitoring." true "true";
    encryptionSupport = feature "Enable agent output encryption." true "true";
    zfsSupport = feature "Enable ZFS monitoring." config.boot.zfs.enabled "config.boot.zfs.enabled";
    lvmSupport = feature "Enable LVM monitoring." (
      config.services.lvm.enable || config.boot.initrd.services.lvm.enable
    ) "config.services.lvm.enable || config.boot.initrd.services.lvm.enable";
    multipathSupport =
      feature "Enable multipath monitoring." config.services.multipath.enable
        "config.services.multipath.enable";
    ovsSupport =
      feature "Enable Open vSwitch monitoring." config.virtualisation.vswitch.enable
        "config.virtualisation.vswitch.enable";
    chronySupport =
      feature "Enable Chrony monitoring." config.services.chrony.enable
        "config.services.chrony.enable";
    postfixSupport =
      feature "Enable Postfix monitoring." config.services.postfix.enable
        "config.services.postfix.enable";
    varnishSupport =
      feature "Enable Varnish monitoring." config.services.varnish.enable
        "config.services.varnish.enable";
    ntpdSupport =
      feature "Enable ntpd monitoring." config.services.ntp.enable
        "config.services.ntp.enable";
    ipmiSupport = feature "Enable IPMI monitoring." false "false";
    dmraidSupport = feature "Enable dmraid monitoring." false "false";
    megaraidSupport = feature "Enable MegaRAID monitoring." false "false";
  };

  packageArgs =
    lib.genAttrs (builtins.attrNames features) (name: cfg.${name})
    // lib.optionalAttrs (cfg.zfsSupport && config.boot.zfs.enabled) {
      zfs = config.boot.zfs.package;
    }
    //
      lib.optionalAttrs
        (cfg.lvmSupport && (config.services.lvm.enable || config.boot.initrd.services.lvm.enable))
        {
          lvm2 = config.services.lvm.package;
        }
    // lib.optionalAttrs (cfg.multipathSupport && config.services.multipath.enable) {
      multipath-tools = config.services.multipath.package;
    }
    // lib.optionalAttrs (cfg.ovsSupport && config.virtualisation.vswitch.enable) {
      openvswitch = config.virtualisation.vswitch.package;
    }
    // lib.optionalAttrs (cfg.chronySupport && config.services.chrony.enable) {
      chrony = config.services.chrony.package;
    }
    // lib.optionalAttrs (cfg.postfixSupport && config.services.postfix.enable) {
      postfix = config.services.postfix.package;
    }
    // lib.optionalAttrs (cfg.varnishSupport && config.services.varnish.enable) {
      varnish = config.services.varnish.package;
    };
in
{
  options.services.checkmk-agent = features // {
    enable = lib.mkEnableOption "checkmk agent";
    asyncLoopInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "Interval in seconds between asynchronous agent passes.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      apply =
        p:
        p.override (
          previous:
          packageArgs
          // {
            plugins = (previous.plugins or [ ]) ++ cfg.plugins;
            plugins-async = (previous.plugins-async or [ ]) ++ cfg.plugins-async;
            local = (previous.local or [ ]) ++ cfg.local;
            local-async = (previous.local-async or [ ]) ++ cfg.local-async;
          }
        );
      description = "Agent package configured with the selected checks and features.";
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
    warnings =
      lib.optional
        (lib.any (interval: interval < cfg.asyncLoopInterval) (
          cfg.package.agentLibDir.asyncCheckIntervals or [ ]
        ))
        "Some asynchronous Checkmk check intervals are shorter than services.checkmk-agent.asyncLoopInterval (${toString cfg.asyncLoopInterval} seconds). Their caches can only refresh when the daemon runs.";

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
        };
      };

      services = {
        "check-mk-agent@".enable = true;
        check-mk-agent-async = {
          enable = true;
          wantedBy = [ "multi-user.target" ];
          environment.MK_LOOP_INTERVAL = toString cfg.asyncLoopInterval;
        };
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
