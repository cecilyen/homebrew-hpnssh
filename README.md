# Homebrew HPN-SSH for macOS

This tap distributes HPN-SSH 18.12.1 for Apple Silicon Macs running macOS 26
Tahoe. Both formulas build the official `rapier1/hpn-ssh` source and provide
an `arm64_tahoe` bottle.

| Formula | Crypto library | HPN multithreaded crypto |
| --- | --- | --- |
| `hpnssh-openssl` | Homebrew `openssl@4` (validated with 4.1.0) | AES-CTR provider and `chacha20-poly1305-mt@hpnssh.org` enabled |
| `hpnssh-awslc` | Homebrew `aws-lc` (validated with 5.12.0) | Disabled because AWS-LC lacks the required legacy OpenSSL APIs |

The formulas conflict with each other and with Homebrew `openssh`.
Install one variant at a time. Apple's system SSH remains available.

Release assets:

- [AWS-LC bottle](https://github.com/cecilyen/homebrew-hpnssh/releases/tag/hpnssh-awslc-18.12.1-macos26-arm64)
- [OpenSSL bottle](https://github.com/cecilyen/homebrew-hpnssh/releases/tag/hpnssh-openssl-18.12.1-macos26-arm64)

## Install

OpenSSL build:

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-openssl
hpnssh -V
```

Expected version family:

```text
OpenSSH_10.6p2_hpn18.12.1, OpenSSL 4.1.0 23 Oct 2026
```

AWS-LC build:

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
hpnssh -V
```

The commands retain the upstream HPN names: `hpnssh`, `hpnsshd`, `hpnscp`,
`hpnsftp`, and the related helpers. They do not replace macOS
`/usr/bin/ssh` or `/usr/sbin/sshd`.

## Runtime Requirements

- Apple Silicon Mac using the ARM64 Homebrew prefix `/opt/homebrew`.
- macOS 26 Tahoe or newer.
- Homebrew `openssl@4` for `hpnssh-openssl`, or Homebrew `aws-lc` for
  `hpnssh-awslc`. Homebrew installs the selected dependency automatically.

zlib, libedit, PAM, and Kerberos come from macOS. They are not Homebrew
runtime dependencies. Neither formula uses BSM audit support.

## Configuration

- Client configuration: `/opt/homebrew/etc/hpnssh/ssh_config`
- Server configuration: `/opt/homebrew/etc/hpnssh/sshd_config`
- Global known-host files: `/opt/homebrew/etc/hpnssh/ssh_known_hosts{,2}`
- Default client and server port: `22`
- Helper alias used by the prebuilt bottles: `/opt/homebrew/share/hpnssh`

The bottles contain no SSH host private keys and install no launch daemon.
Generate and protect host keys separately before deploying `hpnsshd`.

## Build From Source

```sh
brew install --build-from-source cecilyen/hpnssh/hpnssh-openssl
# or
brew install --build-from-source cecilyen/hpnssh/hpnssh-awslc
```

Both formulas use Homebrew LLVM and:

```sh
CFLAGS="-O3 -arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -pipe"
LDFLAGS="-arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -Wl,-dead_strip"
```

They run `autoreconf -fi`, use macOS zlib and libedit, enable PAM and Apple
Kerberos, and set port 22. Installed Mach-O executables are stripped and
ad-hoc signed.

The 18.12.1 bottles were packaged from existing, already stripped source
builds without recompilation. Packaging changes embedded installation
paths in copies and re-signs those copies. Each release includes
`BUILD_PROVENANCE.json` with original and packaged hashes, unchanged
machine-code hashes, build flags, dependencies, and sandbox status. The
original executables are preserved. See [Release Procedure](RELEASE.md).

## Crypto Compatibility

The OpenSSL formula retains HPN-SSH's custom multithreaded AES-CTR provider
and ChaCha20-Poly1305-MT implementation. The AWS-LC formula disables those
extensions because AWS-LC does not provide the legacy APIs they require.
Standard AES-CTR, AES-GCM, and `chacha20-poly1305@openssh.com` remain
available in both builds.

The existing 18.12.1 builds report no Darwin privilege-separation sandbox
(`SANDBOX_NULL`), following their SDK 27 compatibility configuration. This
packaging preserves that setting. Review it before deploying `hpnsshd`;
client verification does not establish daemon deployment approval.

## Verify

```sh
hpnssh -V
hpnssh -F /dev/null -G localhost | grep '^port '
otool -L "$(command -v hpnssh)"
brew test hpnssh-openssl
```

For the OpenSSL bottle, expected libraries include
`/opt/homebrew/opt/openssl@4/lib/libcrypto.4.dylib`,
`/usr/lib/libz.1.dylib`, and Apple's Kerberos framework. `hpnsftp` also
links `/usr/lib/libedit.3.dylib`. Replace the final test command with
`brew test hpnssh-awslc` for the AWS-LC variant.

## Switch or Uninstall

```sh
brew uninstall hpnssh-openssl
brew install hpnssh-awslc
```

To remove the tap:

```sh
brew uninstall hpnssh-openssl hpnssh-awslc
brew untap cecilyen/hpnssh
```

Homebrew preserves modified configuration files as appropriate. Review
`/opt/homebrew/etc/hpnssh` separately if complete removal is required.

## Upstream

- [HPN-SSH](https://github.com/rapier1/hpn-ssh)
- [OpenSSL](https://www.openssl.org/)
- [AWS-LC](https://github.com/aws/aws-lc)
- [Homebrew bottle documentation](https://docs.brew.sh/Bottles)
