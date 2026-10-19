#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPUS_VERSION=1.6.1
OPUS_SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
SOURCE_ROOT="$REPO_ROOT/build/opus-source"
PREFIX="$REPO_ROOT/build/opus-macos26"
ARCHIVE="$SOURCE_ROOT/opus-${OPUS_VERSION}.tar.gz"
mkdir -p "$SOURCE_ROOT" "$SOURCE_ROOT/compile-macos26"
if [[ ! -f "$ARCHIVE" ]]; then
  curl -fL "https://ftp.osuosl.org/pub/xiph/releases/opus/opus-${OPUS_VERSION}.tar.gz" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$OPUS_SHA256" "$ARCHIVE" | shasum -a 256 -c -
if [[ ! -d "$SOURCE_ROOT/opus-${OPUS_VERSION}" ]]; then
  tar -xzf "$ARCHIVE" -C "$SOURCE_ROOT"
fi
cd "$SOURCE_ROOT/compile-macos26"
MACOSX_DEPLOYMENT_TARGET=26.0 CFLAGS='-O2 -mmacosx-version-min=26.0' \
  LDFLAGS='-mmacosx-version-min=26.0' \
  "../opus-${OPUS_VERSION}/configure" --prefix="$PREFIX" \
    --enable-shared --disable-static --disable-doc --disable-extra-programs
make -j8
make install
cp "$SOURCE_ROOT/opus-${OPUS_VERSION}/COPYING" "$PREFIX/COPYING"
