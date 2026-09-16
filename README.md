# Homebrew HPN-SSH with AWS-LC

This tap distributes HPN-SSH 18.11.0 for Apple Silicon Macs running macOS 26
Tahoe. The formula builds the official `rapier1/hpn-ssh` source with AWS-LC
and provides an `arm64_tahoe` bottle.

## Install

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
hpnssh -V
```

Expected version output:

```text
OpenSSH_10.5p1_hpn18.11.0, AWS-LC 5.9.0
```

The commands retain the upstream HPN names: `hpnssh`, `hpnsshd`, `hpnscp`,
`hpnsftp`, and the related helpers. They do not replace the macOS
`/usr/bin/ssh` or `/usr/sbin/sshd` binaries.

## Runtime Requirements

- Apple Silicon Mac using the ARM64 Homebrew prefix `/opt/homebrew`.
- macOS 26 Tahoe or newer.
- Homebrew `aws-lc`. Homebrew installs it automatically with the bottle.

zlib, libedit, PAM, and Kerberos come from macOS. They are not Homebrew runtime
dependencies. The formula does not use BSM audit support.

## Configuration

- Client configuration: `/opt/homebrew/etc/hpnssh/ssh_config`
- Server configuration: `/opt/homebrew/etc/hpnssh/sshd_config`
- Global known-host files: `/opt/homebrew/etc/hpnssh/ssh_known_hosts{,2}`
- Default client and server port: `22`

The bottle does not contain SSH host private keys and does not install or start
a launch daemon. Generate and protect host keys separately before deploying
`hpnsshd`.

## Build From Source

```sh
brew install --build-from-source cecilyen/hpnssh/hpnssh-awslc
```

The source build uses Homebrew LLVM and:

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

It runs `autoreconf -fi`, links Homebrew AWS-LC, and links the macOS SDK
versions of zlib and libedit plus Apple's Kerberos framework. Executables are
stripped and ad-hoc signed after the build.

## AWS-LC Compatibility

AWS-LC does not provide the legacy OpenSSL APIs used by HPN-SSH's custom
AES-CTR-MT and ChaCha20-Poly1305-MT paths. The formula disables those two HPN
extensions. Standard AES-CTR, AES-GCM, and
`chacha20-poly1305@openssh.com` remain available through supported code paths.

## Verify

```sh
hpnssh -V
hpnssh -F /dev/null -G localhost | grep '^port '
otool -L "$(command -v hpnssh)"
brew test hpnssh-awslc
```

The expected dynamic libraries include
`/opt/homebrew/opt/aws-lc/lib/libcrypto.dylib`,
`/usr/lib/libz.1.dylib`, and Apple's Kerberos framework. `hpnsftp` also
links `/usr/lib/libedit.3.dylib`.

## Uninstall

```sh
brew uninstall hpnssh-awslc
brew untap cecilyen/hpnssh
```

Homebrew preserves modified configuration files as appropriate; review
`/opt/homebrew/etc/hpnssh` separately if complete removal is required.

## Upstream

- [HPN-SSH](https://github.com/rapier1/hpn-ssh)
- [AWS-LC](https://github.com/aws/aws-lc)
- [Homebrew bottle documentation](https://docs.brew.sh/Bottles)
