![nixpkgs version](https://img.shields.io/badge/nixpkgs-26.05-5277C3?logo=nixos)
![checkmk version](https://img.shields.io/badge/CheckMK-2.5.0p17-15D1A0?logo=checkmk)

# CheckMK agent

This flake provides a package for using the _packaged checkmk agent_ via Nix.
It supports most common checks and also has optional supports for advanced checks, like MegaRaid or OVS.

The provided outputs are:

- `packages.x86_64-linux.checkmk-agent`: nix package for checkmk agent, version `2.5.0p17`
- (wip) `nixosModules.default`: NixOS module for using checkmk-agent as service

The only supported platform is `x86_64-linux`.
It should also work on other platforms however we currently don't have any testing setup for this.

## Use with `mon.hlrn.de`

> A prerequisite is a priviledged user account on `mon.zibint.hlrn.de`.

1. Include the module and enable in your system config:

```nix
{
  inputs = {
    [... your inputs]
    cmk_agent = {
      url = "git+ssh://git@git.zib.de/hpc-s/checkmk-agent.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { ..., cmk_agent, ... }: {
      nixosConfigurations.your-system = nixpkgs.lib.nixosSystem {
          modules = [
            cmk_agent.nixosModules.default
            ({ ... }: {
              services.cmk_agent.enable = true;
            })
          ];
      };
  }
}
```

If you also want to use `cmk-agent-ctl`, add:

```nix
{ config, ... }: {
  environment.systemPackages = [ config.services.checkmk-agent.package ];
}
```

You should also open the TCP port `6556`, if you want to operate the agent in pull mode (this is what you usually want):

```nix
{ config, ... }: {
  networking.firewall.interfaces.<interface>.allowedTCPPorts = [ 6556 ];
}
```

2. Follow the steps in [the wiki after create host](https://wiki.zib.de/confluence/display/NHRADMIN/checkMK#checkMK-createhost).
   For example (for `adm`): `cmk-agent-ctl register --server mon.adm.hlrn.de --site HPC --user agent_registration --hostname $(hostname -f)`

[^1]: We use the raw edition, as such you cannot use `cmk-agent-ctl register-new`

## Plugins and local checks

Plugins and local checks can run synchronously or at a configured interval:

```nix
{ pkgs, ... }: {
  imports = [ cmk_agent.nixosModules.default ];

  services.checkmk-agent = {
    enable = true;
    plugins = [ myPlugin ];
    plugins-async = [
      { package = mySlowPlugin; interval = 300; }
    ];
    local = [
      (pkgs.writeShellScriptBin "example-local" ''
        echo '0 "Example" - Local check is working'
      '')
    ];
    local-async = [
      { package = mySlowLocalCheck; interval = 600; }
    ];
  };
}
```

Replace the `my*` values with your check packages. Each package contributes its
`lib.getExe` executable. Async intervals are positive integers in seconds.

The module configures the agent package with a Nix store directory containing
the selected checks. No plugin directories are created under `/var/lib`.

## Optional checks

The agent itself is a portable bash script.
It checks the `$PATH` at runtime for uncommon dependencies, like `postfix`, and, if found, evaluates them.
If a binary is not found it will skip the check.

This allows the nix derivation to offer opt-in checks for some services to reduce the derivation size for most installations.
Most common checks, like the systemd-based checks, are always included to make integration easier.

Feature flags are available under `services.checkmk-agent`. ZFS, LVM, multipath, Open vSwitch, Chrony, Postfix, Varnish, and ntpd monitoring default to the host's configured support or service state. 
Checks use the host's selected tool packages where configurable. LVM support is enabled by
default in NixOS, even on hosts without logical volumes.

Override any default explicitly, for example:

```nix
services.checkmk-agent.zfsSupport = false;
services.checkmk-agent.ipmiSupport = true;
```

The package-level options and their standalone defaults are:

- `lnxSupport` (default: `true`): state of network interfaces of Linux hosts
- `multipathSupport` (default: `false`): state of [multipathd](https://en.wikipedia.org/wiki/Linux_DM_Multipath)
- `encryptionSupport` (default: `true`): encryption of agent messages
- `zfsSupport` (default: `false`): monitoring of zpools and ZFS datasets
- (untested)`lvmSupport` (default: `false`): monitoring of lvm
- (untested)`ovsSupport` (default: `false`): monitor [openvswitch](https://www.openvswitch.org/)
- (untested)`chronySupport` (default: `false`): monitor [`chrony`](https://chrony-project.org/)
- `ipmiSupport` (default: `false`): monitor IPMI with `freeipmi` and `ipmitool`
- (untested)`dmraidSupport` (default: `false`): monitor [device-mapper RAID](https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/dm-raid.html)
- `megaraidSupport` (default: `false`): monitor MegaRaid with `storcli` and `megacli`
- `postfixSupport` (default: `true`): monitor [postfix](https://www.postfix.org/postqueue.1.html) mailqueues
- (untested)`varnishSupport` (default: `false`): monitor [varnish](https://varnish-cache.org/)
- (untested) `ntpdSupport` (default: `false`): monitor [ntpd](https://en.wikipedia.org/wiki/Ntpd)

_(untested)_: checks that have yet to be tested on a machine.
