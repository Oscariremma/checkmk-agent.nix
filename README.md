![nixpkgs version](https://img.shields.io/badge/nixpkgs-26.05-5277C3?logo=nixos)
![Checkmk version](https://img.shields.io/badge/CheckMK-2.5.0p17-15D1A0?logo=checkmk)

# Checkmk agent for NixOS

A Nix flake that builds the Checkmk agent and its Rust controller from source,
with a NixOS service module, plugins, and local checks. Currently supports
`x86_64-linux`.

## Usage

Add the flake to your NixOS configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    checkmk-agent = {
      url = "github:Oscariremma/checkmk-agent.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, checkmk-agent, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        checkmk-agent.nixosModules.default
        ({ config, ... }: {
          services.checkmk-agent.enable = true;
          environment.systemPackages = [ config.services.checkmk-agent.package ];
        })
      ];
    };
  };
}
```

For pull mode, allow incoming TCP connections on port `6556`.
Add either an interface-specific rule or a rule for all interfaces.

On a specific interface:

```nix
networking.firewall.interfaces."eth0".allowedTCPPorts = [ 6556 ];
```

Replace `eth0` with the monitored host's interface facing your Checkmk server.

Or on all interfaces:

```nix
networking.firewall.allowedTCPPorts = [ 6556 ];
```

Register the agent with your Checkmk server using `cmk-agent-ctl register`;
see the [Linux agent documentation](https://docs.checkmk.com/latest/en/agent_linux.html).

The standalone package is available as `packages.x86_64-linux.checkmk-agent`
and as the default package.

## Plugins and local checks

Use `plugins` and `local` for synchronous checks, or `plugins-async` and
`local-async` for cached asynchronous checks. For example:

```nix
{ pkgs, ... }: {
  services.checkmk-agent.local-async = [
    {
      interval = 300;
      package = pkgs.writeShellScriptBin "example-local" ''
        echo '0 "Example" - Local check is working'
      '';
    }
  ];
}
```

Async intervals are positive integers in seconds; the daemon loop
is controlled by `services.checkmk-agent.asyncLoopInterval` (default: `60`). A
warning is emitted when a check interval is shorter than the daemon loop.

### Included plugin packages

Plugins are available under `legacyPackages.x86_64-linux.checkmkAgentPlugins`.

| Plugin                        | Monitoring                        |
| ----------------------------- | --------------------------------- |
| [`smart-posix`](#smart-posix) | Disk SMART data via smartmontools |
| [`docker`](#docker)           | Docker hosts and containers       |
| [`nut`](#nut)                 | UPS data via Network UPS Tools    |

For example, add this to the `modules` list in the flake above:

```nix
let
  plugins = checkmk-agent.legacyPackages.x86_64-linux.checkmkAgentPlugins;
in {
  services.checkmk-agent.plugins = [ plugins.nut ];
  services.checkmk-agent.plugins-async = [
    { package = plugins.smart-posix; interval = 300; }
    {
      interval = 300;
      package = plugins.docker.override {
        containerId = "name";
        skipSections = [ "docker_node_images" "docker_container_agent" ];
      };
    }
  ];
}
```

#### SMART POSIX

Collects disk health and SMART data using smartmontools. Needs access to the monitored disk devices.

#### Docker

Monitors Docker hosts and containers, including container status, resource usage,
and image inventory. Container data is sent as piggyback data for separate
container hosts in Checkmk. Requires access to the Docker API, usually through
the local Docker socket.

Docker accepts the following package overrides, matching the
[upstream configuration](https://github.com/Checkmk/checkmk/blob/v2.5.0p17/agents/cfg_examples/docker.cfg):

| Argument                     | Default                        | Purpose                                                           |
| ---------------------------- | ------------------------------ | ----------------------------------------------------------------- |
| `baseUrl`                    | `"unix://var/run/docker.sock"` | Docker API endpoint                                               |
| `containerId`                | `"short"`                      | Piggyback host identifier: `short`, `long`, `name`, or `combined` |
| `skipSections`               | `[ ]`                          | List of section names to omit                                     |
| `persistPeriodNodeDiskUsage` | `90`                           | Seconds to retain disk usage data as a fallback                   |

#### NUT

Monitors UPS status, battery charge, runtime, and other measurements through
Network UPS Tools. Discovers NUT servers from `/etc/nut/upsmon.conf` and also queries localhost.
Its [server-side extension](https://github.com/virus2500/checkmk_nut) is **required** to provide the parser and service checks for the agent's `nut` section and must be installed on your Checkmk server.

## Optional features

Monitoring for ZFS, LVM, multipath, Open vSwitch, Chrony, Postfix, Varnish, and ntpd
defaults to the host's configured support or services. LVM support is enabled by
default in NixOS, even without logical volumes. IPMI, dmraid, and MegaRAID are
opt-in. Override feature defaults through the service:

```nix
services.checkmk-agent.zfsSupport = false;
services.checkmk-agent.ipmiSupport = true;
```

See [module.nix](module.nix) for the available service options.

## Development

CI checks formatting, lint, the package build, and NixOS VM tests. To run these
locally, with KVM available:

```console
nix develop -c nixfmt --check ./*.nix ./plugins/*.nix
nix develop -c deadnix --fail .
nix develop -c statix check .
nix build --no-link -L .#checkmk-agent
nix flake check -L
```

## Credits

Forked from [ZIB's checkmk-agent.nix](https://git.zib.de/hpc-s-public/checkmk-agent.nix).
