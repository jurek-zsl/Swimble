# Swimble Architecture & Agent Rules

You are building **Swimble**, a native macOS 26 Mumble VoIP client for standard `Murmur` servers (TCP/TLS + UDP port 64738) using a **Rust Core** (`rust-core/`) and a **SwiftUI Liquid Glass Frontend** (`MacClient/`).

## 1. Strict Architectural Boundary
- **Rust (`rust-core/`)**: Handles ALL Mumble networking (`tokio-rustls`, TCP 6-byte framing, `Mumble.proto` via `prost`), UDP `OCB2-AES128` encryption, `opus` 48kHz voice encoding/decoding, per-user jitter buffering, and client X.509 certificate generation (`rcgen`).
- **Swift (`MacClient/`)**: Handles ONLY macOS UI (SwiftUI), Keychain storage, Global Push-to-Talk (`CGEvent`), and audio hardware I/O via `AVAudioEngine` with `.voiceProcessingIO` enabled for hardware echo cancellation.
- **Bridge**: Use Mozilla `uniffi` (proc-macro mode, `uniffi::setup_scaffolding!()`) for state/commands and `rtrb` lock-free ring buffers for 48kHz mono PCM audio frames.
- **No Scope Creep**: Do NOT implement screensharing, webcams, or custom server extensions. Strictly target original Mumble 1.5/1.6 `Murmur` servers.

## 2. Xcode Project Management (NEVER edit .pbxproj directly)
- Always modify `MacClient/project.yml` and run `xcodegen generate` inside `MacClient/`.
- Verify Swift compilation from the terminal using:
  `xcodebuild -project MacClient/Swimble.xcodeproj -scheme Swimble -destination 'platform=macOS' build`

## 2a. Universal Binaries (Apple Silicon + Intel)
- Release artifacts are universal: `arm64` + `x86_64`. macOS 26 is the last Intel-supported release, so keep `MACOSX_DEPLOYMENT_TARGET=26.0`.
- Build order: `./scripts/build_opus.sh` (universal Opus) → `./scripts/build_bridge.sh` (universal `libmumble_core.a` and `swimble-rpc` via `lipo`) → `xcodebuild`.
- Never hardcode Homebrew prefixes in build files: `/opt/homebrew` is Apple Silicon, `/usr/local` is Intel. Both are listed as fallbacks.
- `./scripts/build_release.sh` builds with `ARCHS="arm64 x86_64"`; the DMG packager refuses app, `swimble-rpc`, or Opus artifacts that lack either slice.
- For faster single-architecture iteration: `SWIMBLE_ARCHS="$(uname -m)" ./scripts/build_bridge.sh`.

## 3. macOS 26 "Liquid Glass" SwiftUI Standards
Do NOT use legacy `.background(.ultraThinMaterial)` for floating controls. Use macOS 26 Liquid Glass APIs:
- Use standard `NavigationSplitView` for the channel tree sidebar (macOS 26 applies Liquid Glass to the sidebar automatically).
- Wrap floating voice control bars (Mute, Deafen, PTT, Disconnect) inside `GlassEffectContainer(spacing: 14) { ... }`.
- Apply `.glassEffect(.regular.tint(color).interactive(), in: .capsule)` (or `.circle`) to controls inside the container.
- Attach `@Namespace private var glassNamespace` and `.glassEffectID("id", in: glassNamespace)` to controls so state changes morph smoothly.

## 4. Local Test Server
A live Murmur server is running locally in Docker at `127.0.0.1:64738` (container name: `murmur-test`). Always write and run `cargo test` integration tests against `127.0.0.1:64738` (accepting self-signed TLS certs) to verify protocol changes.
