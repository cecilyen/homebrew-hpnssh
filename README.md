# Homebrew HPN-SSH for macOS

This tap distributes HPN-SSH 18.11.1 for Apple Silicon Macs running macOS 26
Tahoe. Both formulas build the official `rapier1/hpn-ssh` source and provide
an `arm64_tahoe` bottle.

| Formula | Crypto library | HPN multithreaded crypto |
| --- | --- | --- |
| `hpnssh-openssl` | Homebrew `openssl@3` | AES-CTR provider and `chacha20-poly1305-mt@hpnssh.org` enabled |
| `hpnssh-awslc` | Homebrew `aws-lc` | Disabled because AWS-LC lacks the required legacy OpenSSL APIs |

The formulas install the same command names and cannot be linked together.
Install one variant at a time.

## Install

OpenSSL 3 build:

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-openssl
hpnssh -V
```

Expected version family:

```text
OpenSSH_10.5p1_hpn18.11.1, OpenSSL 3.x
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
- Homebrew `openssl@3` for `hpnssh-openssl`, or Homebrew `aws-lc` for
  `hpnssh-awslc`. Homebrew installs the selected dependency automatically.

zlib, libedit, PAM, and Kerberos come from macOS. They are not Homebrew
runtime dependencies. Neither formula uses BSM audit support.

## Configuration

- Client configuration: `/opt/homebrew/etc/hpnssh/ssh_config`
- Server configuration: `/opt/homebrew/etc/hpnssh/sshd_config`
- Global known-host files: `/opt/homebrew/etc/hpnssh/ssh_known_hosts{,2}`
- Default client and server port: `22`

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
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

They run `autoreconf -fi`, use macOS zlib and libedit, enable PAM and Apple
Kerberos, and set port 22. Installed Mach-O executables are stripped and
ad-hoc signed.

## Crypto Compatibility

The OpenSSL formula retains HPN-SSH's custom multithreaded AES-CTR provider
and ChaCha20-Poly1305-MT implementation. The AWS-LC formula disables those
extensions because AWS-LC does not provide the legacy APIs they require.
Standard AES-CTR, AES-GCM, and `chacha20-poly1305@openssh.com` remain
available in both builds.

## Verify

```sh
hpnssh -V
hpnssh -F /dev/null -G localhost | grep '^port '
otool -L "$(command -v hpnssh)"
brew test hpnssh-openssl
```

For the OpenSSL bottle, expected libraries include
`/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib`,
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
