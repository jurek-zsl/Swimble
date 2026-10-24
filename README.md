<p align="center">
  <img src="assets/swimble-banner/Swimble-Banner.png" alt="Swimble — Mumble voice chat. Native to macOS." width="700"/>
</p>

**Swimble** is a native macOS client for standard Mumble voice servers. SwiftUI provides the interface and audio hardware integration; Rust implements the Mumble protocol, encrypted voice transport, Opus processing, and playback buffering.

[Download](https://github.com/jurek-zsl/Swimble/releases/latest) · [Screenshots & Video](MEDIA.md) · [Release history](https://github.com/jurek-zsl/Swimble/releases) · [Report an issue](https://github.com/jurek-zsl/Swimble/issues)

## Requirements and installation

- Apple Silicon or Intel Mac running macOS 26 or later. Release builds are universal.
- A standard Murmur server. No server extensions are required.
- Microphone permission for capture; Accessibility permission for global shortcuts.

Download the DMG, open it, and drag **Swimble** to **Applications**. The installer includes Opus, its license, a background image, and an Applications shortcut. Homebrew is not required to run the application.

Published builds currently use ad hoc signing and are not Apple-notarized. Each release includes a SHA-256 checksum. The packaging pipeline supports Developer ID signing and notarization when the maintainer's signing credentials are available; see [release instructions](scripts/RELEASING.md).

## Capabilities

| Area | Support |
| --- | --- |
| Voice | 48 kHz Opus capture, stereo playback, push-to-talk, voice activation, continuous transmission, mute/deafen, priority speakers, per-user volume, and whispers. |
| Voice quality | Configurable 6–128 kbit/s encoder target, 10/20/40/60 ms packets, server bandwidth budgeting, optional Opus FEC, sequence-aware reordering, loss concealment, and adaptive receive buffering. |
| Channels | Hierarchical navigation, listening without joining, channel links, creation/removal, names, hierarchy, ordering, user limits, descriptions, and ACL/group editing subject to server permissions. |
| Messaging | Channel/private messages, formatted descriptions and comments, inline images, per-user text ignore, TTS, notifications, bounded in-memory history, and unread indicators. |
| Audio hardware | App-scoped device routing by stable device UID, offline microphone preview, an output test tone, local/server loopback, VoiceProcessingIO echo cancellation, speech-driven system ducking, and Bluetooth input protection. |
| Positioning | Native Mumble Link, stereo virtual seating, manual world coordinates, distance/volume controls, native positional-plugin loading, and source diagnostics. |
| Recording | Synchronized 48 kHz stereo WAV: microphone on the left only while transmitting, received mix on the right. Each server window owns its recording. |
| Connections | Bookmarks, public directory, DNS SRV, IPv4/IPv6 endpoints, `mumble://` links, automatic TCP fallback, forced TCP mode, and reconnect backoff. |
| Identities | Client certificate generation and PKCS#12 import/export, certificate-based friends/local nicknames, system TLS trust, and explicit private-server fingerprint approval. |
| macOS | Liquid Glass interface, menu bar controls, trackpad haptics, speaker overlay, global keyboard/mouse shortcuts, named whisper presets, and local command-line control. |

New installations have no default server. Startup connection is opt-in and uses the last successfully connected saved server. Existing bookmarks are preserved. Empty channels do not display a zero participant count.

## Security and identity

TLS verifies the requested hostname through the macOS trust store and validates handshake signatures. Private/self-signed certificates require explicit SHA-256 fingerprint approval. Approvals are scoped to the requested host and port; a changed certificate stops connection for review. Server Information can remove a saved approval.

Client private keys and saved passwords live in Keychain. Earlier JSON credential caches and password-bearing bookmarks are migrated only after successful Keychain writes. New bookmark serialization excludes passwords. Identity loading runs away from the main actor; Keychain failures do not silently generate a replacement identity.

UDP voice uses Mumble-compatible OCB2-AES128, including the upstream XEX* countermeasures and replay protection. Incoming control frames have a size limit and read deadlines. Malformed or out-of-range Mumble URL ports are rejected.

Murmur remains authoritative for permissions. Persistent user grants use registered user IDs associated with certificates, rather than temporary session IDs. Older Murmur 1.5 builds can send a stale suppression flag after restoring Speak; affected users may need to reconnect.

## Audio configuration

**Audio Input** contains transmission thresholds, hold times, encoder quality, packet duration, FEC, microphone gain, and device selection. **Audio Output** contains playback volume, receive buffering, positioning, ducking, and microphone tests. Selected devices affect Swimble's audio units, not the Mac's system defaults.

Capture/playback callbacks exchange PCM through bounded lock-free queues. Resampling, Opus, mixing, and recording run on a worker. Statistics calculate FFT data only while displayed. Counters distinguish capture overruns and playback underruns; unavailable signal measurements are identified explicitly rather than estimated as measured values.

Microphone recording follows the transmission gate, including configured hold times. Local monitoring stays out of the received-audio recording track.

Local loopback works without a server. Server loopback requires a connection, uses the standard Mumble loopback voice target, and follows the transmission gate. Use headphones for microphone tests.

Ducking uses Apple's speech-driven voice processing. With ducking disabled, VoiceProcessingIO can still apply Apple's minimum attenuation. Disabling echo cancellation as well selects unprocessed capture. Bluetooth protection selects the built-in microphone for Swimble when appropriate, preserving stereo headphone output.

## Positional audio and game plugins

Native Link reads the POSIX `/MumbleLink.<uid>` layout, including avatar position, camera orientation, context, and player identity. Matching game contexts receive stereo positioning based on direction and distance. Manual positioning uses the original Mumble manual-placement context prefix. Virtual seating provides stereo separation without game integration.

Audio Output exposes near/far distance, far-distance volume, near-field spread, manual coordinates/heading/context, and source diagnostics. This is stereo positional rendering, without head tracking or HRTF processing.

The plugin manager loads trusted native macOS legacy positional plugins and standalone positional plugins using Mumble API 1.2. General Mumble host API requests are not implemented and return an explicit error; plugins requiring those APIs cannot be used. Windows/Wine binaries and games that macOS does not permit a plugin to inspect are unsupported. Saved plugin paths are listed for explicit activation; they are not silently loaded at startup.

## Shortcuts and local control

Global shortcuts target the last focused Swimble server window. Closing that window releases held transmission state and selects another connected session. Keyboard and side-mouse bindings support PTT, mute/deafen, overlay visibility, push-to-mute, transmission latching, channel joins/listening, and named whisper presets. Channel actions and whisper presets are scoped to their server.

The app bundles a local CLI:

```sh
/Applications/Swimble.app/Contents/MacOS/swimble-rpc mute
/Applications/Swimble.app/Contents/MacOS/swimble-rpc toggledeaf
/Applications/Swimble.app/Contents/MacOS/swimble-rpc starttalking
/Applications/Swimble.app/Contents/MacOS/swimble-rpc stoptalking
/Applications/Swimble.app/Contents/MacOS/swimble-rpc join 12
```

Run `swimble-rpc --help` for the command vocabulary. The control socket is restricted to the current macOS user. A `queued` response acknowledges dispatch to the active session, not server acceptance of a permission-controlled operation.

## Compatibility

The protocol targets standard Mumble 1.5 and 1.6 Murmur servers, including 1.5+ protobuf voice packets and legacy voice fallback. Default control/voice port: TCP/TLS and UDP `64738`. Compatibility testing uses local Murmur fixtures; a target version is not a claim that every upstream client feature is implemented.

Public server browsing uses Mumist.eu with a Mumble.info fallback. Directory activity data depends on the source. Intel distributions, legacy voice codecs, a general Mumble plugin host, and injected game overlays are not provided. The floating macOS overlay depends on the game's window/full-screen behavior.

## Build and test

Install Xcode with the macOS 26 SDK or later, Rust, XcodeGen, Opus, and Protobuf tooling:

```sh
brew install opus protobuf xcodegen
./scripts/check_versions.py
cargo check --manifest-path rust-core/Cargo.toml
./scripts/build_bridge.sh
xcodebuild -project MacClient/Swimble.xcodeproj -scheme Swimble -destination 'platform=macOS' build
```

Run the protocol and Swift regression suites:

```sh
# A disposable local Murmur fixture must be available on 127.0.0.1:64738.
cargo test --manifest-path rust-core/Cargo.toml -- --test-threads=1
./scripts/test_acl.sh
xcodebuild -project MacClient/Swimble.xcodeproj -scheme Swimble -destination 'platform=macOS' -parallel-testing-enabled NO test
```

`test_acl.sh` starts and removes a separate localhost-only admin fixture on port `64739`; it does not modify the primary server's ACLs. Live tests verify strict TLS rejection/explicit trust, voice transport, stereo/deafen behavior, forced TCP, recording duration, listeners, links, channel edits, and ACL enforcement. Unit tests cover malformed framing, URL/credential serialization, OCB2 protections, packet ordering, encoder budgets, positional data, plugin ABI compatibility, and transmission state. Hardware tests run only when microphone access is already authorized.

GitHub Actions runs protocol integration checks on Linux and Swift regression checks on macOS 26. Build the portable installer with:

```sh
./scripts/build_release.sh
```

## Architecture

| Component | Responsibility |
| --- | --- |
| `rust-core/` | Mumble networking and state, TLS/OCB2, Protobuf voice/control, Opus, resampling, buffering/mixing, positional sources, recording, and local control transport. |
| `MacClient/` | SwiftUI, CoreAudio/AVAudioEngine hardware I/O, Keychain integration, global shortcuts, notifications, and application preferences. |
| UniFFI | Commands, events, state snapshots, and generated Swift bindings. |
| Native PCM boundary | Bounded `rtrb` queues accessed through a small C ABI, avoiding array serialization on audio callbacks. |

Edit `MacClient/project.yml` and regenerate with XcodeGen; do not edit `.pbxproj` directly. Rust FFI changes require regenerating the bridge. Protocol definitions and imported plugin headers retain their upstream Mumble BSD license.

## License

Swimble is licensed under the [MIT License](LICENSE). Third-party components retain their respective licenses.
