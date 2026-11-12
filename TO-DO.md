# Swimble implementation and improvement backlog

Audit date: **2026-11-03**. Audited Swimble revision: **`7660831`**, version **1.2.1**.

Publication refresh: the universal-binary contribution merged in **`7e80843`** was reviewed before publishing this backlog. Apple Silicon and Intel build support is now present; release and hardware verification remain outstanding. The validation results below describe the original audited revision.

This is a source-based repository audit against the original Mumble client and Murmur server. It covers the Rust core, native plugin adapter, Swift frontend, generated bridge configuration, tests, CI, build/release scripts, and documentation. No application source was changed during the audit. Compiled outputs, generated assets, and upstream reference copies are not implementation changes.

## Scope and comparison baseline

- Stable reference: [Mumble/Murmur 1.5.939](https://github.com/mumble-voip/mumble/releases/tag/v1.5.939), commit `dfbac8d3d9c967003e74b4ffc5610f7d45e8f666`.
- 1.6 reference: [Mumble/Murmur 1.6.1001 RC 2](https://github.com/mumble-voip/mumble/releases/tag/v1.6.0-alpha2), commit `afc8cbbb97c882bb4d92388c788c149c16999732`. The release's Git tag is `v1.6.0-alpha2`; 1.6 is a prerelease at this audit date.
- Target remains a native macOS 26 client for ordinary Murmur servers. Keep Mumble protocol, TLS, UDP encryption, codecs, buffering, and positional processing in Rust; keep UI, Keychain, global input, and audio hardware integration in Swift.
- Murmur is a compatibility and permission-enforcement reference, not a request to build a server. Server databases, hosting, Ice administration, authenticators, and server configuration management are outside this client's required implementation.
- **Bug** means the current source shows a specific incorrect or incomplete behavior. **Missing** means an upstream feature has no equivalent implementation. **Verify** means a plausible risk or an existing feature needs additional evidence; it is not a reproduced defect. **Optional** means a product decision, not required parity.
- **P1:** privacy, identity, audio correctness, or connection reliability. **P2:** normal compatibility, usability, and release quality. **P3:** optional parity or longer-term improvements. All checkboxes are outstanding work, including verification work.

## What already exists

Do not reimplement these from scratch. They need the targeted fixes and verification below.

| Area | Present in Swimble | Remaining work |
| --- | --- | --- |
| Transport | TLS control framing, system certificate validation, explicit private-server pinning, OCB2 voice, UDP/TCP fallback, forced TCP, SRV, IPv6 | Connection lifetime, peer selection, statistics, malformed input, test matrix |
| Voice | Opus, 10/20/40/60 ms packets, configurable bitrate/FEC, per-user decoding, reordering, PLC, mixing, priority attenuation | Bandwidth edge cases, jitter recovery, stream transitions, stereo source preservation |
| Hardware | AVAudioEngine, VoiceProcessingIO, stable device UIDs, Bluetooth protection, offline preview, loopback | Receive-only operation, failure reporting, hot-plug evidence, latency and multi-window behavior |
| Channels | Tree/search, join, create/delete/edit, links, listeners, ACL/group editor, drag users between channels | Listener volumes, permission consistency, administration feedback, cross-server drag isolation |
| Users | Mute/deafen, priority, local mute/volume, comments/avatars, registration, kick/ban, registered-user editor | Persistent identity-based preferences, reset others' content, richer bans, accurate diagnostics |
| Messaging | Channel/private sending, HTML/Markdown display, images, TTS, notifications, bounded in-memory history | Working remote-image privacy control, policy limits, addressing, stable rows, event routing |
| Identity | Generated client certificates, PKCS#12 import/export, Keychain secrets, migration, certificate friends/nicknames | Corrupt identity handling, shared identity updates, validation and backup UX |
| Positioning | Mumble Link, manual placement, virtual seating, native legacy/API 1.2 positional plugins | Plugin scheduling/lifecycle, source controls, interoperability evidence |
| macOS | Liquid Glass sidebar/HUD, menu bar, floating speaker overlay, global shortcuts, local CLI | Accessibility, active-session consistency, shortcut interactions, settings transactions |
| Distribution | DMG assembly, bundled Opus/CLI, checksums, optional signing/notarization pipeline, Linux/macOS CI | Reproducible compatibility fixtures, release gates, dependency notices, clean-machine validation |

The vendored control schema already contains the fields present in the inspected 1.6 RC schema, including selective bans and rolling statistics. The main protocol gaps are **handling and exposing fields/messages**, not merely updating `.proto` files.

## Start here

Suggested first implementation sequence: **SEC-01 → SEC-02 → SEC-03 → NET-01 → NET-02 → PRO-01 → AUD-01 → UX-01**. Add focused regression coverage as each behavior is fixed. Regenerate UniFFI bindings for any exposed Rust API changes and regenerate Xcode through `MacClient/project.yml` only.

## Privacy, credentials, and identity

<a id="sec-01"></a>

- [x] **SEC-01 · P1 · Bug — Isolate access tokens by server and move them to Keychain.**
  `MumbleStore.loadAccessTokens/saveAccessTokens` use one plaintext `Swimble_AccessTokens` preference. `connect` and the connected callback send that same list to every server. Upstream scopes tokens by server digest in [Database.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/Database.cpp).
  **Done when:** server A's tokens never enter server B's Authenticate messages; migration preserves existing tokens without automatically assigning them to every server; concurrent windows stay isolated. Sources: `MacClient/Sources/Store/MumbleStore.swift`, `MacClient/Sources/KeychainHelper.swift`, `rust-core/src/client.rs`.

<a id="sec-02"></a>

- [x] **SEC-02 · P1 · Bug — Make “Block External Remote Images” enforceable.**
  `doNotEmbedExternalImages` is saved and displayed but never read by the rendering/loading paths. `RemoteChatImageView.fetchImage` fetches remote URLs unconditionally, including images reached through `RichDescriptionView`.
  **Done when:** enabling the setting prevents network loads from chat, welcome text, descriptions, comments, previews, and cached views; sanitize external resources before the HTML attributed-string importer too. Add a local HTTP request-counter test. Sources: `Views/Settings/NetworkSettingsTab.swift`, `Views/ChatAndActivityView.swift`, `Views/Components/RichDescriptionView.swift` under `MacClient/Sources/`.

<a id="sec-03"></a>

- [x] **SEC-03 · P1 · Bug — Treat corrupt stored identities as errors, not missing identities.**
  `KeychainHelper.loadClientIdentity` suppresses JSON decoding errors with `try?` and can return `nil` even when an identity item exists. `CredentialRepository.loadIdentity` then generates and saves a new identity, potentially losing the certificate associated with registrations and permissions.
  **Done when:** malformed/incomplete stored identity data fails visibly and remains recoverable; only a genuinely absent identity creates a new key. Sources: `MacClient/Sources/KeychainHelper.swift`, `MacClient/Sources/Utils/CredentialRepository.swift`.

<a id="sec-04"></a>

- [ ] **SEC-04 · P1 · Bug — Synchronize identity replacement across server windows.**
  Replacing an identity updates the shared credential actor and only the initiating store. Other stores retain their old `clientIdentity` and can reconnect with it while new windows use the replacement.
  **Done when:** all stores agree on the identity used for future connections; existing TLS sessions are clearly distinguished from future identity selection. Sources: `MumbleStore.updateClientIdentity`, `CredentialRepository.replaceIdentity`.

<a id="sec-05"></a>

- [ ] **SEC-05 · P2 · Improve — Validate PKCS#12 identities before installing them.**
  The pure-Rust import path independently takes the first certificate and first private key; it does not establish that they match or retain a certificate chain. Import/export and OpenSSL subprocess work also run synchronously from certificate UI actions.
  **Done when:** mismatched/multiple-key archives, encrypted archives, missing keys, and certificate chains have explicit handling; validation completes before replacing Keychain data; expensive work stays off the main actor. Sources: `rust-core/src/cert.rs`, `MacClient/Sources/Views/Modals/CertificateWizardModal.swift`, certificate controls in `Views/Settings/SettingsModal.swift`.

<a id="sec-06"></a>

- [ ] **SEC-06 · P2 · Improve — Provide complete certificate inspection and backup recovery.**
  Client identity UI mostly exposes a SHA-1 fingerprint; server trust review exposes a fingerprint/reason but not full certificate metadata. SHA-1 certificate identity remains necessary for Mumble compatibility and should not simply be replaced.
  **Done when:** inspect subject, issuer, validity, chain where available, and SHA-256 alongside the Mumble identity fingerprint; provide backup status and a recoverable Keychain-error retry. Preserve existing explicit trust and changed-pin blocking. Sources: certificate wizard, `ServerIdentityReview.swift`, `ServerInformationModal.swift`, `connection.rs`.

<a id="sec-07"></a>

- [ ] **SEC-07 · P1 · Improve — Bound and sanitize untrusted rich content.**
  Remote images are downloaded into an unbounded `Data` response; the image cache has no explicit byte budget. HTML/base64 parsing and image creation occur in rendering helpers, and the attributed-string importer receives raw HTML.
  **Done when:** enforce download, pixel, decoded-image, cache, and rendered-content budgets; sanitize resource-bearing markup and link schemes; downsample thumbnails and cache parsed content. Verify malformed HTML, oversized images, redirects, and cancellation without asserting an untested exploit. Sources: `ChatAndActivityView.swift`, `RichDescriptionView.swift`, user avatar rendering in `UserRowView.swift`.

## Connection and Rust core reliability

<a id="net-01"></a>

- [x] **NET-01 · P1 · Bug — Clear session-scoped state on server changes and reconnects.**
  `ClientState.reset` leaves `user_volumes` intact. Swift keeps session-ID maps for local mute, volume, and ignored text; active voice-target selection also survives core disconnect. Those numeric IDs can identify different users/channels on the next server. Unexpected disconnect also leaves substantial UI state populated.
  **Done when:** reset ephemeral user/channel/ACL/stats/whisper/idle/move state at a defined session boundary; retain intentional preferences through certificate/server keys; re-establish self mute/deafen deliberately before microphone transmission. Sources: `state.rs`, `client.rs`, `MumbleStore.connect/disconnect/onConnectionStatusChanged`.

<a id="net-02"></a>

- [x] **NET-02 · P1 · Verify — Make connection replacement cancel and isolate every old task/callback.**
  `connect` signals the previous connection but reuses shared state, mixer, crypto, counters, and callback handler. Most Swift callbacks carry no connection generation; only status callbacks compare current status. Old TLS reads/UDP handlers and queued MainActor tasks need a demonstrable lifetime boundary.
  **Done when:** rapid A→B switching, repeated Connect, disconnect during DNS/TLS, and late old-server events cannot update or send through B's session. Track a generation and/or await task shutdown; cover the races with deterministic tests. Sources: `rust-core/src/client.rs`, `StoreEventHandler` and callbacks in `MumbleStore.swift`.

<a id="net-03"></a>

- [x] **NET-03 · P1 · Bug — Use the established TCP peer for UDP.**
  After TLS succeeds, CryptSetup performs another DNS lookup and chooses its first address. That address may differ from the IP that accepted TCP, breaking UDP association behind multi-address hosts, SRV targets, or address-family fallback.
  **Done when:** UDP connects to the successful TCP peer address/port and all relevant address families are tested. Source: `client.rs`, CryptSetup socket setup; preserve original-host certificate validation in `connection.rs`.

<a id="net-04"></a>

- [x] **NET-04 · P1 · Bug — Correct ping and packet-statistics reporting.**
  UDP replies call `on_ping_updated(0.0, udp_ms, false)`, resetting the displayed TCP value. TCP Ping processing can subsequently replace the UDP value with zero. Outgoing heartbeats contain only a timestamp; local OCB receive good/late/lost/resync counters and ping moments are not maintained/reported like upstream.
  **Done when:** independent measurements do not erase each other; local versus server-reported directions are explicit; heartbeat statistics reflect actual traffic; monotonic timing and fallback transitions have tests. Sources: `client.rs`, `crypt_ocb2.rs`, `ServerConnectionInfo` in `lib.rs`; compare upstream [ServerHandler.cpp](https://github.com/mumble-voip/mumble/blob/v1.6.0-alpha2/src/mumble/ServerHandler.cpp).

<a id="net-05"></a>

- [ ] **NET-05 · P1 · Improve — Propagate connection and command errors explicitly.**
  Early DNS/TCP/TLS failures are largely printed and collapsed into `Failed`; `send_proto` silently drops commands on a full/closed queue. Voice uses `try_send` too, including stream terminators. UI operations can claim success before delivery or Murmur acceptance.
  **Done when:** expose structured connection/reject/permission/queue failures; control operations report queued/rejected/failed state; preserve or deliberately recover from lost terminators; no unbounded queue replacement. Sources: `client.rs`, `lib.rs`, `MumbleStore.swift`.
  **Status:** connection failures now carry a structured kind (`on_connection_error`: unreachable / TLS / handshake timeout / rejected / I/O) and a reason; a rejected session ends as `Failed`; dropped commands report `on_command_failed`; voice stream terminators are no longer dropped on a full queue. Still open: per-operation queued/rejected/failed state in the UI, and surfacing `on_connection_error` kinds in the Connect dialog.

<a id="net-06"></a>

- [x] **NET-06 · P1 · Improve — Couple writer failure and write deadlines to connection shutdown.**
  The writer breaks on error without directly ending the reader/session, and raw writes have no timeout. Reads have frame deadlines, but a stalled writer or pre-sync server can leave connection progress unclear.
  **Done when:** writer failure wakes the session immediately; writes and authentication/synchronization have bounded deadlines and cancellation; a responsive Ping stream alone cannot leave Connect pending forever. Sources: `client.rs`, `framing.rs`.

<a id="net-07"></a>

- [ ] **NET-07 · P1 · Improve — Harden parsers and per-session resource limits.**
  Legacy `decode_varint` recursively accepts `0xF8` prefixes without a depth bound. Jitter arithmetic uses unchecked `u64` additions on network sequence values, and decoder creation accepts session IDs absent from the user model. Individual frames are bounded, but cumulative users/blobs/streams are not comprehensively bounded.
  **Done when:** bounded iterative varints, checked sequence arithmetic, validated sessions, and cumulative limits reject malformed input without stack overflow, panic, poisoned locks, or excessive allocation. Fuzz control/voice parsing and crypto state transitions. Sources: `voice_packet.rs`, `audio_mixer.rs`, `state.rs`, `framing.rs`.

<a id="net-08"></a>

- [ ] **NET-08 · P2 · Verify — Complete real-network recovery behavior.**
  Exercise Wi-Fi/VPN changes, sleep/wake, UDP black holes and recovery, nonce resync, repeated CryptSetup, IPv6-only servers, and slow/broken address families. Check TCP_NODELAY and stalled-write behavior against measured voice latency; avoid adding transport optimizations without evidence.
  **Done when:** bounded reconnect with useful reasons, one active UDP heartbeat/receiver per session, no stale audio, and recorded UDP→TCP→UDP recovery evidence. Sources: `connection.rs`, `client.rs`, `dns.rs`, `MacAudioEngine.swift`.

<a id="net-09"></a>

- [ ] **NET-09 · P2 · Missing — Add proxy support if full connection parity is required.**
  Original Mumble supports HTTP CONNECT and SOCKS5 proxy settings; Swimble connects directly. Forced TCP is already present and is a separate capability.
  **Done when:** Rust owns proxy negotiation/timeouts, proxy credentials use Keychain, and TLS still validates the intended server. Document any deliberate exclusion. Sources: `connection.rs`, `NetworkSettingsTab.swift`; reference [NetworkConfig.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/NetworkConfig.cpp).

## Mumble/Murmur protocol and administration parity

<a id="pro-01"></a>

- [x] **PRO-01 · P1 · Bug — Honor server recording policy.**
  ServerConfig's `recording_allowed` is decoded but ignored. Recording controls and `start_recording` do not consult it, while upstream explicitly enables/disables recording from this field.
  **Done when:** bridge the policy, disable recording when forbidden, and stop an active recording if policy changes; show a useful reason. Sources: `client.rs`, `lib.rs`, `MumbleStore.toggleAudioRecording`, `App.swift`; upstream [msgServerConfig](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/Messages.cpp).

<a id="pro-02"></a>

- [ ] **PRO-02 · P2 · Missing — Respect server HTML and text/image length limits.**
  `allow_html`, `message_length`, and `image_message_length` are ignored. Image compression uses a fixed 80 KB target, can still return larger output, and does not budget base64 expansion or markup.
  **Done when:** expose live limits; build and validate the final encoded message using Murmur's counting rules; disable unsupported formatting/images and retain rejected drafts. Sources: `client.rs`, `lib.rs`, `ChatImageHelper`, comment/description editors; reference [Murmur Messages.cpp](https://github.com/mumble-voip/mumble/blob/v1.6.0-alpha2/src/murmur/Messages.cpp).

<a id="pro-03"></a>

- [ ] **PRO-03 · P2 · Missing — Handle SuggestConfig and codec negotiation.**
  SuggestConfig (25) and CodecVersion (21) have schema definitions but no dispatch cases. An Opus-only client should explain an incompatible codec requirement instead of silently failing voice. Server requests for PTT, positional settings, or a minimum client version are currently invisible.
  **Done when:** display suggestions without silently overriding user settings; handle Opus availability explicitly. Adding CELT/Speex is not required for the stated 1.5/1.6 Opus target. Sources: `framing.rs`, `client.rs`; upstream `Messages.cpp`.

<a id="pro-04"></a>

- [ ] **PRO-04 · P2 · Missing — Add listener volume adjustment and restoration.**
  Channel listening exists, and received modern voice volume adjustments are applied. However, `UserState.listening_volume_adjustment` is neither stored nor sent, and no per-listener volume UI exists.
  **Done when:** adjust and display a listening channel's volume independently; accept server updates, persist desired listeners by server, and restore valid listeners after reconnect. Sources: `state.rs`, `client.rs`, `ChannelRowView.swift`; upstream [listener handling](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/Messages.cpp).

<a id="pro-05"></a>

- [ ] **PRO-05 · P2 · Missing — Add QueryUsers name/ID resolution for ACL editing.**
  QueryUsers (14) is unhandled. The editor tries the full registered-user list and online users, although permissions to query all registrations can differ from ACL access. Group members are primarily raw registered IDs, and groups have no removal control.
  **Done when:** resolve ACL IDs and entered names through QueryUsers, edit/remove local groups, preserve inherited rules/members, and show denied/time-out states. Sources: `ChannelPrivilegesModal.swift`, `client.rs`, `lib.rs`; upstream [ACLEditor.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/ACLEditor.cpp).

<a id="pro-06"></a>

- [ ] **PRO-06 · P2 · Missing — Support standard server-provided context actions.**
  ContextActionModify (16) and outgoing ContextAction (17) are absent from dispatch/API/UI. These are existing Mumble protocol operations used by ordinary Murmur administration integrations, not a new custom extension.
  **Done when:** scoped server/channel/user menu actions can be added, removed, invoked, and cleared on disconnect; labels remain untrusted text. Sources: `framing.rs`, `client.rs`, context menus; upstream `Messages.cpp`.

<a id="pro-07"></a>

- [ ] **PRO-07 · P2 · Missing — Expose newer ban choices and existing-ban editing.**
  `ban_certificate` and `ban_ip` exist in the vendored schema but `ban_user` only sets `ban=true`. The ban editor adds/removes entries rather than editing their full certificate/name/reason/expiry data.
  **Done when:** offer IP/certificate choices when supported, preserve legacy behavior on 1.5, and edit a server-returned entry without losing fields. Sources: `client.rs`, `BanListModal.swift`; upstream [1.6 ban handling](https://github.com/mumble-voip/mumble/blob/v1.6.0-alpha2/src/murmur/Messages.cpp).

<a id="pro-08"></a>

- [ ] **PRO-08 · P1 · Bug — Validate bans before sending and reconcile with the server.**
  The ban form only rejects empty IPs; `UInt32(newMask)` can trap on a negative value. Invalid addresses become all-zero IPv6 bytes in `encode_ban_ip`. Ban-list writes update local state optimistically and use a cached whole-list snapshot, risking stale edits.
  **Done when:** Rust validates addresses/prefixes and returns errors; Swift uses safe conversion; reload the authoritative list after writes and expose stale/concurrent changes. Sources: `BanListModal.swift`, `MumbleStore.addBan/removeBan`, `client.rs`.

<a id="pro-09"></a>

- [ ] **PRO-09 · P2 · Missing — Finish user administration actions.**
  The core can register another session, but user context menus only expose self-registration. The ACL editor exposes Reset User Content permission, but no command/UI resets another user's comment/avatar. Online nickname changes are also absent from the public command API.
  **Done when:** add permission-aware actions backed by standard UserState/UserList operations, with target identity and authoritative feedback; keep self-renaming subject to actual Murmur rules. Sources: `UserContextMenuView.swift`, `UserRowView.swift`, `client.rs`; upstream `MainWindow.cpp` and Murmur `Messages.cpp`.

<a id="pro-10"></a>

- [ ] **PRO-10 · P2 · Bug — Make permissions and operation results consistent across UI paths.**
  The SwiftUI user menu disables several unauthorized operations; the AppKit menu explicitly disables automatic item validation and leaves equivalent admin actions enabled. Registration/avatar/ban edits sometimes log success or dismiss before server acceptance; ACL dialogs can wait indefinitely after denial. Permission refresh uses a finite queue without delivery feedback.
  **Done when:** one permission model drives menus, toolbar, drag/drop, and dialogs; server replies/denials reconcile optimistic state; pending operations have timeouts. Sources: `UserContextMenuView.swift`, `UserRowView.swift`, `ChannelPrivilegesModal.swift`, `MumbleStore.swift`, `client.rs`.

<a id="pro-11"></a>

- [ ] **PRO-11 · P2 · Missing — Preserve full text-message addressing.**
  Incoming TextMessage keeps only the first channel/session and discards `tree_id`; the bridge model cannot represent multiple recipients or channel-tree messages. Outgoing APIs only address one channel or one user.
  **Done when:** preserve recipients and tree targets, show the destination, and support upstream-style subtree/multiple-recipient sending where useful. Test server messages without an actor separately from private messages. Sources: `client.rs`, `ChatMessage` in `lib.rs`, `MumbleStore.swift`.

<a id="pro-12"></a>

- [ ] **PRO-12 · P2 · Improve — Finish incremental state and blob semantics.**
  Comments, textures, and descriptions are fetched eagerly whenever hashes arrive, without a hash cache; empty/changed hashes do not directly invalidate cached content. Full link replacement only runs for a nonempty `links` list, so empty-list versus delta semantics need explicit upstream comparison. Removed users are not immediately removed from mixer state.
  **Done when:** invalidate/fetch/cache blobs by content hash, bound outstanding fetches, handle cleared content/link snapshots correctly, and release removed-user audio immediately. Sources: `state.rs`, `client.rs`, `audio_mixer.rs`.

<a id="pro-13"></a>

- [ ] **PRO-13 · P2 · Bug — Make diagnostics describe actual data.**
  UserStats ignores 1.6 `rolling_stats`, assigns any received certificate the name “Swimble User,” and UI substitutes missing OS/version/IP with macOS/1.5.0/127.0.0.1. Zero-valued statistics are sometimes treated as missing and replaced by different counters. Bandwidth units should be checked against upstream before display.
  **Done when:** expose unavailable fields as unavailable, parse actual certificate metadata, distinguish directions/units, and display rolling-window statistics when provided. Sources: `client.rs`, `UserStatsInfo` in `lib.rs`, `UserStatsModal.swift`, `ServerInformationModal.swift`.

## Audio, recording, positioning, and shortcuts

<a id="aud-01"></a>

- [ ] **AUD-01 · P1 · Bug — Adapt packet duration as well as bitrate to bandwidth limits.**
  `apply_bitrate` subtracts fixed transport overhead and floors the encoder at 6 kbit/s. At sufficiently low server limits, short packets can exceed the entire allowance through overhead alone. Original Mumble can lengthen packets while adapting quality.
  **Done when:** budget actual legacy/modern framing and positional data, adapt duration or report an impossible budget, and test low-limit servers with sustained voice. Sources: `audio_mixer.rs`; compare [AudioInput.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/AudioInput.cpp).

<a id="aud-02"></a>

- [ ] **AUD-02 · P1 · Verify — Make jitter recovery robust to variable durations and stream gaps.**
  Missing-frame duration is inferred from the previous decode. Recovery can advance past queued sequence keys, but the render loop does not explicitly discard all queued keys older than its next sequence. Adaptive delay mainly affects initial priming; continuous-stream clock drift and overfull recovery lack strong evidence.
  **Done when:** deterministic loss/reorder/duplicate tests cover packet-duration changes, missing terminators, long pauses, clock skew, queue saturation, and sequence extremes; stale packets cannot keep concealment running. Source: `audio_mixer.rs`.

<a id="aud-03"></a>

- [x] **AUD-03 · P1 · Bug — Apply local mute/volume changes immediately to buffered audio.**
  `set_user_local_volume` changes the state map, while the mixer's user gain is updated only when another voice packet arrives. Already-buffered audio can continue with the old volume, including after Local Mute.
  **Done when:** the next rendered block observes local gain changes, including the tail of an ended stream, without waiting for a new packet. Sources: `client.rs`, `audio_mixer.rs`, local-volume controls in `MumbleStore.swift`.

<a id="aud-04"></a>

- [ ] **AUD-04 · P1 · Verify — Define target transitions and competing transmission inputs.**
  Buffered microphone samples are not associated with the target used when they were captured. PTT, whisper, transmission latch, UI controls, and RPC all write a common active flag, so one release can cancel another held input. Reconnect can retain a target not registered on the new server.
  **Done when:** flush/terminate the old stream before changing destinations; arbitrate held inputs, release on permission/input loss, and test overlapping PTT/whisper/latch/RPC with hold times. Sources: `audio_mixer.rs`, `audio_io.rs`, `GlobalPTT.swift`, `LocalControl.swift`.

<a id="aud-05"></a>

- [ ] **AUD-05 · P1 · Bug — Detect actual user activity for idle actions.**
  `recordUserActivity` is called only by mute/deafen toggles. Normal speaking, PTT, keyboard/mouse activity, and chat do not reset the idle timer. “Set AFK” currently just mutes and logs an AFK message.
  **Done when:** define and implement activity semantics, reset/restore idle state across sessions, and either implement a documented AFK-channel action or rename the existing option accurately. Sources: `MumbleStore.swift`, `GlobalPTT.swift`, `SettingsState.swift`.

<a id="aud-06"></a>

- [ ] **AUD-06 · P1 · Improve — Support receive-only audio and explain hardware failures.**
  Engine startup always configures input and installs a microphone tap. Voice-processing enable/disable failures are only printed, so the UI may imply AEC is active when it is not. Hardware and microphone authorization failures need a clearer recovery path.
  **Done when:** users can listen without microphone access or an input device; actual processing/device state is visible; failed routing/start attempts can be retried without reconnecting. Sources: `MacAudioEngine.swift`, audio settings/wizard, `MumbleStore.onConnectionStatusChanged`.

<a id="aud-07"></a>

- [ ] **AUD-07 · P2 · Improve — Isolate recording/plugin work from the audio worker.**
  WAV writes occur on the same Tokio worker path that resamples/feeds playback, write/finalize errors are discarded, and plugin polling holds the mixer mutex. Slow storage or a blocking native plugin can disrupt audio/network scheduling. User-selected plugin initialization also runs synchronously through the UI-facing call.
  **Done when:** bounded worker handoffs isolate blocking work; recording errors reach the UI and stop cleanly; plugin polling cannot monopolize the mixer; capture/playback callbacks remain allocation/lock/file/network free. Sources: `audio_io.rs`, `plugins.rs`, `client.rs`, `native/plugin_host.cpp`.

<a id="aud-08"></a>

- [ ] **AUD-08 · P2 · Missing — Preserve stereo Opus sources where applicable.**
  Playback is stereo, but each incoming Opus decoder is mono, collapsing stereo source material before positioning/mixing. Original Mumble's receive path supports stereo decoding.
  **Done when:** preserve source channels with explicit mono/spatial routing rules and stereo interoperability tests; mono microphone capture remains valid. Sources: `audio_mixer.rs`; upstream [AudioOutputSpeech.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/AudioOutputSpeech.cpp).

<a id="aud-09"></a>

- [ ] **AUD-09 · P2 · Improve — Finish audio calibration and recording UX.**
  The wizard edits live engine values while persisted settings use a separate model; the displayed VAD threshold can differ from the configured hysteresis thresholds. Its “Stop Test Sound” action only changes UI state. Recording always uses one fixed Music directory and a mic-left/remote-right WAV, and can be started while disconnected without a running sample clock.
  **Done when:** calibration saves the actual thresholds/devices, test sound can stop, recording preconditions/errors are visible, and users can choose a destination. Per-speaker tracks, mixdown, naming templates, and compressed formats are optional upstream parity. Sources: audio wizard/settings, `AudioRecorder.swift`, `audio_io.rs`; upstream [VoiceRecorder.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/VoiceRecorder.cpp).

<a id="aud-10"></a>

- [ ] **AUD-10 · P2 · Verify — Validate positional/plugin lifecycle across games and windows.**
  Link/manual/native sources exist. Verify source-enable semantics, stale Link data, context/identity clearing, finite orientation vectors, plugin unlink/relink, process-list failures, and loading the same library in multiple windows. Each host currently initializes the modern plugin with ID 1, and plugins may have process-global state.
  **Done when:** matching/mismatching game contexts interoperate with original Mumble, disabled sources stop publishing, and multiple sessions cannot initialize/shutdown each other's plugin state. Sources: `positional.rs`, `plugins.rs`, `audio_mixer.rs`, `native/plugin_host.cpp`, `AdvancedAudioSettings.swift`.

## SwiftUI, messaging, preferences, and native behavior

<a id="ux-01"></a>

- [ ] **UX-01 · P1 · Bug — Make TTS controls authoritative.**
  `EventNotificationManager` calls `TTSEngine.speak` directly; that method does not check `isEnabled`, `readChatMessages`, or `readChannelEvents`. Console logging independently calls `speakEvent`, so event speech can bypass the matrix or be duplicated. “Read message text” disabled still includes the message in `detail`.
  **Done when:** one event-routing path honors the master/category/matrix controls, suppresses message bodies when requested, and bounds speech queues. Sources: `EventNotificationManager.swift`, `TTSEngine.swift`, `MumbleStore.logSystemMessage`.

<a id="ux-02"></a>

- [ ] **UX-02 · P2 · Bug — Make settings Apply/Cancel/Reset transactional and shared.**
  Main settings bind a global singleton directly and apply it to only one store. Advanced preferences persist/apply on every change outside the snapshot. Closing the view applies settings; Reset/Cancel cannot reliably undo every advanced or live-preview change.
  **Done when:** a defined draft/snapshot covers the complete settings surface, Cancel restores previewed effects, Apply updates all intended sessions, and concurrent settings windows cannot overwrite each other. Sources: `SettingsState.swift`, `ClientPreferences.swift`, `SettingsView.swift`, `SettingsModal.swift`, `SettingsFooterView.swift`.

<a id="ux-03"></a>

- [ ] **UX-03 · P2 · Bug — Share bookmark storage across windows and validate edits.**
  Each store loads its own bookmark array and writes the whole array to the same preference, enabling lost updates. Invalid port text silently becomes 64738 and zero is accepted. Duplicating a bookmark copies its now-empty in-memory password rather than the Keychain password.
  **Done when:** one repository owns bookmark mutations; invalid host/port input has inline errors; duplicate credentials follow a deliberate policy; failed Keychain saves do not continue as if editing succeeded. Sources: `MumbleStore.swift`, `ServerConnectSheet.swift`, `ServerBookmark.swift`.

<a id="ux-04"></a>

- [ ] **UX-04 · P2 · Missing — Persist local user preferences by certificate identity.**
  Friends/nicknames already use certificate hashes; local mute, volume, and text ignore use transient session IDs and are not persisted. Original Mumble stores corresponding user preferences by hash.
  **Done when:** restore those preferences for the same identity, safely scope users without certificates, and avoid affecting a different person who receives a recycled session ID. Sources: `ClientPreferences.swift`, `MumbleStore.swift`; upstream [Database.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/Database.cpp).

<a id="ux-05"></a>

- [ ] **UX-05 · P2 · Improve — Give chat stable identity and explicit destinations.**
  Chat rows use enumerated array offsets as identity; trimming history reassigns those IDs. `filteredChatMessages` returns the entire server log despite the selected-channel heading, and the view scrolls to the bottom on incoming changes even while someone reads history.
  **Done when:** stable message IDs survive trimming, destinations/private senders are clear, history can be searched, and auto-scroll follows reader intent. Dedicated private conversations, multiline composition, and log export are useful follow-ups. Sources: `ChatAndActivityView.swift`, `ChatMessage` in `lib.rs` or a Swift presentation wrapper.

<a id="ux-06"></a>

- [ ] **UX-06 · P2 · Bug — Route typed events instead of inferring them from English text.**
  Permission notifications look for “Permission denied,” while core denial strings often say “You were denied” or “Denied:”. Several matrix events, including kicks, are not dispatched through their named routes; core and Swift can emit duplicate connection/user/recording activity.
  **Done when:** typed core events carry actors, targets, reasons, and severity; render text once and apply notification/TTS/sound choices once. Sources: `client.rs`, `lib.rs`, `MumbleStore.swift`, `EventNotificationManager.swift`.

<a id="ux-07"></a>

- [ ] **UX-07 · P2 · Bug — Isolate drag/drop and channel navigation by server.**
  A draggable user exports only a decimal session ID. Dropping it in another server window can issue a move for an unrelated local session with the same ID. Channel-path lookup also falls back to a global name match after hierarchy lookup fails.
  **Done when:** drag payloads include session/server identity and reject cross-server moves; URL paths resolve deterministically and report missing/ambiguous channels instead of joining an unrelated match. Sources: `UserRowView.swift`, `ChannelRowView.swift`, `MumbleStore.findChannel/searchChannelSubtree`.

<a id="ux-08"></a>

- [ ] **UX-08 · P2 · Improve — Unify active-session ownership and window lifecycle.**
  Global shortcuts/RPC use the last-focused store, while application menus may fall back to the last-created store. The overlay binds a particular store; window/tab creation relies on AppKit selectors, and SwiftUI disappearance triggers shutdown.
  **Done when:** menu bar, menu commands, RPC, shortcuts, and overlay show/control the same explicitly selected session; new tab/window and tab switching have lifecycle tests; hiding/switching a view does not unexpectedly disconnect. Sources: `App.swift`, `GlobalPTT.swift`, `LocalControl.swift`, `SessionFocusObserver.swift`, `FloatingOverlayWindow.swift`.

<a id="ux-09"></a>

- [ ] **UX-09 · P2 · Improve — Complete accessibility and responsive layouts.**
  Image previews use tap gestures; many icon/state controls rely on symbols, color, or tooltips rather than explicit accessible labels/values. Several dialogs have fixed dimensions and very small text. There is little explicit Reduce Motion handling.
  **Done when:** keyboard and VoiceOver can navigate tree, controls, menus, chat, images, and dialogs; state is announced; large text/contrast/reduced motion remain usable. Keep the existing NavigationSplitView and Liquid Glass HUD. Verify overlay glass grouping/IDs and duplicate morph identities as states change. Sources: `MacClient/Sources/Views/`.

<a id="ux-10"></a>

- [ ] **UX-10 · P2 · Improve — Reduce repeated rendering and consolidate duplicate components.**
  HTML parsing, regex extraction, avatar decoding, and full tree rebuilding occur on frequently invalidated UI paths. Large chat/store/settings files combine independent responsibilities. SwiftUI/AppKit user menus and multiple settings/certificate surfaces already differ in behavior.
  **Done when:** cache parsed/image presentation data, isolate talking/meter updates, share action validation and settings components, and profile large servers before choosing optimizations. Add guards for malformed/cyclic channel hierarchies. Sources: `MumbleStore.swift`, `ChannelTreeNode.swift`, `ChatAndActivityView.swift`, user menus and settings views.

<a id="ux-11"></a>

- [ ] **UX-11 · P2 · Missing — Add localization and finish user-facing settings semantics.**
  Most UI/protocol event strings are hardcoded English and no localization catalog exists. `highlightFavoriteEntriesOnTop` is saved but not consumed by bookmark sorting. The overlay setting is named “FPS” although its value is display refresh rate, read from `NSScreen.main` rather than the actual overlay screen.
  **Done when:** extract localizable strings/plurals, test long translations, wire or remove inactive settings, and label refresh rate accurately without implying measured game FPS. Sources: `MacClient/Sources/`, `SettingsState.swift`, `FloatingOverlayWindow.swift`.

<a id="ux-12"></a>

- [ ] **UX-12 · P3 · Missing — Add LAN discovery and migration conveniences.**
  Public-directory browsing and saved servers already exist. Original Mumble additionally discovers LAN servers through Bonjour; Swimble has no equivalent browser. Import/export of original Mumble favorites/settings is also absent, although certificate import exists.
  **Done when:** optionally discover standard `_mumble._tcp` services, support bookmark exchange/import, and keep imported credentials out of plain preferences. Sources: `ServerConnectSheet.swift`, `MumistService.swift`, `dns.rs`; upstream [ConnectDialog.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/ConnectDialog.cpp).

## Tests and continuous integration

<a id="test-01"></a>

- [ ] **TEST-01 · P1 · Verify — Restore the local Murmur fixture and rerun live suites.**
  At audit time Docker's socket was unavailable and `127.0.0.1:64738` refused connections. Four live tests consequently failed; this does not establish a protocol regression. Some fixture failures surface as missing certificate-challenge unwraps rather than a clear readiness failure.
  **Done when:** the documented `murmur-test` fixture is reachable, all local tests pass, and missing fixtures fail early with a useful explanation. Keep destructive ACL tests isolated on 64739. Sources: `rust-core/tests/murmur_integration.rs`, `scripts/test_acl.sh`.

<a id="test-02"></a>

- [ ] **TEST-02 · P1 · Missing — Pin and test both supported server versions.**
  CI and the admin helper use `mumblevoip/mumble-server:latest`; that is not reproducible evidence for both 1.5 and 1.6 compatibility.
  **Done when:** use pinned image digests or reproducible builds for 1.5.939 and the chosen 1.6 RC; cover UDP and forced TCP, self-signed trust, IPv4/IPv6, permissions, listeners, bans, server policies, and reconnects. Sources: `.github/workflows/ci.yml`, `scripts/test_acl.sh`.

<a id="test-03"></a>

- [ ] **TEST-03 · P1 · Missing — Test against the original Mumble client, not only another Swimble endpoint.**
  Existing live audio tests primarily pair Swimble cores and synthetic PCM. Symmetric bugs can pass that arrangement.
  **Done when:** record bidirectional original-Mumble↔Swimble voice, PTT/terminators, whisper/shout/listen, priority, positioning contexts, text/images, and recording-state interoperability on both server families. Include malformed/lossy network scenarios separately.

<a id="test-04"></a>

- [ ] **TEST-04 · P1 · Missing — Add deterministic lifecycle, policy, and credential regressions.**
  Swift's seven general regression cases cover URLs, bookmark encoding, one formatting path, and one transmission-hold path. Store reconnection, per-server credentials, identity corruption/migration, policy handling, TTS routing, settings cancellation, and multi-window behavior have no equivalent coverage.
  **Done when:** add focused tests for SEC-01/02/03, NET-01/02, PRO-01/02, UX-01/02/03/07/08, using fake events, isolated preference suites, and disposable credential services rather than the user's data. Source: `MacClient/Tests/ClientRegressionTests.swift`.

<a id="test-05"></a>

- [ ] **TEST-05 · P2 · Improve — Make tests hermetic and assertions meaningful.**
  `ping::tests::test_ping_outside_tokio_context` contacts a real community server even though another remote integration case is ignored. `test_parse_mumble_openssl_p12` silently does nothing when optional `/tmp` files are absent. The mixer performance test reports timing without a regression criterion.
  **Done when:** replace routine remote dependencies with local fixtures; commit/generate real PKCS#12 fixtures; separate benchmarks from correctness tests and make skipped prerequisites explicit. Sources: `ping.rs`, `cert.rs`, `audio_mixer.rs`.

<a id="test-06"></a>

- [ ] **TEST-06 · P1 · Verify — Exercise real audio hardware and concurrent sessions.**
  Hardware tests were skipped because microphone authorization was not already granted. Synthetic checks do not establish AEC quality, Bluetooth behavior, hot-plug routing, separate-device clock behavior, or multiple AVAudioEngine interactions.
  **Done when:** record authorized manual/automated evidence for built-in/USB/Bluetooth devices, 44.1/48/96 kHz, sleep/wake, device removal, receive-only mode, simultaneous server windows, AEC/ducking, and loss recovery. Measure mouth-to-ear latency and idle/active CPU rather than inferring them.

<a id="test-07"></a>

- [ ] **TEST-07 · P2 · Improve — Add formatting/lint and bridge freshness checks to CI.**
  CI builds/tests but does not run rustfmt or Clippy, and generated artifacts/project files can drift from sources. FFI ABI/ownership contracts and `unsafe` audio endpoints deserve explicit checks.
  **Done when:** CI checks formatting/lints, runs fresh bridge/XcodeGen generation with drift detection where deterministic, and exercises sanitizers/stress checks appropriate to Rust/C++/Swift boundaries. Preserve `project.yml` as the project source of truth. Sources: `.github/workflows/ci.yml`, `scripts/build_bridge.sh`, `NativeAudioBridge.h`, `audio_io.rs`.

## Packaging, documentation, and optional parity decisions

<a id="rel-01"></a>

- [ ] **REL-01 · P2 · Improve — Verify compatible universal Opus builds and development fallbacks.**
  The original audit build warned that Homebrew `libopus.0.dylib` was built for macOS 27 while Swimble targets macOS 26. The merged universal-binary contribution now builds macOS 26 Opus for both architectures in CI and release builds, and puts that library before Homebrew fallbacks. Verify those new paths and keep fallback-only local builds from silently linking an incompatible library.
  **Done when:** all advertised macOS 26 build paths link a compatible library; validate the final app's minimum OS, both architecture slices, and dependencies on clean Apple Silicon and Intel macOS 26 systems. Sources: `project.yml`, `build_opus.sh`, `build_release.sh`, `.github/workflows/ci.yml`.

<a id="rel-02"></a>

- [ ] **REL-02 · P2 · Improve — Make signing/notarization a verified release gate when credentials are available.**
  The pipeline already supports Developer ID and notarization; Releases from 1.3.1 onward are signed and notarized. Do not list signing support as unimplemented.
  **Done when:** publish a signed/notarized release through the existing path and verify Gatekeeper, stapling, plugin loading, microphone/accessibility behavior, DMG layout, checksum, and bundled CLI on a clean machine. Sources: `scripts/RELEASING.md`, `package_dmg.py`, `Swimble.entitlements`.

<a id="rel-03"></a>

- [ ] **REL-03 · P2 · Improve — Inventory and bundle third-party notices.**
  Mumble protocol licensing and bundled Opus notices are present. There is no complete generated inventory/notices bundle for the statically linked Rust dependency graph and native adapter dependencies.
  **Done when:** produce an SBOM/license inventory, review dependencies, and include required notices in release artifacts and an accessible acknowledgments view/file. Add dependency-update/advisory review to maintenance without claiming an unverified vulnerability. Sources: `Cargo.toml`, `Cargo.lock`, `project.yml`, `package_dmg.py`, `LICENSE`.

<a id="rel-04"></a>

- [ ] **REL-04 · P2 · Improve — Document the build environment and audit limitations accurately.**
  A normal terminal `xcodebuild` failed with CommandLineTools selected; explicitly selecting the installed Xcode for the command succeeded. README's claim that local tests do not depend on a community server conflicts with the unignored ping unit test. Some capabilities depend on hardware or fixtures not checked in CI.
  **Done when:** add prerequisite checks for Xcode/SDK/toolchain/Docker/Opus, distinguish source support from verified interoperability, and maintain this backlog as behavior changes. Sources: `README.md`, `scripts/check_versions.py`, `scripts/RELEASING.md`.

<a id="rel-05"></a>

- [ ] **REL-05 · P3 · Optional — Decide the remaining upstream feature boundaries explicitly.**
  Full general Mumble plugin hosting and PluginDataTransmission (26), plugin installation/update UI, broader shortcut vocabulary, injected game overlays, legacy codecs, advanced recording formats, and minimalist window modes are not equivalent to current features. A local floating overlay, positional-only plugin adapter, and universal-binary build pipeline already exist.
  **Done when:** record which differences are intentional and only schedule those with a concrete macOS use case. A full plugin host must preserve the Rust networking boundary. Keep screensharing, webcams, custom server extensions, and Murmur server implementation out of scope. References: upstream [PluginManager.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/PluginManager.cpp), `MainWindow.cpp`, `VoiceRecorder.cpp`; local README and `AGENTS.md`.

## Validation performed for this audit

| Check | Result | Interpretation |
| --- | --- | --- |
| `./scripts/check_versions.py` | Passed; 1.2.1 | Manifest/app versions agree |
| `cargo fmt --manifest-path rust-core/Cargo.toml -- --check` | Passed | Current Rust formatting is clean |
| `cargo test --manifest-path rust-core/Cargo.toml --locked -- --test-threads=1` | 33 unit tests passed; integration: 1 passed, 4 failed, 2 ignored | The fixture-dependent failures occurred with no reachable local Murmur; the passed integration case covers synthetic recording gates |
| `docker ps` | Failed: Docker socket unavailable | Could not verify/start the documented container through the running Docker service |
| Required `xcodebuild ... build` | Passed using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` | Existing generated bridge/static library built with the Swift frontend; this was not a fresh bridge-regeneration check |
| `xcodebuild ... -parallel-testing-enabled NO test` | Passed: 7 executed/passed, 2 skipped | Hardware preview and explicitly gated microphone authorization were skipped |
| Xcode build warning | Homebrew Opus minimum OS 27.0 versus target 26.0 | Development dependency issue; release Opus pipeline has a separate macOS 26 build |
| UI/hardware/product walkthrough | Not performed | Accessibility, AEC quality, real-device routing, and visual/full-screen behavior remain verification tasks |
| Signing/notarization/DMG generation | Not performed | Existing release scripts were reviewed, not executed for publication |

No protocol or application fixes are included in this document-only change. The audit does not claim every upstream feature was exercised or every possible defect found. Confirm source-derived risks with the listed regression/interoperability tests before marking them resolved.

## Upstream source map

Use the pinned release references above when implementing; upstream `master` describes future behavior and can change.

| Comparison area | Primary upstream sources |
| --- | --- |
| Control/voice fields | [1.5 Mumble.proto](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/Mumble.proto), [1.6 Mumble.proto](https://github.com/mumble-voip/mumble/blob/v1.6.0-alpha2/src/Mumble.proto), [MumbleUDP.proto](https://github.com/mumble-voip/mumble/blob/v1.6.0-alpha2/src/MumbleUDP.proto) |
| Server authority and policies | [Murmur Messages.cpp](https://github.com/mumble-voip/mumble/blob/v1.6.0-alpha2/src/murmur/Messages.cpp), [Murmur Server.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/murmur/Server.cpp), [ACL documentation](https://www.mumble.info/documentation/administration/acl/) |
| Client protocol dispatch | [Messages.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/Messages.cpp), [ServerHandler.cpp](https://github.com/mumble-voip/mumble/blob/v1.6.0-alpha2/src/mumble/ServerHandler.cpp) |
| Audio and crypto | [AudioInput.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/AudioInput.cpp), [AudioOutputSpeech.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/AudioOutputSpeech.cpp), [CryptStateOCB2.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/crypto/CryptStateOCB2.cpp) |
| User/channel actions and preferences | [MainWindow.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/MainWindow.cpp), [Database.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/Database.cpp), [ACLEditor.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/ACLEditor.cpp) |
| Connections and discovery | [ConnectDialog.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/ConnectDialog.cpp), [NetworkConfig.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/NetworkConfig.cpp) |
| Recording, shortcuts, plugins | [VoiceRecorder.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/VoiceRecorder.cpp), [GlobalShortcut.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/GlobalShortcut.cpp), [PluginManager.cpp](https://github.com/mumble-voip/mumble/blob/v1.5.939/src/mumble/PluginManager.cpp) |
