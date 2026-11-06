# Release Procedure

Release targets:

| Formula | Tag | Bottle tag | Runtime crypto |
| --- | --- | --- | --- |
| `hpnssh-awslc` | `hpnssh-awslc-18.12.1-macos26-arm64` | `arm64_tahoe` | AWS-LC 5.12.0 |
| `hpnssh-openssl` | `hpnssh-openssl-18.12.1-macos26-arm64` | `arm64_tahoe` | OpenSSL 4.1.0 |

Both target macOS 26 or newer and Homebrew at `/opt/homebrew`. They conflict
with each other and Homebrew `openssh`.

## Package Existing Executables Without Recompiling

Use the project build directories containing the completed executables,
generated manual pages, configuration files, `Makefile`, and `config.h`.
Run from the tap directory:

```sh
work_dir=$(mktemp -d /private/tmp/hpn-bottle.XXXXXX)

ruby scripts/package-existing-bottle.rb \
  --formula hpnssh-awslc \
  --build-dir /path/to/completed-awslc-build/hpn-ssh \
  --work-dir "$work_dir" --dry-run

ruby scripts/package-existing-bottle.rb \
  --formula hpnssh-awslc \
  --build-dir /path/to/completed-awslc-build/hpn-ssh \
  --work-dir "$work_dir"
```

Repeat with `--formula hpnssh-openssl` and the completed OpenSSL build.
The script requires Ruby, pigz, macOS command-line tools, and the already
installed crypto dependency. It runs no compiler, configure, autoreconf,
make, dependency installation, or managed Homebrew installation.

It copies 14 executables, relocates compiled installation paths in the
copies, preserves string offsets with slash padding, and re-signs the
copies. Helper paths use `/opt/homebrew/share/hpnssh`, which Homebrew links
to the keg's `libexec` directory. Default configuration is stored under
`.bottle/etc/hpnssh` for Homebrew's configuration-preserving installation.
It refuses to overwrite an output directory or staging keg.

The archives include a standard Homebrew receipt and formula snapshot.
The receipt records `built_as_bottle: false` because these executables came
from existing source builds, rather than `brew install --build-bottle`.
The release JSON pins the supported Cellar to `/opt/homebrew/Cellar`;
arbitrary Homebrew prefixes are not claimed to work.

Each release directory contains:

- The `.arm64_tahoe.bottle.tar.gz` archive and bottle JSON.
- Formula snapshot with the new bottle SHA-256.
- `BUILD_PROVENANCE.json`: source and packaged executable hashes, unchanged
  `__TEXT,__text` hashes, build flags, dependencies, and sandbox setting.
- Packaging script, installation notes, and `SHA256SUMS`.

Copy the generated bottle checksum into the tap formula before publication.
The script verifies that all original executable hashes remain unchanged.

## Validate

Check both checksum manifests and formula syntax:

```sh
(cd dist/hpnssh-awslc-18.12.1-macos26-arm64 && shasum -a 256 -c SHA256SUMS)
(cd dist/hpnssh-openssl-18.12.1-macos26-arm64 && shasum -a 256 -c SHA256SUMS)
ruby -c Formula/hpnssh-awslc.rb
ruby -c Formula/hpnssh-openssl.rb
git diff --check
```

On an approved writable Homebrew installation, pour and test one variant
at a time. Review existing conflicting installations before switching.

```sh
brew install ./dist/hpnssh-awslc-18.12.1-macos26-arm64/hpnssh-awslc-18.12.1.arm64_tahoe.bottle.tar.gz
brew test cecilyen/hpnssh/hpnssh-awslc
hpnssh -V
```

The 18.12.1 existing builds report `SANDBOX_NULL`, not the Darwin
privilege-separation sandbox. Review this configuration before deploying
the server. No daemon is installed or started by this packaging workflow.

## Source Builds

`scripts/build-bottle.sh` remains available for an explicitly requested
source rebuild on an approved writable Homebrew host. It installs the
formula with `--build-bottle` and runs `brew bottle`. Do not run that script
when packaging existing executables only, or on a read-only managed Cellar.

## Publish

Commit the reviewed formula, script, and documentation changes, then push
the tap and upload each release when publication is authorized:

```sh
git push origin main
FORMULA=hpnssh-awslc scripts/upload-release.sh
FORMULA=hpnssh-openssl scripts/upload-release.sh
```

The uploader validates checksums and refuses to replace an existing release
unless `ALLOW_CLOBBER=1` is explicitly set. After upload, download both
release asset sets and verify their `SHA256SUMS` files.

Do not upload host private keys, local SSH configuration, source trees,
build logs, or temporary Homebrew prefixes.
