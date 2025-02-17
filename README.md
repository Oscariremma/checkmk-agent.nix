![nixpkgs version](https://img.shields.io/badge/nixpkgs-24.11-blue?logo=nixos)

# CheckMK agent

This flake provides a package for using the _packaged checkmk agent_ via Nix.
It supports most common checks and also has optional supports for advanced checks, like MegaRaid or OVS.

The provided outputs are:

- `packages.x86_64-linux.checkmk-agent`: nix package for checkmk agent, at the time of writing for version `2.3.0p26`
- (wip) `nixosModules.default`: NixOS module for using checkmk-agent as service

The only supported platform is `x86_64-linux`.
It should also work on other platforms however we currently don't have any testing setup for this.

## Optional checks

The agent itself is a portable bash script.
It checks the `$PATH` at runtime for uncommon dependencies, like `postfix`, and, if found, evaluates them.
If a binary is not found it will skip the check.

This allows the nix derivation to offer opt-in checks for some services to reduce the derivation size for most installations.
Most common checks, like the systemd-based checks, are always included to make integration easier.

The supported options are:

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
- `postfixSupport` (default: `false`): monitor [postfix](https://www.postfix.org/postqueue.1.html) mailqueues
- (untested)`varnishSupport` (default: `false`): monitor [varnish](https://varnish-cache.org/)
- (untested) `ntpdSupport` (default: `false`): monitor [ntpd](https://en.wikipedia.org/wiki/Ntpd)

_(untested)_: checks that have yet to be tested on a machine.
