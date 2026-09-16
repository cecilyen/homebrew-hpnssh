# Release Procedure

The release target is:

- Tap: `cecilyen/hpnssh`
- Repository: `cecilyen/homebrew-hpnssh`
- Tag: `hpnssh-awslc-18.11.0-macos26-arm64`
- Bottle tag: `arm64_tahoe`

## 1. Validate the Tap

```sh
brew style Formula/hpnssh-awslc.rb
brew audit --strict --online cecilyen/hpnssh/hpnssh-awslc
```

## 2. Build the Bottle

```sh
scripts/build-bottle.sh
```

This builds from source with `brew install --build-bottle`, runs the formula
test, creates bottle JSON and the bottle tarball, and writes the bottle checksum
into the formula.

## 3. Commit and Push the Bottle Block

```sh
git add Formula/hpnssh-awslc.rb README.md RELEASE.md scripts .gitignore
git commit -m "Publish HPN-SSH 18.11.0 AWS-LC bottle"
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

Do not upload host private keys, local SSH configuration, or build logs.
