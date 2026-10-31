#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"
export MACOSX_DEPLOYMENT_TARGET=26.0

./scripts/check_versions.py
./scripts/build_bridge.sh
./scripts/build_opus.sh
xcodebuild -project MacClient/Swimble.xcodeproj -scheme Swimble \
  -destination 'platform=macOS' -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath build/release-derived-data \
  "LIBRARY_SEARCH_PATHS=$REPO_ROOT/build/opus-macos26/lib $REPO_ROOT/MacClient/Generated" \
  CODE_SIGNING_ALLOWED=NO build

DMG_PYTHON="$REPO_ROOT/build/packaging-tools/venv/bin/python"
if [[ ! -x "$DMG_PYTHON" ]]; then
  python3 -m venv "$REPO_ROOT/build/packaging-tools/venv"
fi
"$DMG_PYTHON" -m pip install -r scripts/requirements-dmg.txt
RELEASE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' MacClient/Info.plist)
"$DMG_PYTHON" scripts/package_dmg.py \
  --app build/release-derived-data/Build/Products/Release/Swimble.app \
  --output "build/Swimble-${RELEASE_VERSION}.dmg"
