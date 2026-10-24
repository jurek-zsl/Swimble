#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPUS_VERSION=1.6.1
OPUS_SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
SOURCE_ROOT="$REPO_ROOT/build/opus-source"
PREFIX="$REPO_ROOT/build/opus-macos26"
BUILD_DIR="$SOURCE_ROOT/compile-macos26"
ARCHIVE="$SOURCE_ROOT/opus-${OPUS_VERSION}.tar.gz"

# Universal by default (Apple Silicon + Intel). Override for a faster local
# single-architecture build, e.g. SWIMBLE_OPUS_ARCHS="$(uname -m)".
OPUS_ARCHS="${SWIMBLE_OPUS_ARCHS:-x86_64;arm64}"

mkdir -p "$SOURCE_ROOT"
if [[ ! -f "$ARCHIVE" ]]; then
  curl -fL "https://ftp.osuosl.org/pub/xiph/releases/opus/opus-${OPUS_VERSION}.tar.gz" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$OPUS_SHA256" "$ARCHIVE" | shasum -a 256 -c -
if [[ ! -d "$SOURCE_ROOT/opus-${OPUS_VERSION}" ]]; then
  tar -xzf "$ARCHIVE" -C "$SOURCE_ROOT"
fi

# Build a universal dylib in one pass; CMake drives both slices and the
# resulting libopus.0.dylib is already fat.
rm -rf "$BUILD_DIR" "$PREFIX"
cmake -S "$SOURCE_ROOT/opus-${OPUS_VERSION}" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$OPUS_ARCHS" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_NAME_DIR="$PREFIX/lib" \
  -DOPUS_BUILD_SHARED_LIBRARY=ON \
  -DOPUS_BUILD_TESTING=OFF \
  -DOPUS_BUILD_PROGRAMS=OFF \
  -DOPUS_INSTALL_PKG_CONFIG_MODULE=ON
cmake --build "$BUILD_DIR" --parallel
cmake --install "$BUILD_DIR"
cp "$SOURCE_ROOT/opus-${OPUS_VERSION}/COPYING" "$PREFIX/COPYING"

echo "==> Opus built for: $(lipo -archs "$PREFIX/lib/libopus.0.dylib")"
