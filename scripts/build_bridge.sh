#!/bin/bash
set -euo pipefail

# Resolve repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Ensure target output directory exists
mkdir -p "${REPO_ROOT}/MacClient/Generated"

# 1. Run cargo build --release in rust-core/
echo "==> Building rust-core in release mode..."
cd "${REPO_ROOT}/rust-core"
cargo build --release

# 2. Run uniffi-bindgen to generate Swift bindings
echo "==> Generating Swift bindings with uniffi-bindgen..."
cargo run --bin uniffi-bindgen generate --library target/release/libmumble_core.dylib --language swift --out-dir ../MacClient/Generated

# 3. Copy target/release/libmumble_core.a to MacClient/Generated/
echo "==> Copying libmumble_core.a to MacClient/Generated/..."
cp target/release/libmumble_core.a ../MacClient/Generated/

# 4. Run xcodegen generate inside MacClient/
echo "==> Generating Xcode project with xcodegen..."
cd "${REPO_ROOT}/MacClient"
xcodegen generate

echo "==> Bridge build complete."
