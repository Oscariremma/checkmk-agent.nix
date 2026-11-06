{ pkgs, self }:
let
  inherit (pkgs) lib;
  plugins = self.legacyPackages.${pkgs.stdenv.hostPlatform.system}.checkmkAgentPlugins;
  configuredDocker = plugins.docker.override {
    baseUrl = "unix:///var/run/docker.sock";
    containerId = "name";
    skipSections = [
      "docker_node_disk_usage"
      "docker_node_images"
      "docker_node_network"
    ];
    persistPeriodNodeDiskUsage = 120;
  };
  nixos-lib = import (pkgs.path + "/nixos/lib") { };
in
(nixos-lib.runTest {
  hostPkgs = pkgs;
  defaults.documentation.enable = lib.mkDefault false;
  name = "checkmk-docker-plugin";
  nodes.server = { config, ... }: {
    imports = [ self.nixosModules.default ];
    virtualisation.docker.enable = true;
    services.checkmk-agent = {
      enable = true;
      plugins = [ configuredDocker ];
    };
    environment.systemPackages = [ config.services.checkmk-agent.package ];
  };
  testScript = ''
    import re

    start_all()
    server.wait_for_unit("docker.service")
    server.wait_for_unit("check-mk-agent.socket")
    server.wait_for_unit("cmk-agent-ctl-daemon.service")
    server.succeed("mkdir -p /tmp/docker-config; printf '[DOCKER]\\nbase_url=unix:///nonexistent.sock\\n' > /tmp/docker-config/docker.cfg")
    default_output = server.succeed("env -i PATH=/nonexistent MK_CONFDIR=/tmp/docker-config ${lib.getExe plugins.docker}")
    assert re.search(r"(?m)^<<<docker_node_info:sep\(124\)>>>$", default_output)
    assert re.search(r"(?m)^<<<docker_node_images:sep\(124\)>>>$", default_output)
    assert "MKDockerClient.__init__" not in default_output
    dump = server.succeed("cmk-agent-ctl dump")
    assert re.search(r"(?m)^<<<docker_node_info:sep\(124\)>>>$", dump)
    assert "MKDockerClient.__init__" not in dump
    for section in ["docker_node_disk_usage", "docker_node_images", "docker_node_network"]:
        assert not re.search(r"(?m)^<<<" + section + r"[:>]", dump)
  '';
}).config.result
