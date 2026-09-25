#!/bin/bash
# Points Homebrew at the version just released: the cask in
# github.com/vedantlavale/homebrew-tap gets this version and the checksum of
# the disk image on its GitHub release, so that
#
#   brew install --cask vedantlavale/tap/ant
#
# installs it, and brew upgrade brings it. Run it once the release is on
# GitHub (tag vX.Y.Z, Ant.dmg attached); it reads the version from VERSION.
set -euo pipefail

cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < VERSION)"
URL="https://github.com/vedantlavale/ant/releases/download/v$VERSION/Ant.dmg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL -o "$WORK/Ant.dmg" "$URL" \
  || { echo "no Ant.dmg on the v$VERSION release yet — publish the release first" >&2; exit 1; }
SHA="$(shasum -a 256 "$WORK/Ant.dmg" | cut -d' ' -f1)"

git clone -q https://github.com/vedantlavale/homebrew-tap.git "$WORK/tap"
CASK="$WORK/tap/Casks/ant.rb"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
if git -C "$WORK/tap" diff --quiet; then
  echo "the tap already has Ant $VERSION"
  exit 0
fi
git -C "$WORK/tap" commit -qam "Ant $VERSION"
git -C "$WORK/tap" push -q
echo "tap: Ant $VERSION, sha256 $SHA"
