import XCTest
@testable import Swimble

final class ClientRegressionTests: XCTestCase {
    func testExternalResourcesAreStrippedBeforeHTMLImport() {
        let html = #"<p>hi</p><img src="https://evil.example/a.png"><img src='//evil.example/b.png'><link rel="stylesheet" href="https://evil.example/x.css"><div style="background:url(https://evil.example/c.png)">x</div><img src="data:image/png;base64,AAAA">"#
        let out = stripExternalResources(html)
        XCTAssertFalse(out.contains("evil.example"))
        XCTAssertTrue(out.contains("data:image/png"))
        XCTAssertTrue(out.contains("<p>hi</p>"))
    }

    func testAccessTokensAreScopedPerServer() {
        let a = "[test-a-\(UUID().uuidString)]:64738", b = "[test-b-\(UUID().uuidString)]:64738"
        defer { KeychainHelper.updateAccessTokens(serverKey: a) { $0.removeAll() }; KeychainHelper.updateAccessTokens(serverKey: b) { $0.removeAll() } }
        KeychainHelper.updateAccessTokens(serverKey: a) { $0 = ["secret-a"] }
        XCTAssertEqual(KeychainHelper.loadAccessTokens(serverKey: a), ["secret-a"])
        XCTAssertEqual(KeychainHelper.loadAccessTokens(serverKey: b), [])
    }

    func testConnectionEpochDiscardsCallbacksCapturedBeforeABump() {
        let epoch = ConnectionEpoch()
        let captured = epoch.value
        XCTAssertEqual(captured, epoch.value)
        epoch.bump() // a newer connect()/disconnect()
        XCTAssertNotEqual(captured, epoch.value, "a callback captured before the bump must be treated as stale")
    }

    @MainActor func testDisconnectDropsSessionScopedState() {
        let store = MumbleStore()
        store.userVolumes[5] = 0.2
        store.userLocalMutes[5] = true
        store.ignoredTextMessageUsers = [5, 6]
        store.isWhispering = true
        let before = store.connectionEpoch.value
        store.disconnect()
        XCTAssertTrue(store.userVolumes.isEmpty)
        XCTAssertTrue(store.userLocalMutes.isEmpty)
        XCTAssertTrue(store.ignoredTextMessageUsers.isEmpty)
        XCTAssertFalse(store.isWhispering)
        XCTAssertNotEqual(before, store.connectionEpoch.value)
        XCTAssertTrue(store.recordingAllowed, "recording is allowed until a server says otherwise")
        XCTAssertNil(store.recordingBlockedReason)
    }

    func testURLPortsAreValidatedWithoutTrapping() {
        for port in ["0", "65536", "70000", "999999999"] {
            XCTAssertNil(MumbleURLParser.parse(string: "mumble://localhost:\(port)"))
        }
        XCTAssertEqual(MumbleURLParser.parse(string: "mumble://localhost:65535")?.port, 65535)
        XCTAssertEqual(MumbleURLParser.parse(string: "mumble://localhost")?.port, 64738)
    }
    func testIPv6AndUnicodeChannelURLs() {
        let value = MumbleURLParser.parse(string: "mumble://[::1]:64738/Lobby/Gaming%20Room")
        XCTAssertNotNil(value)
        XCTAssertEqual(value?.channelPath, ["Lobby", "Gaming Room"])
    }
    func testBookmarkEncodingNeverContainsPassword() throws {
        let bookmark = ServerBookmark(name: "test", host: "localhost", username: "user", password: "secret-must-not-serialize")
        let data = try JSONEncoder().encode(bookmark)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret-must-not-serialize")); XCTAssertFalse(text.contains("password"))
        XCTAssertNil(try JSONDecoder().decode(ServerBookmark.self, from: data).password)
    }
    func testLegacyBookmarkCanBeReadForMigration() throws {
        let text = """
        {"id":"E25C3D3A-7D8B-4930-AEE7-B66323414947","name":"legacy","host":"localhost","port":64738,"username":"user","password":"old-secret","isFavorite":false}
        """
        let bookmark = try JSONDecoder().decode(ServerBookmark.self, from: Data(text.utf8))
        XCTAssertEqual(bookmark.password, "old-secret")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(bookmark), as: UTF8.self).contains("old-secret"))
    }
    @MainActor func testIPv6HostNormalization() {
        XCTAssertEqual(MumbleStore.cleanServerHost("[::1]"), "::1")
        XCTAssertEqual(MumbleStore.cleanServerHost("mumble://[2001:db8::1]:64738"), "2001:db8::1")
        XCTAssertEqual(MumbleStore.cleanServerHost("example.com:64738"), "example.com")
    }
    @MainActor func testChatFormattingKeepsTextAndStripsBlockNewlines() {
        let value = parseChatMessageBody("<p><b>Hello</b> <i>world</i></p>")
        XCTAssertEqual(String(value.characters), "Hello world")
    }
    func testTransmissionHoldUsesConfiguredThresholds() {
        let state = AudioTransmitState()
        state.configureTransmission(mode: .pushToTalk, silenceDb: -50, speechDb: -35, voiceHold: 0.2, pttHold: 0.1)
        state.setPushToTalkActive(true, now: 1)
        XCTAssertTrue(state.processAudio(db: -90, now: 1).shouldTransmit)
        state.setTemporaryMute(true)
        XCTAssertFalse(state.processAudio(db: -10, now: 1.01).shouldTransmit)
        state.setTemporaryMute(false); state.setPushToTalkActive(false, now: 2)
        XCTAssertTrue(state.processAudio(db: -90, now: 2.05).shouldTransmit)
        XCTAssertFalse(state.processAudio(db: -90, now: 2.2).shouldTransmit)
    }
}

import AVFoundation

private final class AudioTestEvents: MumbleEventHandler, @unchecked Sendable {
    func onConnectionStatusChanged(status: ConnectionStatus) {}
    func onServerIdentityChallenge(challenge: ServerIdentityChallenge) {}
    func onChannelAclReceived(acl: ChannelAcl) {}
    func onChannelsUpdated(channels: [ChannelInfo]) {}
    func onUsersUpdated(users: [UserInfo]) {}
    func onUserTalkingChanged(sessionId: UInt32, isTalking: Bool, talkingState: TalkingState) {}
    func onChatMessage(message: ChatMessage) {}
    func onPingUpdated(tcpMs: Float, udpMs: Float, usingUdpTunnel: Bool) {}
    func onServerConnectionInfoUpdated(info: ServerConnectionInfo) {}
    func onRegisteredUsersUpdated(users: [RegisteredUser]) {}
    func onBanListUpdated(bans: [BanEntryInfo]) {}
    func onUserStatsReceived(stats: UserStatsInfo) {}
    func onConnectionError(kind: ConnectionErrorKind, message: String) {}
    func onCommandFailed(command: String, reason: String) {}
}

final class AudioHardwareRegressionTests: XCTestCase {
    @MainActor func testOfflineMicrophonePreviewAndEngineRestart() async throws {
        if ProcessInfo.processInfo.environment["SWIMBLE_REQUEST_MICROPHONE"] == "1",
           AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        try XCTSkipUnless(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "Microphone access must already be authorized; tests never request additional permissions.")
        let manager = CoreAudioDeviceManager.shared
        manager.refreshDevices()
        let originalInput = manager.selectedInputDeviceID
        let originalOutput = manager.selectedOutputDeviceID
        let client = MumbleClient(handler: AudioTestEvents())
        let audio = MacAudioEngine(client: client)
        audio.isMuted = true // No microphone PCM can be sent to a server.
        audio.beginPreview()
        defer { audio.endPreview(); audio.stop() }
        try await Task.sleep(for: .seconds(3))
        XCTAssertTrue(audio.isRunning, audio.lastError ?? "Offline preview must start audio hardware")
        XCTAssertGreaterThan(client.audioMetrics().micFramesProcessed, 0)
        XCTAssertGreaterThanOrEqual(audio.playbackChannelCount, 2, "Positional playback must preserve stereo")
        if let input = manager.inputDevices.first(where: { $0.id == originalInput }),
           let output = manager.outputDevices.first(where: { $0.id == originalOutput }) {
            audio.selectDevices(input: input.uid, output: output.uid)
            try await Task.sleep(for: .seconds(3))
            XCTAssertTrue(audio.isRunning, audio.lastError ?? "Explicit app-scoped device selection must work")
        }
        let before = client.audioMetrics().micFramesProcessed
        audio.restartForHardwareChange()
        try await Task.sleep(for: .seconds(3))
        XCTAssertTrue(audio.isRunning, audio.lastError ?? "Audio must restart after a hardware configuration change")
        XCTAssertGreaterThan(client.audioMetrics().micFramesProcessed, before)
        audio.endPreview()
        XCTAssertFalse(audio.isRunning)
        manager.refreshDevices()
        XCTAssertEqual(manager.selectedInputDeviceID, originalInput, "App routing must not change the system input")
        XCTAssertEqual(manager.selectedOutputDeviceID, originalOutput, "App routing must not change the system output")
    }
}

final class ManualMicrophoneAuthorizationTests: XCTestCase {
    @MainActor func testAuthorizedLocalMicrophoneRequest() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWIMBLE_REQUEST_MICROPHONE"] == "1", "Run only after explicit user approval.")
        let authorized = await AVCaptureDevice.requestAccess(for: .audio)
        XCTAssertTrue(authorized,"Grant microphone access to Swimble to run local hardware verification.")
    }
}
