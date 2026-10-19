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
`build/Swimble-<version>.dmg` and its `.dmg.sha256` checksum. The default build
is for Apple Silicon and is ad hoc signed, without Apple notarization.

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
