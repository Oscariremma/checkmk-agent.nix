{
  fetchurl,
  rpmextract,
  stdenv,
  makeWrapper,
  gzip,
  lib,
  # wether to pull from upstream or mon.zibint.hlrn.de
  useZibint ? true,
  # derivations for `plugins`:
  # All executables in PLUGINSDIR will simply be executed and their
  # ouput appended to the output of the agent. Plugins define their own
  # sections and must output headers with '<<<' and '>>>'
  plugins ? [ ],
  # derivations for `local`:
  # All executables in LOCALDIR will by executabled and their
  # output inserted into the section <<<local>>>. Please
  # refer to online documentation for details about local checks.
  local ? [ ],
  # deps for actual checkmk-agent script
  systemd, # section_systemd
  procps, # section_ps and mkjob
  util-linux, # section_df and check_mk_caching_agent (flock)
  gnugrep, # section_mem and many others
  perl, # section_fileinfo
  coreutils, # everything
  findutils, # postfix among others
  iproute2, # section_lnx_if and section_tcp
  # section_lnx_if
  lnxSupport ? true,
  ethtool,
  # section_multipathing
  multipathSupport ? false,
  multipath-tools,
  # section_checkmk
  gnused,
  python3,
  # encryption handlers
  encryptionSupport ? true,
  openssl,
  gawk,
  # optional stuff
  zfsSupport ? true,
  zfs,
  lvmSupport ? false,
  lvm2,
  ovsSupport ? false,
  openvswitch,
  chronySupport ? false,
  chrony,
  ipmiSupport ? false,
  ipmitool,
  freeipmi,
  dmraidSupport ? false,
  dmraid,
  megaraidSupport ? false,
  storcli,
  megacli,
  postfixSupport ? false,
  postfix,
  varnishSupport ? false,
  varnish,
  ntpdSupport ? false,
  ntp,
}:
let
  major = "2.3.0p26";
  patch = "-1";
  version = major + patch;

  # generate commands to copy all binaries from `packages` into `out`
  copyBinaries = (
    packages: out:
    lib.strings.concatMapStringsSep "\n" (p: ''cp ${lib.attrsets.getBin p}/* "${out}"'') packages
  );

  # equivalent of packages plugins/local scripts
  lib_dir = stdenv.mkDerivation {
    pname = "checkmk-agent-lib";
    inherit version;

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p "$out/plugins" "$out/local"
      ${copyBinaries plugins "$out/plugins"}
      ${copyBinaries local "$out/local"}
    '';
  };
in
stdenv.mkDerivation {
  pname = "checkmk-agent";
  inherit version;

  # fetch packaged agent, this allows us access to agent + systemd unit files in one archive
  src =
    if useZibint then
      fetchurl {
        url = "https://mon.zibint.hlrn.de/HPC/check_mk/agents/check-mk-agent-${version}.noarch.rpm";
        hash = "sha256-ZK86ZIRpvPru5hzYnJfXuOo9QyAffVKAdnyuWSj0w70=";
      }
    else
      # refer to https://checkmk.com/download?platform=cmk&distribution=redhat&release=el9&edition=cre
      fetchurl {
        url = "https://download.checkmk.com/checkmk/${major}/check-mk-raw-${major}-el9-38.x86_64.rpm";
        hash = "sha256-URRWQ4BQ+oOYvLcuKQ043cAjOYCcEL1f9khCcPuZ8UE=";
      };

  # remote builds are not recommended, we need zibint
  preferLocalBuild = useZibint;

  # we need dpkg for unpacking the debian version
  nativeBuildInputs = [
    rpmextract
    gzip
    makeWrapper
  ];

  dontBuild = true;

  # unpack rpm into distinct source root (`src`)
  unpackCmd =
    if useZibint then
      ''
        mkdir src
        cd src
        rpmextract $curSrc
        gunzip var/lib/cmk-agent/cmk-agent-ctl.gz
        cd ..
      ''
    else
      ''
        mkdir tmp
        cd tmp
        rpmextract $curSrc
        mv opt/omd/versions/${major}.cre/share/check_mk/agents/check-mk-agent-${version}.noarch.rpm ..
        cd ..
        rm -rf tmp

        mkdir src
        cd src
        rpmextract ../check-mk-agent-${version}.noarch.rpm
        gunzip var/lib/cmk-agent/cmk-agent-ctl.gz
        cd ..
      '';
  sourceRoot = "src";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/systemd/system
    cp usr/bin/* var/lib/cmk-agent/cmk-agent-ctl $out/bin
    chmod +x $out/bin/cmk-agent-ctl

    for cfg in var/lib/cmk-agent/scripts/super-server/0_systemd/*.{service,socket,fallback}; do
      substitute "$cfg" "$out/lib/systemd/system/$(basename $cfg)" \
        --replace /usr/bin/waitmax $out/bin/waitmax \
        --replace /usr/bin/check_mk_agent $out/bin/check_mk_agent \
        --replace /usr/bin/check_mk_caching_agent $out/bin/check_mk_caching_agent \
        --replace /usr/bin/cmk-agent-ctl $out/bin/cmk-agent-ctl \
        --replace /usr/bin/mk-job $out/bin/mk-job
    done

    runHook postInstall
  '';

  preFixup = ''
    wrapProgram $out/bin/cmk-agent-ctl \
      --set PATH $out/bin \
      --set MK_TMPDIR /tmp \
      --set MK_VARDIR /var/lib/check_mk_agent \
      --set MK_CONFDIR /etc/check_mk
    wrapProgram $out/bin/mk-job \
    --set PATH ${
      lib.makeBinPath [
        coreutils
        gnugrep
        procps
      ]
    }:$out/bin

    wrapProgram $out/bin/check_mk_caching_agent \
      --set PATH ${
        lib.makeBinPath [
          coreutils
          util-linux
        ]
      }:$out/bin
    wrapProgram $out/bin/check_mk_agent \
      --set MK_LIBDIR ${toString lib_dir} \
      --set MK_BIN $out \
      --set MK_CONFDIR /etc/check_mk \
      --set MK_VARDIR /var/lib/check_mk_agent \
      --set MK_TMPDIR /tmp \
      --set PATH ${
        lib.makeBinPath (
          [
            procps
            coreutils
            findutils
            perl
            systemd
            python3
            gnugrep
            gawk
            gnused
            util-linux
            iproute2
          ]
          ++ (lib.optionals encryptionSupport [ openssl ])
          ++ (lib.optionals ipmiSupport [
            ipmitool
            freeipmi
          ])
          ++ (lib.optionals ovsSupport [ openvswitch ])
          ++ (lib.optionals varnishSupport [ varnish ])
          ++ (lib.optionals postfixSupport [ postfix ])
          ++ (lib.optionals megaraidSupport [
            megacli
            storcli
          ])
          ++ (lib.optionals ntpdSupport [ ntp ])
          ++ (lib.optionals dmraidSupport [ dmraid ])
          ++ (lib.optionals lnxSupport [ ethtool ])
          ++ (lib.optionals lvmSupport [ lvm2 ])
          ++ (lib.optionals chronySupport [ chrony ])
          ++ (lib.optionals multipathSupport [ multipath-tools ])
          ++ (lib.optionals zfsSupport [ zfs ])
        )
      }:$out/bin
  '';

  meta = {
    description = "compat build of packaged checkmk agent";
    homepage = "https://mon.zibint.hlrn.de/HPC/check_mk";
    maintainers = [ lib.maintainers.cobalt ];
  };
}
