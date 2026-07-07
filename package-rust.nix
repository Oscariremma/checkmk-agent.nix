{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,

  # Derivations for `plugins`:
  # All executables in PLUGINSDIR will simply be executed and their
  # output appended to the output of the agent. Plugins define their own
  # sections and must output headers with '<<<' and '>>>'
  plugins ? [ ],

  # Derivations for `local`:
  # All executables in LOCALDIR will by executables and their
  # output inserted into the section <<<local>>>. Please
  # refer to online documentation for details about local checks.
  local ? [ ],

  systemd,
  procps,
  util-linux,
  gnugrep,
  perl,
  coreutils,
  findutils,
  iproute2,

  lnxSupport ? true,
  ethtool,

  multipathSupport ? false,
  multipath-tools,

  gnused,
  python3,
  encryptionSupport ? true,
  openssl,
  gawk,

  # optional stuff
  zfsSupport ? false,
  zfs,
  lvmSupport ? false,
  lvm2,
  ovsSupport ? false,
  openvswitch,
  chronySupport ? true,
  chrony,
  ipmiSupport ? false,
  ipmitool,
  freeipmi,
  dmraidSupport ? false,
  dmraid,
  megaraidSupport ? false,
  storcli,
  megacli,
  postfixSupport ? true,
  postfix,
  varnishSupport ? false,
  varnish,
  ntpdSupport ? false,
  ntp,
}:
let
  version = "2.5.0p4";
  src = fetchFromGitHub {
    owner = "Checkmk";
    repo = "checkmk";
    tag = "v${version}";
    hash = "sha256-mjyBwiuEboglxFi8OSBl0hw4ZnwDOtYO73APGm54zQI=";
  };

  # Generate commands to symlink all binaries from `packages` (toplevel as well as ones located in `bin`) into `out`
  linkBinaries =
    packages: out:
    lib.strings.concatMapStringsSep "\n" (
      p: ''ln -s ${lib.attrsets.getBin p}/{*,bin/*} "${out}"''
    ) packages;

  # Equivalent of packages plugins/local scripts
  lib_dir = stdenv.mkDerivation {
    pname = "checkmk-agent-lib";
    inherit version;

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p "$out/plugins" "$out/local"
      ${linkBinaries plugins "$out/plugins"}
      ${linkBinaries local "$out/local"}

    '';
  };

in
rustPlatform.buildRustPackage (finalAttrs: rec {
  pname = "checkmk-agent";
  inherit version src;

  sourceRoot = "${src.name}/requirements/rust/host";

  cargoHash = "sha256-BHRRp2ZVvD/+9ldaSyibDHn3Yxhco5ZgWpGaRjHSgOQ=";

  nativeBuildInputs = [
    pkg-config
    perl
    rustPlatform.bindgenHook
    makeWrapper
  ];

  buildInputs = [ openssl ];


  postInstall = ''
    mkdir -p $out/lib/systemd/system

    pushd ../../..

    for bin in agents/{*.linux,waitmax,mk-job}; do
        install -D -m 0555 "$bin" "$out/bin/$(basename $bin .linux)"
    done

    ${lib.strings.optionalString postfixSupport ''
      substituteInPlace "$out/bin/check_mk_agent" --replace-fail /usr/sbin/ssmtp ${postfix}
    ''}

    for cfg in agents/scripts/super-server/0_systemd/*.{service,socket,fallback}; do
      substitute "$cfg" "$out/lib/systemd/system/$(basename $cfg)" \
        --replace-quiet /usr/bin/waitmax $out/bin/waitmax \
        --replace-quiet /usr/bin/check_mk_agent $out/bin/check_mk_agent \
        --replace-quiet /usr/bin/check_mk_caching_agent $out/bin/check_mk_caching_agent \
        --replace-quiet /usr/bin/cmk-agent-ctl $out/bin/cmk-agent-ctl \
        --replace-quiet /usr/bin/mk-job $out/bin/mk-job
    done

    popd
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
          ++ lib.optional encryptionSupport openssl
          ++ lib.optionals ipmiSupport [
            ipmitool
            freeipmi
          ]
          ++ lib.optional ovsSupport openvswitch
          ++ lib.optional varnishSupport varnish
          ++ lib.optional postfixSupport postfix
          ++ lib.optionals megaraidSupport [
            megacli
            storcli
          ]
          ++ lib.optional ntpdSupport ntp
          ++ lib.optional dmraidSupport dmraid
          ++ lib.optional lnxSupport ethtool
          ++ lib.optional lvmSupport lvm2
          ++ lib.optional chronySupport chrony
          ++ lib.optional multipathSupport multipath-tools
          ++ lib.optional zfsSupport zfs
        )
      }:$out/bin
  '';

  doCheck = false;

  env = {
    OPENSSL_DIR = "${openssl.dev}";
    OPENSSL_LIB_DIR = "${openssl.out}/lib";
    OPENSSL_INCLUDE_DIR = "${openssl.dev}/include";
    PKG_CONFIG_ALLOW_CROSS = "1";
  };

  meta = {
    description = "Checkmk - Best-in-class infrastructure & application monitoring";
    homepage = "https://github.com/Checkmk/checkmk";
    changelog = "https://github.com/Checkmk/checkmk/blob/${finalAttrs.src.rev}/CHANGES";
    license = lib.licenses.gpl2;
    maintainers = with lib.maintainers; [ weriomat ];
    mainProgram = "cmk-agent-ctl";
  };
})
