import Foundation
import Observation

public struct WhisperPreset: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "Whisper"
    public var serverKey = ""
    public var channelId: UInt32?
    public var group = ""
    public var children = false
    public var links = false
    public var userHashes: [String] = []
    public var shortcut: PTTKeybind?
}
public enum ShortcutCommand: String, Codable, CaseIterable, Identifiable, Sendable {
    case pushToMute = "Push to mute", toggleTransmission = "Toggle transmission", joinChannel = "Join channel", toggleListening = "Toggle channel listening"
    public var id: String { rawValue }
}
public struct ActionShortcut: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var command: ShortcutCommand = .pushToMute
    public var serverKey = ""
    public var channelId: UInt32 = 0
    public var shortcut: PTTKeybind?
}

/// Non-secret preferences; all writes are small and UI-owned. Credentials are
/// deliberately absent from this model and its UserDefaults representation.
@Observable @MainActor
public final class ClientPreferences {
    public static let shared = ClientPreferences()
    public var bitrateKbps = 64 { didSet { save() } }
    public var packetDurationMs = 20 { didSet { save() } }
    public var forwardErrorCorrection = true { didSet { save() } }
    public var minimumDistance = 1.0 { didSet { save() } }
    public var maximumDistance = 50.0 { didSet { save() } }
    public var farVolume = 0.0 { didSet { save() } }
    public var positionalBloom = 0.25 { didSet { save() } }
    public var manualPositionEnabled = false { didSet { save() } }
    public var manualX = 0.0 { didSet { save() } }
    public var manualY = 0.0 { didSet { save() } }
    public var manualZ = 0.0 { didSet { save() } }
    public var manualHeading = 0.0 { didSet { save() } }
    public var manualContext = "" { didSet { save() } }
    public var pluginPaths: [String] = [] { didSet { save() } }
    public var friends: Set<String> = [] { didSet { save() } }
    public var nicknames: [String: String] = [:] { didSet { save() } }
    public var whisperPresets: [WhisperPreset] = [] { didSet { save() } }
    public var shortcuts: [ActionShortcut] = [] { didSet { save() } }
    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "Swimble_AdvancedPreferences"), let value = try? JSONDecoder().decode(Snapshot.self, from: data) {
            bitrateKbps = value.bitrateKbps; packetDurationMs = value.packetDurationMs; forwardErrorCorrection = value.fec
            minimumDistance = value.minDistance; maximumDistance = value.maxDistance; farVolume = value.farVolume; positionalBloom = value.bloom
            manualPositionEnabled = value.manual; manualX = value.x; manualY = value.y; manualZ = value.z; manualHeading = value.heading; manualContext = value.context
            pluginPaths = value.plugins; friends = value.friends; nicknames = value.nicknames; whisperPresets = value.presets; shortcuts = value.shortcuts
        }
    }
    private struct Snapshot: Codable {
        var bitrateKbps: Int; var packetDurationMs: Int; var fec: Bool
        var minDistance: Double; var maxDistance: Double; var farVolume: Double; var bloom: Double
        var manual: Bool; var x: Double; var y: Double; var z: Double; var heading: Double; var context: String
        var plugins: [String]; var friends: Set<String>; var nicknames: [String: String]
        var presets: [WhisperPreset]; var shortcuts: [ActionShortcut]
    }
    private func save() {
        let value = Snapshot(bitrateKbps: bitrateKbps, packetDurationMs: packetDurationMs, fec: forwardErrorCorrection,
                             minDistance: minimumDistance, maxDistance: maximumDistance, farVolume: farVolume, bloom: positionalBloom,
                             manual: manualPositionEnabled, x: manualX, y: manualY, z: manualZ, heading: manualHeading, context: manualContext,
                             plugins: pluginPaths, friends: friends, nicknames: nicknames, presets: whisperPresets, shortcuts: shortcuts)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "Swimble_AdvancedPreferences") }
        for store in MumbleStore.activeStores { apply(to: store) }
    }
    public func apply(to store: MumbleStore) {
        store.client.configureAudioQuality(bitrate: UInt32(max(6, min(128, bitrateKbps)) * 1000), packetMs: UInt32(packetDurationMs), fec: forwardErrorCorrection)
        store.client.configurePositioning(minimumDistance: Float(minimumDistance), maximumDistance: Float(maximumDistance), farVolume: Float(farVolume), bloom: Float(positionalBloom),
                                          manual: manualPositionEnabled, x: Float(manualX), y: Float(manualY), z: Float(manualZ), heading: Float(manualHeading), context: manualContext)
    }
    public func displayName(_ user: UserInfo) -> String { user.certHash.flatMap { nicknames[$0] }.flatMap { $0.isEmpty ? nil : $0 } ?? user.name }
    public func isFriend(_ user: UserInfo) -> Bool { user.certHash.map { friends.contains($0) } ?? false }
}
