#!/usr/bin/env bash
set -Eeuo pipefail

TAP_SOURCE="${TAP_SOURCE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TAP_NAME="${TAP_NAME:-cecilyen/hpnssh}"
FORMULA="${FORMULA:-hpnssh-awslc}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-cecilyen/homebrew-hpnssh}"
RELEASE_TAG="${RELEASE_TAG:-hpnssh-awslc-18.11.1-macos26-arm64}"
ROOT_URL="${ROOT_URL:-https://github.com/${GITHUB_REPOSITORY}/releases/download/${RELEASE_TAG}}"
OUT_DIR="${OUT_DIR:-${TAP_SOURCE}/dist/${RELEASE_TAG}}"
FQ_FORMULA="${TAP_NAME}/${FORMULA}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_cmd brew
require_cmd bfs
require_cmd git
require_cmd jaq
require_cmd rsync
require_cmd ug
require_cmd uu-cksum

[[ "$(uname -s)" == "Darwin" ]] || die "This bottle is macOS-only."
[[ "$(uname -m)" == "arm64" ]] || die "This bottle requires an ARM64 Mac."
[[ -f "${TAP_SOURCE}/Formula/${FORMULA}.rb" ]] ||
  die "Formula not found: ${TAP_SOURCE}/Formula/${FORMULA}.rb"
git -C "$TAP_SOURCE" diff --quiet ||
  die "Commit tracked tap changes before building the bottle."
git -C "$TAP_SOURCE" diff --cached --quiet ||
  die "Commit staged tap changes before building the bottle."
[[ -z "$(git -C "$TAP_SOURCE" ls-files --others --exclude-standard)" ]] ||
  die "Commit or remove untracked tap files before building the bottle."

export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"
export HOMEBREW_NO_INSTALL_CLEANUP="${HOMEBREW_NO_INSTALL_CLEANUP:-1}"

BREW_CELLAR="$(brew --cellar)"
BREW_TAPS="$(brew --repository)/Library/Taps"
[[ -w "$BREW_CELLAR" ]] || die "Homebrew Cellar is not writable: $BREW_CELLAR"
[[ -w "$BREW_TAPS" ]] || die "Homebrew taps directory is not writable: $BREW_TAPS"

if brew list --formula -1 | ug -Fxq "$FORMULA"; then
  brew uninstall --force "$FQ_FORMULA"
fi
if brew tap | ug -Fxq "$TAP_NAME"; then
  brew untap "$TAP_NAME"
fi
brew tap "$TAP_NAME" "file://${TAP_SOURCE}"

rm -rf -- "$OUT_DIR"
mkdir -p "$OUT_DIR"

brew install --build-bottle "$FQ_FORMULA"
brew test "$FQ_FORMULA"

(
  cd "$OUT_DIR"
  brew bottle --json --no-rebuild --root-url="$ROOT_URL" "$FQ_FORMULA"
)

JSON_FILE="$(bfs "$OUT_DIR" -maxdepth 1 -name '*.bottle.json' -print -quit)"
[[ -n "$JSON_FILE" ]] || die "Homebrew did not create bottle JSON."
LOCAL_BOTTLE="$(jaq -r '.[] | .bottle.tags[] | .local_filename' "$JSON_FILE")"
REMOTE_BOTTLE="$(jaq -r '.[] | .bottle.tags[] | .filename' "$JSON_FILE")"
[[ -n "$LOCAL_BOTTLE" && -n "$REMOTE_BOTTLE" ]] ||
  die "Bottle filenames are missing from $JSON_FILE"
[[ -f "$OUT_DIR/$LOCAL_BOTTLE" ]] ||
  die "Local bottle not found: $OUT_DIR/$LOCAL_BOTTLE"
if [[ "$LOCAL_BOTTLE" != "$REMOTE_BOTTLE" ]]; then
  mv "$OUT_DIR/$LOCAL_BOTTLE" "$OUT_DIR/$REMOTE_BOTTLE"
fi

brew bottle --merge --write --no-commit "$JSON_FILE"

TAPPED_REPO="$(brew --repository "$TAP_NAME")"
rsync -a "${TAPPED_REPO}/Formula/${FORMULA}.rb" "${TAP_SOURCE}/Formula/${FORMULA}.rb"

cp "${TAP_SOURCE}/Formula/${FORMULA}.rb" "$OUT_DIR/"
cp "${TAP_SOURCE}/README.md" "$OUT_DIR/homebrew-tap-README.md"
cp "${TAP_SOURCE}/RELEASE.md" "$OUT_DIR/RELEASE.md"

cat > "$OUT_DIR/RELEASE_NOTES.md" <<'NOTES'
# HPN-SSH 18.11.1 AWS-LC bottle

Prebuilt Homebrew bottle for macOS 26 Tahoe on Apple Silicon.

- HPN-SSH 18.11.1 / OpenSSH 10.5p1
- AWS-LC runtime dependency
- macOS system zlib, libedit, PAM, and Kerberos
- ARM64 ThinLTO build
- Default port 22
- Stripped and ad-hoc signed executables
- No host private keys

HPN-SSH 18.11.1 fixes SecureBlackbox/MobaXterm SFTP rekey interoperability
and preserves `DisableMTAES` across later rekeys.

Install:

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
```
NOTES

(
  cd "$OUT_DIR"
  LC_ALL=C uu-cksum -a sha256 -- \
    ./*.bottle.tar.gz ./*.bottle.json ./hpnssh-awslc.rb \
    ./homebrew-tap-README.md ./RELEASE.md ./RELEASE_NOTES.md > SHA256SUMS
)

printf 'Bottle release directory: %s\n' "$OUT_DIR"
printf 'Bottle root URL: %s\n' "$ROOT_URL"
printf 'Installed source build remains available for inspection: %s\n' "$FQ_FORMULA"
