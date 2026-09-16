#!/usr/bin/env bash
set -Eeuo pipefail

TAP_SOURCE="${TAP_SOURCE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-cecilyen/homebrew-hpnssh}"
RELEASE_TAG="${RELEASE_TAG:-hpnssh-awslc-18.11.0-macos26-arm64}"
OUT_DIR="${OUT_DIR:-${TAP_SOURCE}/dist/${RELEASE_TAG}}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || die "GitHub CLI not found: gh"
command -v uu-cksum >/dev/null 2>&1 || die "Checksum utility not found: uu-cksum"
[[ -d "$OUT_DIR" ]] || die "Release directory not found: $OUT_DIR"
compgen -G "${OUT_DIR}/*.bottle.tar.gz" >/dev/null ||
  die "No Homebrew bottle tarball found in $OUT_DIR"
[[ -f "${OUT_DIR}/SHA256SUMS" ]] || die "SHA256SUMS is missing."
(
  cd "$OUT_DIR"
  uu-cksum -c SHA256SUMS
)

assets=(
  "${OUT_DIR}"/*.bottle.tar.gz
  "${OUT_DIR}"/*.bottle.json
  "${OUT_DIR}"/hpnssh-awslc.rb
  "${OUT_DIR}"/homebrew-tap-README.md
  "${OUT_DIR}"/RELEASE.md
  "${OUT_DIR}"/RELEASE_NOTES.md
  "${OUT_DIR}"/SHA256SUMS
)

if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "${assets[@]}" \
    --repo "$GITHUB_REPOSITORY" \
    --clobber
else
  gh release create "$RELEASE_TAG" "${assets[@]}" \
    --repo "$GITHUB_REPOSITORY" \
    --title "HPN-SSH 18.11.0 AWS-LC macOS 26 ARM64 bottle" \
    --notes-file "${OUT_DIR}/RELEASE_NOTES.md"
fi

gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY"
