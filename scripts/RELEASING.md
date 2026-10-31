# macOS releases

Set `CFBundleShortVersionString` and `CFBundleVersion` in `MacClient/project.yml`,
then run from the repository root:

```sh
./scripts/build_release.sh
```

This rebuilds the Rust bridge with `MACOSX_DEPLOYMENT_TARGET=26.0`, regenerates
the Xcode project, builds a checksum-verified Opus 1.6.1 for macOS 26, and
builds the Release app. Xcode leaves this intermediate app unsigned; the
packager signs it after embedding Opus. It creates
`build/Swimble-<version>.dmg` and its `.dmg.sha256` checksum. Release builds are
universal (`arm64` + `x86_64`), so one DMG runs on Apple Silicon and Intel Macs,
and are ad hoc signed, without Apple notarization.

The packager refuses to produce a DMG unless the app executable, the bundled
`swimble-rpc` CLI, and the embedded Opus dylib all contain both architectures.

The packaging script copies the app into a fresh temporary staging directory outside the
workspace, embeds
Opus and its license, rewrites the library load path, and signs the resulting
bundle. It checks that no Homebrew or user-directory dependencies remain.

The installer uses `assets/swimble-dmg/Swimble-DMG-Background.tiff` and the
positions in `assets/swimble-dmg/Finder-layout.json`. Its `.DS_Store` is written
on the mounted writable image, so the background alias refers to a file inside
the volume. After compression, the script remounts the final read-only image
and verifies the background alias, icon size and positions, Applications link,
bundled Opus library, and application signature. Finder automation is not needed
to generate the layout.

To package an already-built Release app:

```sh
build/packaging-tools/venv/bin/python scripts/package_dmg.py \
  --app build/release-derived-data/Build/Products/Release/Swimble.app \
  --output build/Swimble-<version>.dmg
```

The packager refuses to replace an existing output file. After inspecting the
mounted installer in Finder, publish the version tag and release with the DMG
and checksum as release assets. Keep unrelated working-tree edits out of the
release commit.

## Developer ID and notarization

Install a **Developer ID Application** certificate with its private key in the
build Mac's Keychain. An Apple developer account login by itself does not install
this identity. Save notarization credentials with `xcrun notarytool
store-credentials`, then build with the identity and profile names:

```sh
export SWIMBLE_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export SWIMBLE_NOTARY_PROFILE='Swimble'
./scripts/build_release.sh
```

The packager signs embedded code with hardened runtime, submits/staples the app,
then signs and notarizes/staples the final DMG. Credentials remain in Keychain;
never commit certificates, private keys, passwords, or API keys. A failed signing
or notarization step fails the build rather than falling back to ad hoc signing.
Without these variables, the output remains explicitly ad hoc signed.

The app entitlement permits user-selected native positional plugins signed by
other developers. General plugin host APIs are unavailable. Review this policy
when changing plugin support.

## Release verification

Before packaging:

```sh
./scripts/check_versions.py
cargo test --manifest-path rust-core/Cargo.toml --locked -- --test-threads=1
./scripts/test_acl.sh
xcodebuild -project MacClient/Swimble.xcodeproj -scheme Swimble \
  -destination 'platform=macOS' -parallel-testing-enabled NO test
```

Microphone hardware tests skip when the test application has not already been
authorized. Record this separately from synthetic/live-server audio validation.
The installer verifies its persisted background alias and positions after
remounting the compressed image. The bundled CLI is
`Swimble.app/Contents/MacOS/swimble-rpc`.

Push the tested commit first. Create a new immutable version tag and publish the
DMG and `.dmg.sha256` together; do not replace an existing release's assets.
