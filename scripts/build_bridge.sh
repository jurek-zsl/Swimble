#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"

# Architectures to build. Defaults to a universal app (Apple Silicon + Intel).
# Set SWIMBLE_ARCHS to a single arch for faster local iteration, e.g.
#   SWIMBLE_ARCHS="$(uname -m)" ./scripts/build_bridge.sh
ARCHS_STRING="${SWIMBLE_ARCHS:-arm64 x86_64}"
read -r -a ARCHS <<< "$ARCHS_STRING"

rust_triple_for() {
  case "$1" in
    arm64)  echo "aarch64-apple-darwin" ;;
    x86_64) echo "x86_64-apple-darwin" ;;
    *) echo "Unsupported architecture: $1" >&2; exit 1 ;;
  esac
}

# Resolve repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Ensure target output directory exists
mkdir -p "${REPO_ROOT}/MacClient/Generated"
UNIVERSAL_DIR="${REPO_ROOT}/rust-core/target/universal"
mkdir -p "${UNIVERSAL_DIR}"

STATIC_LIBS=()
DYLIB_LIBS=()
RPC_BINS=()

# 1. Build rust-core for every architecture
cd "${REPO_ROOT}/rust-core"
for arch in "${ARCHS[@]}"; do
  triple="$(rust_triple_for "${arch}")"
  if command -v rustup >/dev/null 2>&1; then
    rustup target add "${triple}" >/dev/null 2>&1 || true
  fi
  echo "==> Building rust-core for ${arch} (${triple})..."
  cargo build --release --target "${triple}"
  STATIC_LIBS+=("target/${triple}/release/libmumble_core.a")
  DYLIB_LIBS+=("target/${triple}/release/libmumble_core.dylib")
  RPC_BINS+=("target/${triple}/release/swimble-rpc")
done

# 2. Merge per-architecture artifacts into universal binaries
echo "==> Creating universal binaries with lipo (${ARCHS_STRING})..."
lipo -create -output "${UNIVERSAL_DIR}/libmumble_core.a" "${STATIC_LIBS[@]}"
lipo -create -output "${UNIVERSAL_DIR}/libmumble_core.dylib" "${DYLIB_LIBS[@]}"
lipo -create -output "${UNIVERSAL_DIR}/swimble-rpc" "${RPC_BINS[@]}"

# 3. Run uniffi-bindgen to generate Swift bindings.
#    The bindings are architecture-independent; use the universal dylib.
echo "==> Generating Swift bindings with uniffi-bindgen..."
cargo run --release --bin uniffi-bindgen -- generate --library "${UNIVERSAL_DIR}/libmumble_core.dylib" --language swift --out-dir ../MacClient/Generated

# Keep generated text stable across bindgen runs.
python3 - <<'PYTHON'
from pathlib import Path
for generated in Path('../MacClient/Generated').iterdir():
    if generated.suffix in {'.swift', '.h'}:
        generated.write_text('\n'.join(line.rstrip() for line in generated.read_text().splitlines()) + '\n')
PYTHON

# 4. Copy the universal artifacts where Xcode and the packager expect them.
echo "==> Copying universal libmumble_core.a to MacClient/Generated/..."
cp "${UNIVERSAL_DIR}/libmumble_core.a" ../MacClient/Generated/
# package_dmg.py reads the CLI from rust-core/target/release/.
cp "${UNIVERSAL_DIR}/swimble-rpc" target/release/swimble-rpc
chmod +x target/release/swimble-rpc

# 5. Run xcodegen generate inside MacClient/
echo "==> Generating Xcode project with xcodegen..."
cd "${REPO_ROOT}/MacClient"
xcodegen generate

echo "==> Bridge build complete."
for artifact in "${UNIVERSAL_DIR}/libmumble_core.a" "${UNIVERSAL_DIR}/swimble-rpc"; do
  printf '    %s: ' "${artifact#"${REPO_ROOT}/"}"
  lipo -archs "${artifact}"
done
