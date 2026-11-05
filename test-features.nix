{ pkgs, self }:
let
  inherit (pkgs) lib;
  probePackage = lib.makeOverridable (args: pkgs.hello // { featureArgs = args; }) { };

  evaluate =
    module: settings:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        module
        {
          services.checkmk-agent.package = probePackage;
          system.stateVersion = "26.05";
        }
        settings
      ];
    }).config.services.checkmk-agent.package.featureArgs;

  automaticFlags = [
    "zfsSupport"
    "lvmSupport"
    "multipathSupport"
    "ovsSupport"
    "chronySupport"
    "postfixSupport"
    "varnishSupport"
    "ntpdSupport"
  ];
  hardwareFlags = [
    "ipmiSupport"
    "dmraidSupport"
    "megaraidSupport"
  ];
  allFlags =
    automaticFlags
    ++ hardwareFlags
    ++ [
      "lnxSupport"
      "encryptionSupport"
    ];

  selected = {
    zfs = pkgs.zfs.overrideAttrs { pname = "test-zfs"; };
    lvm2 = pkgs.lvm2.overrideAttrs { pname = "test-lvm2"; };
    multipath-tools = pkgs.multipath-tools.overrideAttrs { pname = "test-multipath-tools"; };
    openvswitch = pkgs.openvswitch.overrideAttrs { pname = "test-openvswitch"; };
    chrony = pkgs.chrony.overrideAttrs { pname = "test-chrony"; };
    postfix = pkgs.postfix.overrideAttrs { pname = "test-postfix"; };
    varnish = pkgs.varnish.overrideAttrs { pname = "test-varnish"; };
  };

  host = {
    boot.supportedFilesystems.zfs = true;
    boot.zfs.package = selected.zfs;
    services = {
      lvm = {
        enable = true;
        package = selected.lvm2;
      };
      multipath = {
        enable = true;
        package = selected.multipath-tools;
      };
      chrony = {
        enable = true;
        package = selected.chrony;
      };
      postfix = {
        enable = true;
        package = selected.postfix;
      };
      varnish = {
        enable = true;
        package = selected.varnish;
      };
    };
    virtualisation.vswitch = {
      enable = true;
      package = selected.openvswitch;
    };
  };

  checkModule =
    module:
    let
      defaults = evaluate module { };
      enabled = evaluate module host;
      disabled = evaluate module {
        imports = [ host ];
        services.checkmk-agent = lib.genAttrs allFlags (_: false);
      };
      forced = evaluate module {
        services.lvm.enable = false;
        boot.initrd.services.lvm.enable = false;
        services.checkmk-agent = lib.genAttrs allFlags (_: true);
      };
      noLvm = evaluate module {
        services.lvm.enable = false;
        boot.initrd.services.lvm.enable = false;
      };
      initrdLvm = evaluate module {
        services.lvm.enable = false;
        boot.initrd.services.lvm.enable = true;
      };
      initrdZfs = evaluate module {
        boot.initrd.supportedFilesystems.zfs = true;
      };
      ntpd = evaluate module { services.ntp.enable = true; };
    in
    assert lib.assertMsg (
      defaults.lnxSupport && defaults.encryptionSupport && defaults.lvmSupport
    ) "Base checks and the default NixOS LVM support must be enabled";
    assert lib.assertMsg (lib.all (name: !defaults.${name}) (
      lib.remove "lvmSupport" automaticFlags ++ hardwareFlags
    )) "Unused services and hardware checks must be disabled";
    assert lib.assertMsg (lib.all (name: enabled.${name}) (
      lib.remove "ntpdSupport" automaticFlags
    )) "Configured host features must enable their checks";
    assert lib.assertMsg (lib.all (name: enabled.${name} == selected.${name}) (
      builtins.attrNames selected
    )) "Checks must use the host's selected packages";
    assert lib.assertMsg (lib.all (
      name: !disabled.${name}
    ) allFlags) "Explicitly disabling a check must override automatic defaults";
    assert lib.assertMsg (
      !(disabled ? zfs) && !(disabled ? lvm2) && !(disabled ? postfix)
    ) "Disabled checks must not select host tool packages";
    assert lib.assertMsg (lib.all (
      name: forced.${name}
    ) allFlags) "Explicitly enabling a check must work without its host service";
    assert lib.assertMsg (
      !noLvm.lvmSupport && initrdLvm.lvmSupport && initrdZfs.zfsSupport && ntpd.ntpdSupport
    ) "Initrd support and ntpd configuration must be detected";
    true;
in
assert checkModule self.nixosModules.default;
pkgs.runCommand "checkmk-feature-options-test" { } ''
  touch "$out"
''
