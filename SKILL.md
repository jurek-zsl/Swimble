---
name: uniffi-bridge
description: Compiles the Rust mumble_core static library, generates Swift UniFFI bindings, and regenerates the Xcode project via XcodeGen. Use whenever Rust FFI types, functions, or Cargo dependencies change.
---

# UniFFI Rust-to-Swift Bridge Workflow

Whenever you modify any `#[uniffi::export]`, `#[derive(uniffi::Record)]`, or `#[derive(uniffi::Object)]` item in `rust-core/`, run these exact steps:

1. Run the bridge build script from the workspace root:
   ```bash
   ./scripts/build_bridge.sh
