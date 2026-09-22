# Release Procedure

Current release targets:

| Formula | Tag | Bottle tag |
| --- | --- | --- |
| `hpnssh-openssl` | `hpnssh-openssl-18.11.1-macos26-arm64` | `arm64_tahoe` |
| `hpnssh-awslc` | `hpnssh-awslc-18.11.1-macos26-arm64` | `arm64_tahoe` |

## Prerequisites

```sh
brew install bfs jaq ugrep uutils-coreutils
```

The build host must have a writable Homebrew Cellar and tap directory. Do
not change ownership of a managed Homebrew installation. Use an isolated
user-owned Homebrew staging prefix or an approved build host.

## 1. Validate the Tap

```sh
brew style Formula/hpnssh-openssl.rb Formula/hpnssh-awslc.rb
brew audit --strict cecilyen/hpnssh/hpnssh-openssl
brew audit --strict cecilyen/hpnssh/hpnssh-awslc
```

## 2. Build a Bottle

OpenSSL 3:

```sh
FORMULA=hpnssh-openssl \
RELEASE_TAG=hpnssh-openssl-18.11.1-macos26-arm64 \
scripts/build-bottle.sh
```

AWS-LC:

```sh
scripts/build-bottle.sh
```

The script builds with `brew install --build-bottle`, runs the formula test,
creates rebuild-0 bottle JSON and the `arm64_tahoe` archive, normalizes the
release filename, and merges the checksum into the formula.

## 3. Commit and Push

```sh
git add Formula README.md RELEASE.md scripts .gitignore
git commit -m "Publish HPN-SSH 18.11.1 OpenSSL bottle"
git push origin main
```

## 4. Upload Release Assets

```sh
FORMULA=hpnssh-openssl \
RELEASE_TAG=hpnssh-openssl-18.11.1-macos26-arm64 \
scripts/upload-release.sh
```

The uploader refuses to overwrite an existing release unless
`ALLOW_CLOBBER=1` is set explicitly.

## 5. Validate a Bottle Pour

```sh
brew uninstall hpnssh-openssl
brew update
brew install --force-bottle cecilyen/hpnssh/hpnssh-openssl
brew test cecilyen/hpnssh/hpnssh-openssl
hpnssh -V
```

Confirm that Homebrew downloads
`hpnssh-openssl-18.11.1.arm64_tahoe.bottle.tar.gz` from the GitHub release.

Do not upload host private keys, local SSH configuration, source trees,
build logs, or temporary Homebrew prefixes.
