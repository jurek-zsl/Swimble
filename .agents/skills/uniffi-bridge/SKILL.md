---
name: uniffi-bridge
description: Compiles the Rust mumble_core static library, generates Swift UniFFI bindings, and regenerates the Xcode project via XcodeGen. Use whenever Rust FFI types, functions, or Cargo dependencies change.
---

# UniFFI Rust-to-Swift Bridge Workflow

Whenever you modify any `#[uniffi::export]`, `#[derive(uniffi::Record)]`, or `#[derive(uniffi::Object)]` item in `rust-core/`, or change dependencies / bridging configuration, follow these exact steps:

## Workflow Steps

1. **Verify Rust Core Compiles**:
   ```bash
   cd rust-core && cargo check
   ```

2. **Run Bridge Generation & Build**:
   Execute the bridge build script from the workspace root:
   ```bash
   ./scripts/build_bridge.sh
   ```
   This script:
   - Compiles `rust-core` in release mode (`cargo build --release`).
   - Runs `uniffi-bindgen` to generate Swift bindings into `MacClient/Generated/`.
   - Copies `libmumble_core.a` to `MacClient/Generated/`.
   - Runs `xcodegen generate` in `MacClient/` to regenerate `Swimble.xcodeproj`.

3. **Verify Swift Compilation**:
   Validate that the client builds successfully without opening Xcode:
   ```bash
   xcodebuild -project MacClient/Swimble.xcodeproj -scheme Swimble -destination 'platform=macOS' build
   ```

## Rules & Constraints
- **Never edit `.pbxproj` directly**: Always modify `MacClient/project.yml` and run `xcodegen generate`.
- Ensure `MacClient/Generated/mumble_coreFFI.modulemap` and `MacClient/Generated/mumble_coreFFI.h` are preserved and accessible to the compiler via Swift search paths.
