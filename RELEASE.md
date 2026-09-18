# Release Procedure

The release target is:

- Tap: `cecilyen/hpnssh`
- Repository: `cecilyen/homebrew-hpnssh`
- Tag: `hpnssh-awslc-18.11.1-macos26-arm64`
- Bottle tag: `arm64_tahoe`

## Prerequisites

```sh
brew install bfs jaq ugrep uutils-coreutils
```

The build host must own or be able to write its Homebrew Cellar and tap
directory. Do not change ownership of a managed or organization-controlled
Homebrew installation. Use an approved build host or ask the administrator to
run the build when those paths are not writable.

## 1. Validate the Tap

```sh
brew style Formula/hpnssh-awslc.rb
brew audit --strict cecilyen/hpnssh/hpnssh-awslc
```

Add `--online` after the GitHub repository exists.

## 2. Build the Bottle

```sh
scripts/build-bottle.sh
```

The script builds with `brew install --build-bottle`, runs the formula test,
creates rebuild-0 bottle JSON and the `arm64_tahoe` tarball, normalizes the
release asset filename expected by Homebrew, and merges the checksum into the
formula.

## 3. Commit and Push the Bottle Block

```sh
git add Formula/hpnssh-awslc.rb README.md RELEASE.md scripts .gitignore
git commit -m "Publish HPN-SSH 18.11.1 AWS-LC bottle"
git push origin main
```

## 4. Upload Release Assets

```sh
scripts/upload-release.sh
```

The release contains the bottle, bottle JSON, formula snapshot, release notes,
and `SHA256SUMS`.

## 5. Validate a Bottle Pour

```sh
brew uninstall hpnssh-awslc
brew update
brew install --force-bottle cecilyen/hpnssh/hpnssh-awslc
brew test cecilyen/hpnssh/hpnssh-awslc
hpnssh -V
```

Confirm that the install downloads
`hpnssh-awslc-18.11.1.arm64_tahoe.bottle.tar.gz` from the GitHub release.

Do not upload host private keys, local SSH configuration, source trees, build
logs, or temporary Homebrew prefixes.
