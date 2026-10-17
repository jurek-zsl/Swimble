import SwiftUI
import AppKit

// MARK: - Enums for Settings

public enum TransmitMode: String, CaseIterable, Identifiable, Sendable {
    case voiceActivity = "Voice Activity"
    case continuous = "Continuous"
    case pushToTalk = "Push To Talk"

    public var id: String { rawValue }
}

public enum VadMode: String, CaseIterable, Identifiable, Sendable {
    case amplitude = "Amplitude"
    case signalToNoise = "Signal to Noise"

    public var id: String { rawValue }
}

public enum NoiseSuppressionMode: String, CaseIterable, Identifiable, Sendable {
    case disabled = "Disabled"
    case speex = "Speex"
    case rnnoise = "RNNoise"
    case both = "Both"

    public var id: String { rawValue }
}

public enum IdleActionType: String, CaseIterable, Identifiable, Sendable {
    case doNothing = "Do nothing"
    case muteSelf = "Mute Self"
    case deafenSelf = "Deafen Self"
    case setAfk = "Set AFK"

    public var id: String { rawValue }
}

public enum LoopbackMode: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case local = "Local"
    case server = "Server"

    public var id: String { rawValue }
}

public enum UserSortMode: String, CaseIterable, Identifiable, Sendable {
    case alphabetically = "Alphabetically"
    case byId = "By ID"

    public var id: String { rawValue }
}

public enum ProxyType: String, CaseIterable, Identifiable, Sendable {
    case direct = "Direct connection"
    case http = "HTTP(S) proxy"
    case socks5 = "SOCKS5 proxy"

    public var id: String { rawValue }
}

public enum SoundfileMode: String, CaseIterable, Identifiable, Sendable {
    case defaultSound = "Default"
    case customSound = "Custom sound file"

    public var id: String { rawValue }
}

public enum OverlayPositionPreset: String, CaseIterable, Identifiable, Sendable {
    case topLeft = "Top-Left"
    case topRight = "Top-Right"
    case bottomLeft = "Bottom-Left"
    case bottomRight = "Bottom-Right"
    case custom = "Custom"

    public var id: String { rawValue }
}

// MARK: - Data Models for Tables

public struct ShortcutBindingItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var function: String
    public var data: String
    public var shortcut: String
    public var suppress: Bool

    public init(id: UUID = UUID(), function: String, data: String = "", shortcut: String, suppress: Bool = false) {
        self.id = id
        self.function = function
        self.data = data
        self.shortcut = shortcut
        self.suppress = suppress
    }
}

public struct EventNotificationItem: Identifiable, Sendable {
    public var id: String { eventName }
    public var eventName: String
    public var console: Bool
    public var notification: Bool
    public var tts: Bool
    public var soundfile: Bool

    public init(eventName: String, console: Bool = true, notification: Bool = true, tts: Bool = false, soundfile: Bool = true) {
        self.eventName = eventName
        self.console = console
        self.notification = notification
        self.tts = tts
        self.soundfile = soundfile
    }
}

// MARK: - Settings State Store

@Observable
@MainActor
public final class SettingsState {
    public static let shared = SettingsState()

    // 1. Audio Input
    public var audioInputSystem: String = "CoreAudio"
    public var audioInputDevice: String = ""
    public var audioInputExclusiveMode: Bool = false
    public var transmitMode: TransmitMode = .voiceActivity
    public var vadMode: VadMode = .amplitude
    public var voiceHold: Double = 0.20
    public var silenceBelowDb: Double = -50.0
    public var speechAboveDb: Double = -35.0
    public var pttDoublePushTime: Double = 0.00
    public var pttHoldTime: Double = 0.00
    public var pttAudioCue: Bool = false
    public var pttOnCuePath: String = ""
    public var pttOffCuePath: String = ""
    public var qualityBitrateKbps: Double = 145.3
    public var audioPacketFrameSizeMs: Int = 10
    public var allowLowDelayMode: Bool = true
    public var maxAmplification: Double = 3.76
    public var echoCancellation: Bool = true
    public var noiseSuppressionMode: NoiseSuppressionMode = .speex
    public var noiseSuppressionLevelDb: Double = -15.0
    public var muteMicrophoneCue: Bool = true
    public var muteCuePath: String = ""
    public var highlightMicIconWhenOpen: Bool = true
    public var idleActionTimeoutMinutes: Int = 5
    public var idleActionType: IdleActionType = .doNothing
    public var undoIdleActionOnActivity: Bool = true

    // 2. Audio Output
    public var audioOutputSystem: String = "CoreAudio"
    public var audioOutputDevice: String = ""
    public var outputDelayMs: Double = 20.0
    public var audioOutputExclusiveMode: Bool = false
    public var defaultJitterBufferMs: Double = 10.0
    public var outputVolumePercent: Double = 100.0
    public var minVolumePercent: Double = 0.0
    public var attenuateByPercent: Double = 50.0
    public var attenuateWhileOthersTalk: Bool = true
    public var attenuateWhileYouTalk: Bool = false
    public var duckingVolumePercent: Double = 20.0
    public var onlyAttenuateSameAsSystem: Bool = true
    public var attenuateSystemOutput: Bool = false
    public var loopbackMode: LoopbackMode = .none
    public var loopbackDelayVarianceMs: Double = 0.0
    public var loopbackPacketLossPercent: Double = 0.0
    public var positionalAudioHeadphones: Bool = true
    public var positionalMinDistanceM: Double = 1.0
    public var positionalMaxDistanceM: Double = 15.0
    public var positionalMinVolumePercent: Double = 30.0
    public var positionalBloomPercent: Double = 175.0

    // 3. User Interface
    public var uiStyle: String = "macOS Liquid Glass"
    public var uiTheme: String = "System Default"
    public var uiLanguage: String = "System Default"
    public var displayQuitConfirmation: Bool = false
    public var includeUnreadCountInTaskbar: Bool = true
    public var layoutPreset: String = "Classic"
    public var lockLayout: Bool = false
    public var showContextMenuOnMenuBar: Bool = true
    public var minimalViewTooltip: Bool = false
    public var channelTreeExpand: String = "All"
    public var userSort: UserSortMode = .alphabetically
    public var channelDrag: String = "Move"
    public var hoverUserShowsVolume: Bool = true
    public var askBeforeDraggingChannel: Bool = true
    public var alwaysShowChannelUserCount: Bool = true
    public var filterHidesEmptyChannels: Bool = false
    public var showUserAvatarInTooltip: Bool = true
    public var showTalkingStatusInTray: Bool = true
    public var showUserNameWhenTalking: Bool = false
    public var highlightFavoriteEntriesOnTop: Bool = true

    // 4. Shortcuts
    public var shortcuts: [ShortcutBindingItem] = [
        ShortcutBindingItem(function: "Push-to-Talk", data: "", shortcut: "Space", suppress: true),
        ShortcutBindingItem(function: "Toggle Self Mute", data: "", shortcut: "Cmd+M", suppress: false),
        ShortcutBindingItem(function: "Toggle Self Deafen", data: "", shortcut: "Cmd+D", suppress: false),
        ShortcutBindingItem(function: "Whisper to Channel", data: "Root", shortcut: "Ctrl+W", suppress: true),
    ]
    public var enableGlobalShortcuts: Bool = true
    public var handleSideMouseButtons: Bool = true

    // 5. Network
    public var useTcpCompatibilityMode: Bool = false
    public var useQosPrioritizePackets: Bool = true
    public var reconnectAutomatically: Bool = true
    public var autoConnectLastUsedServer: Bool = false
    public var suppressCertPasswordWarnings: Bool = false
    public var proxyType: ProxyType = .direct
    public var proxyHostname: String = ""
    public var proxyPort: Int = 1080
    public var proxyUsername: String = ""
    public var proxyPassword: String = ""
    public var maxImageSizeKb: Int = 0
    public var maxImageWidthPx: Int = 0
    public var maxImageHeightPx: Int = 0
    public var doNotEmbedExternalImages: Bool = false
    public var clearUserCommentsOnExit: Bool = false
    public var clearChatWindowOnExit: Bool = false
    public var hideOsInfoFromServers: Bool = false
    public var checkForUpdatesOnStartup: Bool = true
    public var downloadOfficialPluginsUpdates: Bool = true

    // 6. Messages
    public var eventsMatrix: [EventNotificationItem] = [
        EventNotificationItem(eventName: "Connected", console: true, notification: true, tts: false, soundfile: true),
        EventNotificationItem(eventName: "Disconnected", console: true, notification: true, tts: false, soundfile: true),
        EventNotificationItem(eventName: "You were kicked", console: true, notification: true, tts: true, soundfile: true),
        EventNotificationItem(eventName: "You were muted/deafened (by admin)", console: true, notification: true, tts: true, soundfile: true),
        EventNotificationItem(eventName: "You muted/deafened yourself", console: true, notification: false, tts: false, soundfile: true),
        EventNotificationItem(eventName: "Text message received", console: true, notification: true, tts: true, soundfile: true),
        EventNotificationItem(eventName: "Private text message received", console: true, notification: true, tts: true, soundfile: true),
        EventNotificationItem(eventName: "User joined channel", console: true, notification: true, tts: false, soundfile: true),
        EventNotificationItem(eventName: "User left channel", console: true, notification: true, tts: false, soundfile: true),
        EventNotificationItem(eventName: "User moved (between other channels)", console: true, notification: false, tts: false, soundfile: false),
        EventNotificationItem(eventName: "User kicked (you or by you)", console: true, notification: true, tts: true, soundfile: true),
        EventNotificationItem(eventName: "Permission denied", console: true, notification: true, tts: true, soundfile: true),
        EventNotificationItem(eventName: "Recording state changed", console: true, notification: true, tts: true, soundfile: true),
    ]
    public var soundfileMode: SoundfileMode = .defaultSound
    public var customSoundFilePath: String = ""
    public var ttsVolumePercent: Double = 85.0
    public var ttsLengthThreshold: Int = 150
    public var ttsReadMessageText: Bool = true
    public var whisperWalkieTalkieMode: Bool = false
    public var echoMultiTargetMessages: Bool = true
    public var maxChatBlockCount: Int = 5000
    public var highlightUsesRegEx: Bool = false

    // 7. Overlay
    public var overlayEnabled: Bool = false
    public var overlayPositionPreset: OverlayPositionPreset = .topRight
    public var showFpsCounter: Bool = false
    public var showCurrentTime: Bool = false
    public var overlayFontName: String = "System Default"
    public var overlayColorHex: String = "#00E5FF"

    // Snapshot storage for Reset / Cancel
    private var snapshotData: [String: Any] = [:]

    public init() {
        loadFromUserDefaults()
        takeSnapshot()
    }

    public func takeSnapshot() {
        snapshotData = [
            "audioInputExclusiveMode": audioInputExclusiveMode,
            "transmitMode": transmitMode.rawValue,
            "vadMode": vadMode.rawValue,
            "voiceHold": voiceHold,
            "silenceBelowDb": silenceBelowDb,
            "speechAboveDb": speechAboveDb,
            "pttDoublePushTime": pttDoublePushTime,
            "pttHoldTime": pttHoldTime,
            "pttAudioCue": pttAudioCue,
            "qualityBitrateKbps": qualityBitrateKbps,
            "audioPacketFrameSizeMs": audioPacketFrameSizeMs,
            "allowLowDelayMode": allowLowDelayMode,
            "maxAmplification": maxAmplification,
            "echoCancellation": echoCancellation,
            "noiseSuppressionMode": noiseSuppressionMode.rawValue,
            "noiseSuppressionLevelDb": noiseSuppressionLevelDb,
            "muteMicrophoneCue": muteMicrophoneCue,
            "highlightMicIconWhenOpen": highlightMicIconWhenOpen,
            "idleActionTimeoutMinutes": idleActionTimeoutMinutes,
            "idleActionType": idleActionType.rawValue,
            "undoIdleActionOnActivity": undoIdleActionOnActivity,
            "outputDelayMs": outputDelayMs,
            "audioOutputExclusiveMode": audioOutputExclusiveMode,
            "defaultJitterBufferMs": defaultJitterBufferMs,
            "outputVolumePercent": outputVolumePercent,
            "minVolumePercent": minVolumePercent,
            "attenuateByPercent": attenuateByPercent,
            "attenuateWhileOthersTalk": attenuateWhileOthersTalk,
            "attenuateWhileYouTalk": attenuateWhileYouTalk,
            "duckingVolumePercent": duckingVolumePercent,
            "onlyAttenuateSameAsSystem": onlyAttenuateSameAsSystem,
            "attenuateSystemOutput": attenuateSystemOutput,
            "loopbackMode": loopbackMode.rawValue,
            "loopbackDelayVarianceMs": loopbackDelayVarianceMs,
            "loopbackPacketLossPercent": loopbackPacketLossPercent,
            "positionalAudioHeadphones": positionalAudioHeadphones,
            "positionalMinDistanceM": positionalMinDistanceM,
            "positionalMaxDistanceM": positionalMaxDistanceM,
            "positionalMinVolumePercent": positionalMinVolumePercent,
            "positionalBloomPercent": positionalBloomPercent,
            "uiStyle": uiStyle,
            "uiTheme": uiTheme,
            "uiLanguage": uiLanguage,
            "displayQuitConfirmation": displayQuitConfirmation,
            "includeUnreadCountInTaskbar": includeUnreadCountInTaskbar,
            "layoutPreset": layoutPreset,
            "lockLayout": lockLayout,
            "showContextMenuOnMenuBar": showContextMenuOnMenuBar,
            "minimalViewTooltip": minimalViewTooltip,
            "channelTreeExpand": channelTreeExpand,
            "userSort": userSort.rawValue,
            "channelDrag": channelDrag,
            "hoverUserShowsVolume": hoverUserShowsVolume,
            "askBeforeDraggingChannel": askBeforeDraggingChannel,
            "alwaysShowChannelUserCount": alwaysShowChannelUserCount,
            "filterHidesEmptyChannels": filterHidesEmptyChannels,
            "showUserAvatarInTooltip": showUserAvatarInTooltip,
            "showTalkingStatusInTray": showTalkingStatusInTray,
            "showUserNameWhenTalking": showUserNameWhenTalking,
            "highlightFavoriteEntriesOnTop": highlightFavoriteEntriesOnTop,
            "enableGlobalShortcuts": enableGlobalShortcuts,
            "handleSideMouseButtons": handleSideMouseButtons,
            "useTcpCompatibilityMode": useTcpCompatibilityMode,
            "useQosPrioritizePackets": useQosPrioritizePackets,
            "reconnectAutomatically": reconnectAutomatically,
            "autoConnectLastUsedServer": autoConnectLastUsedServer,
            "suppressCertPasswordWarnings": suppressCertPasswordWarnings,
            "proxyType": proxyType.rawValue,
            "proxyHostname": proxyHostname,
            "proxyPort": proxyPort,
            "proxyUsername": proxyUsername,
            "maxImageSizeKb": maxImageSizeKb,
            "maxImageWidthPx": maxImageWidthPx,
            "maxImageHeightPx": maxImageHeightPx,
            "doNotEmbedExternalImages": doNotEmbedExternalImages,
            "clearUserCommentsOnExit": clearUserCommentsOnExit,
            "clearChatWindowOnExit": clearChatWindowOnExit,
            "hideOsInfoFromServers": hideOsInfoFromServers,
            "checkForUpdatesOnStartup": checkForUpdatesOnStartup,
            "downloadOfficialPluginsUpdates": downloadOfficialPluginsUpdates,
            "soundfileMode": soundfileMode.rawValue,
            "ttsVolumePercent": ttsVolumePercent,
            "ttsLengthThreshold": ttsLengthThreshold,
            "ttsReadMessageText": ttsReadMessageText,
            "whisperWalkieTalkieMode": whisperWalkieTalkieMode,
            "echoMultiTargetMessages": echoMultiTargetMessages,
            "maxChatBlockCount": maxChatBlockCount,
            "highlightUsesRegEx": highlightUsesRegEx,
            "overlayEnabled": overlayEnabled,
            "overlayPositionPreset": overlayPositionPreset.rawValue,
            "showFpsCounter": showFpsCounter,
            "showCurrentTime": showCurrentTime,
            "overlayFontName": overlayFontName,
            "overlayColorHex": overlayColorHex
        ]
    }

    public func resetToSnapshot() {
        if let v = snapshotData["audioInputExclusiveMode"] as? Bool { audioInputExclusiveMode = v }
        if let s = snapshotData["transmitMode"] as? String, let m = TransmitMode(rawValue: s) { transmitMode = m }
        if let s = snapshotData["vadMode"] as? String, let m = VadMode(rawValue: s) { vadMode = m }
        if let v = snapshotData["voiceHold"] as? Double { voiceHold = v }
        if let v = snapshotData["silenceBelowDb"] as? Double { silenceBelowDb = v }
        if let v = snapshotData["speechAboveDb"] as? Double { speechAboveDb = v }
        if let v = snapshotData["pttDoublePushTime"] as? Double { pttDoublePushTime = v }
        if let v = snapshotData["pttHoldTime"] as? Double { pttHoldTime = v }
        if let v = snapshotData["pttAudioCue"] as? Bool { pttAudioCue = v }
        if let v = snapshotData["qualityBitrateKbps"] as? Double { qualityBitrateKbps = v }
        if let v = snapshotData["audioPacketFrameSizeMs"] as? Int { audioPacketFrameSizeMs = v }
        if let v = snapshotData["allowLowDelayMode"] as? Bool { allowLowDelayMode = v }
        if let v = snapshotData["maxAmplification"] as? Double { maxAmplification = v }
        if let v = snapshotData["echoCancellation"] as? Bool { echoCancellation = v }
        if let s = snapshotData["noiseSuppressionMode"] as? String, let m = NoiseSuppressionMode(rawValue: s) { noiseSuppressionMode = m }
        if let v = snapshotData["noiseSuppressionLevelDb"] as? Double { noiseSuppressionLevelDb = v }
        if let v = snapshotData["muteMicrophoneCue"] as? Bool { muteMicrophoneCue = v }
        if let v = snapshotData["highlightMicIconWhenOpen"] as? Bool { highlightMicIconWhenOpen = v }
        if let v = snapshotData["idleActionTimeoutMinutes"] as? Int { idleActionTimeoutMinutes = v }
        if let s = snapshotData["idleActionType"] as? String, let m = IdleActionType(rawValue: s) { idleActionType = m }
        if let v = snapshotData["undoIdleActionOnActivity"] as? Bool { undoIdleActionOnActivity = v }
        if let v = snapshotData["outputDelayMs"] as? Double { outputDelayMs = v }
        if let v = snapshotData["audioOutputExclusiveMode"] as? Bool { audioOutputExclusiveMode = v }
        if let v = snapshotData["defaultJitterBufferMs"] as? Double { defaultJitterBufferMs = v }
        if let v = snapshotData["outputVolumePercent"] as? Double { outputVolumePercent = v }
        if let v = snapshotData["minVolumePercent"] as? Double { minVolumePercent = v }
        if let v = snapshotData["attenuateByPercent"] as? Double { attenuateByPercent = v }
        if let v = snapshotData["attenuateWhileOthersTalk"] as? Bool { attenuateWhileOthersTalk = v }
        if let v = snapshotData["attenuateWhileYouTalk"] as? Bool { attenuateWhileYouTalk = v }
        if let v = snapshotData["duckingVolumePercent"] as? Double { duckingVolumePercent = v }
        if let v = snapshotData["onlyAttenuateSameAsSystem"] as? Bool { onlyAttenuateSameAsSystem = v }
        if let v = snapshotData["attenuateSystemOutput"] as? Bool { attenuateSystemOutput = v }
        if let s = snapshotData["loopbackMode"] as? String, let m = LoopbackMode(rawValue: s) { loopbackMode = m }
        if let v = snapshotData["loopbackDelayVarianceMs"] as? Double { loopbackDelayVarianceMs = v }
        if let v = snapshotData["loopbackPacketLossPercent"] as? Double { loopbackPacketLossPercent = v }
        if let v = snapshotData["positionalAudioHeadphones"] as? Bool { positionalAudioHeadphones = v }
        if let v = snapshotData["positionalMinDistanceM"] as? Double { positionalMinDistanceM = v }
        if let v = snapshotData["positionalMaxDistanceM"] as? Double { positionalMaxDistanceM = v }
        if let v = snapshotData["positionalMinVolumePercent"] as? Double { positionalMinVolumePercent = v }
        if let v = snapshotData["positionalBloomPercent"] as? Double { positionalBloomPercent = v }
        if let v = snapshotData["uiStyle"] as? String { uiStyle = v }
        if let v = snapshotData["uiTheme"] as? String { uiTheme = v }
        if let v = snapshotData["uiLanguage"] as? String { uiLanguage = v }
        if let v = snapshotData["displayQuitConfirmation"] as? Bool { displayQuitConfirmation = v }
        if let v = snapshotData["includeUnreadCountInTaskbar"] as? Bool { includeUnreadCountInTaskbar = v }
        if let v = snapshotData["layoutPreset"] as? String { layoutPreset = v }
        if let v = snapshotData["lockLayout"] as? Bool { lockLayout = v }
        if let v = snapshotData["showContextMenuOnMenuBar"] as? Bool { showContextMenuOnMenuBar = v }
        if let v = snapshotData["minimalViewTooltip"] as? Bool { minimalViewTooltip = v }
        if let v = snapshotData["channelTreeExpand"] as? String { channelTreeExpand = v }
        if let s = snapshotData["userSort"] as? String, let m = UserSortMode(rawValue: s) { userSort = m }
        if let v = snapshotData["channelDrag"] as? String { channelDrag = v }
        if let v = snapshotData["hoverUserShowsVolume"] as? Bool { hoverUserShowsVolume = v }
        if let v = snapshotData["askBeforeDraggingChannel"] as? Bool { askBeforeDraggingChannel = v }
        if let v = snapshotData["alwaysShowChannelUserCount"] as? Bool { alwaysShowChannelUserCount = v }
        if let v = snapshotData["filterHidesEmptyChannels"] as? Bool { filterHidesEmptyChannels = v }
        if let v = snapshotData["showUserAvatarInTooltip"] as? Bool { showUserAvatarInTooltip = v }
        if let v = snapshotData["showTalkingStatusInTray"] as? Bool { showTalkingStatusInTray = v }
        if let v = snapshotData["showUserNameWhenTalking"] as? Bool { showUserNameWhenTalking = v }
        if let v = snapshotData["highlightFavoriteEntriesOnTop"] as? Bool { highlightFavoriteEntriesOnTop = v }
        if let v = snapshotData["enableGlobalShortcuts"] as? Bool { enableGlobalShortcuts = v }
        if let v = snapshotData["handleSideMouseButtons"] as? Bool { handleSideMouseButtons = v }
        if let v = snapshotData["useTcpCompatibilityMode"] as? Bool { useTcpCompatibilityMode = v }
        if let v = snapshotData["useQosPrioritizePackets"] as? Bool { useQosPrioritizePackets = v }
        if let v = snapshotData["reconnectAutomatically"] as? Bool { reconnectAutomatically = v }
        if let v = snapshotData["autoConnectLastUsedServer"] as? Bool { autoConnectLastUsedServer = v }
        if let v = snapshotData["suppressCertPasswordWarnings"] as? Bool { suppressCertPasswordWarnings = v }
        if let s = snapshotData["proxyType"] as? String, let m = ProxyType(rawValue: s) { proxyType = m }
        if let v = snapshotData["proxyHostname"] as? String { proxyHostname = v }
        if let v = snapshotData["proxyPort"] as? Int { proxyPort = v }
        if let v = snapshotData["proxyUsername"] as? String { proxyUsername = v }
        if let v = snapshotData["maxImageSizeKb"] as? Int { maxImageSizeKb = v }
        if let v = snapshotData["maxImageWidthPx"] as? Int { maxImageWidthPx = v }
        if let v = snapshotData["maxImageHeightPx"] as? Int { maxImageHeightPx = v }
        if let v = snapshotData["doNotEmbedExternalImages"] as? Bool { doNotEmbedExternalImages = v }
        if let v = snapshotData["clearUserCommentsOnExit"] as? Bool { clearUserCommentsOnExit = v }
        if let v = snapshotData["clearChatWindowOnExit"] as? Bool { clearChatWindowOnExit = v }
        if let v = snapshotData["hideOsInfoFromServers"] as? Bool { hideOsInfoFromServers = v }
        if let v = snapshotData["checkForUpdatesOnStartup"] as? Bool { checkForUpdatesOnStartup = v }
        if let v = snapshotData["downloadOfficialPluginsUpdates"] as? Bool { downloadOfficialPluginsUpdates = v }
        if let s = snapshotData["soundfileMode"] as? String, let m = SoundfileMode(rawValue: s) { soundfileMode = m }
        if let v = snapshotData["ttsVolumePercent"] as? Double { ttsVolumePercent = v }
        if let v = snapshotData["ttsLengthThreshold"] as? Int { ttsLengthThreshold = v }
        if let v = snapshotData["ttsReadMessageText"] as? Bool { ttsReadMessageText = v }
        if let v = snapshotData["whisperWalkieTalkieMode"] as? Bool { whisperWalkieTalkieMode = v }
        if let v = snapshotData["echoMultiTargetMessages"] as? Bool { echoMultiTargetMessages = v }
        if let v = snapshotData["maxChatBlockCount"] as? Int { maxChatBlockCount = v }
        if let v = snapshotData["highlightUsesRegEx"] as? Bool { highlightUsesRegEx = v }
        if let v = snapshotData["overlayEnabled"] as? Bool { overlayEnabled = v }
        if let s = snapshotData["overlayPositionPreset"] as? String, let m = OverlayPositionPreset(rawValue: s) { overlayPositionPreset = m }
        if let v = snapshotData["showFpsCounter"] as? Bool { showFpsCounter = v }
        if let v = snapshotData["showCurrentTime"] as? Bool { showCurrentTime = v }
        if let v = snapshotData["overlayFontName"] as? String { overlayFontName = v }
        if let v = snapshotData["overlayColorHex"] as? String { overlayColorHex = v }
    }

    public func restoreDefaults(for tab: SettingsTab) {
        switch tab {
        case .audioInput:
            audioInputSystem = "CoreAudio"
            audioInputDevice = ""
            audioInputExclusiveMode = false
            transmitMode = .voiceActivity
            vadMode = .amplitude
            voiceHold = 0.20
            silenceBelowDb = -50.0
            speechAboveDb = -35.0
            pttDoublePushTime = 0.00
            pttHoldTime = 0.00
            pttAudioCue = false
            qualityBitrateKbps = 145.3
            audioPacketFrameSizeMs = 10
            allowLowDelayMode = true
            maxAmplification = 3.76
            echoCancellation = true
            noiseSuppressionMode = .speex
            noiseSuppressionLevelDb = -15.0
            muteMicrophoneCue = true
            highlightMicIconWhenOpen = true
            idleActionTimeoutMinutes = 5
            idleActionType = .doNothing
            undoIdleActionOnActivity = true

        case .audioOutput:
            audioOutputSystem = "CoreAudio"
            audioOutputDevice = ""
            outputDelayMs = 20.0
            audioOutputExclusiveMode = false
            defaultJitterBufferMs = 10.0
            outputVolumePercent = 100.0
            minVolumePercent = 0.0
            attenuateByPercent = 50.0
            attenuateWhileOthersTalk = true
            attenuateWhileYouTalk = false
            duckingVolumePercent = 20.0
            onlyAttenuateSameAsSystem = true
            attenuateSystemOutput = false
            loopbackMode = .none
            loopbackDelayVarianceMs = 0.0
            loopbackPacketLossPercent = 0.0
            positionalAudioHeadphones = true
            positionalMinDistanceM = 1.0
            positionalMaxDistanceM = 15.0
            positionalMinVolumePercent = 30.0
            positionalBloomPercent = 175.0

        case .userInterface:
            uiStyle = "macOS Liquid Glass"
            uiTheme = "System Default"
            uiLanguage = "System Default"
            displayQuitConfirmation = false
            includeUnreadCountInTaskbar = true
            layoutPreset = "Classic"
            lockLayout = false
            showContextMenuOnMenuBar = true
            minimalViewTooltip = false
            channelTreeExpand = "All"
            userSort = .alphabetically
            channelDrag = "Move"
            hoverUserShowsVolume = true
            askBeforeDraggingChannel = true
            alwaysShowChannelUserCount = true
            filterHidesEmptyChannels = false
            showUserAvatarInTooltip = true
            showTalkingStatusInTray = true
            showUserNameWhenTalking = false
            highlightFavoriteEntriesOnTop = true

        case .shortcuts:
            shortcuts = [
                ShortcutBindingItem(function: "Push-to-Talk", data: "", shortcut: "Space", suppress: true),
                ShortcutBindingItem(function: "Toggle Self Mute", data: "", shortcut: "Cmd+M", suppress: false),
                ShortcutBindingItem(function: "Toggle Self Deafen", data: "", shortcut: "Cmd+D", suppress: false),
                ShortcutBindingItem(function: "Whisper to Channel", data: "Root", shortcut: "Ctrl+W", suppress: true),
            ]
            enableGlobalShortcuts = true
            handleSideMouseButtons = true

        case .network:
            useTcpCompatibilityMode = false
            useQosPrioritizePackets = true
            reconnectAutomatically = true
            autoConnectLastUsedServer = false
            suppressCertPasswordWarnings = false
            proxyType = .direct
            proxyHostname = ""
            proxyPort = 1080
            proxyUsername = ""
            proxyPassword = ""
            maxImageSizeKb = 0
            maxImageWidthPx = 0
            maxImageHeightPx = 0
            doNotEmbedExternalImages = false
            clearUserCommentsOnExit = false
            clearChatWindowOnExit = false
            hideOsInfoFromServers = false
            checkForUpdatesOnStartup = true
            downloadOfficialPluginsUpdates = true

        case .messages:
            soundfileMode = .defaultSound
            customSoundFilePath = ""
            ttsVolumePercent = 85.0
            ttsLengthThreshold = 150
            ttsReadMessageText = true
            whisperWalkieTalkieMode = false
            echoMultiTargetMessages = true
            maxChatBlockCount = 5000
            highlightUsesRegEx = false

        case .overlay:
            overlayEnabled = false
            overlayPositionPreset = .topRight
            showFpsCounter = false
            showCurrentTime = false
            overlayFontName = "System Default"
            overlayColorHex = "#00E5FF"

        default:
            break
        }
    }

    public func restoreAllDefaults() {
        for tab in SettingsTab.allCases {
            restoreDefaults(for: tab)
        }
    }

    public func apply(to store: MumbleStore) {
        // 1. Audio Engine updates
        if let engine = store.audioEngine {
            engine.vadThresholdDb = Float(silenceBelowDb)
            engine.isPushToTalk = (transmitMode == .pushToTalk)
            engine.isVoiceProcessingEnabled = echoCancellation
            engine.isAudioDuckingEnabled = (attenuateWhileOthersTalk || attenuateWhileYouTalk)
            engine.isLoopbackTestEnabled = (loopbackMode == .local)
        }

        // 2. Hardware device selection
        if !audioInputDevice.isEmpty, let dev = CoreAudioDeviceManager.shared.inputDevices.first(where: { $0.name == audioInputDevice }) {
            _ = CoreAudioDeviceManager.shared.setInputDevice(dev.id)
        }
        if !audioOutputDevice.isEmpty, let dev = CoreAudioDeviceManager.shared.outputDevices.first(where: { $0.name == audioOutputDevice }) {
            _ = CoreAudioDeviceManager.shared.setOutputDevice(dev.id)
        }

        // 3. Persist to UserDefaults
        saveToUserDefaults()

        // 4. Update overlay state
        let overlayMgr = FloatingOverlayManager.shared
        if overlayEnabled != overlayMgr.isVisible {
            overlayMgr.toggle(store: store)
        }

        // Take fresh snapshot after applying
        takeSnapshot()
    }

    private func saveToUserDefaults() {
        let d = UserDefaults.standard
        d.set(audioInputExclusiveMode, forKey: "Swimble_AudioInputExclusive")
        d.set(transmitMode.rawValue, forKey: "Swimble_TransmitMode")
        d.set(vadMode.rawValue, forKey: "Swimble_VadMode")
        d.set(voiceHold, forKey: "Swimble_VoiceHold")
        d.set(silenceBelowDb, forKey: "Swimble_SilenceBelowDb")
        d.set(speechAboveDb, forKey: "Swimble_SpeechAboveDb")
        d.set(pttDoublePushTime, forKey: "Swimble_PttDoublePush")
        d.set(pttHoldTime, forKey: "Swimble_PttHold")
        d.set(pttAudioCue, forKey: "Swimble_PttAudioCue")
        d.set(qualityBitrateKbps, forKey: "Swimble_BitrateKbps")
        d.set(audioPacketFrameSizeMs, forKey: "Swimble_FrameSizeMs")
        d.set(allowLowDelayMode, forKey: "Swimble_LowDelay")
        d.set(maxAmplification, forKey: "Swimble_MaxAmplification")
        d.set(echoCancellation, forKey: "Swimble_EchoCancellation")
        d.set(noiseSuppressionMode.rawValue, forKey: "Swimble_NoiseSuppressionMode")
        d.set(noiseSuppressionLevelDb, forKey: "Swimble_NoiseSuppressionLevel")
        d.set(muteMicrophoneCue, forKey: "Swimble_MuteMicCue")
        d.set(highlightMicIconWhenOpen, forKey: "Swimble_HighlightMic")
        d.set(idleActionTimeoutMinutes, forKey: "Swimble_IdleTimeout")
        d.set(idleActionType.rawValue, forKey: "Swimble_IdleAction")
        d.set(undoIdleActionOnActivity, forKey: "Swimble_UndoIdle")

        d.set(outputDelayMs, forKey: "Swimble_OutputDelayMs")
        d.set(audioOutputExclusiveMode, forKey: "Swimble_AudioOutputExclusive")
        d.set(defaultJitterBufferMs, forKey: "Swimble_JitterBufferMs")
        d.set(outputVolumePercent, forKey: "Swimble_OutputVolume")
        d.set(minVolumePercent, forKey: "Swimble_MinVolume")
        d.set(attenuateByPercent, forKey: "Swimble_AttenuateBy")
        d.set(attenuateWhileOthersTalk, forKey: "Swimble_AttenuateOthers")
        d.set(attenuateWhileYouTalk, forKey: "Swimble_AttenuateSelf")
        d.set(duckingVolumePercent, forKey: "Swimble_DuckingVolume")
        d.set(onlyAttenuateSameAsSystem, forKey: "Swimble_AttenuateSameSystem")
        d.set(attenuateSystemOutput, forKey: "Swimble_AttenuateSystemOut")
        d.set(loopbackMode.rawValue, forKey: "Swimble_LoopbackMode")
        d.set(loopbackDelayVarianceMs, forKey: "Swimble_LoopbackDelayVar")
        d.set(loopbackPacketLossPercent, forKey: "Swimble_LoopbackLoss")
        d.set(positionalAudioHeadphones, forKey: "Swimble_PositionalHeadphones")
        d.set(positionalMinDistanceM, forKey: "Swimble_PositionalMinDist")
        d.set(positionalMaxDistanceM, forKey: "Swimble_PositionalMaxDist")
        d.set(positionalMinVolumePercent, forKey: "Swimble_PositionalMinVol")
        d.set(positionalBloomPercent, forKey: "Swimble_PositionalBloom")

        d.set(uiStyle, forKey: "Swimble_UiStyle")
        d.set(uiTheme, forKey: "Swimble_UiTheme")
        d.set(uiLanguage, forKey: "Swimble_UiLanguage")
        d.set(displayQuitConfirmation, forKey: "Swimble_QuitConfirm")
        d.set(includeUnreadCountInTaskbar, forKey: "Swimble_UnreadBadge")
        d.set(layoutPreset, forKey: "Swimble_LayoutPreset")
        d.set(lockLayout, forKey: "Swimble_LockLayout")
        d.set(showContextMenuOnMenuBar, forKey: "Swimble_ContextMenuMenuBar")
        d.set(minimalViewTooltip, forKey: "Swimble_MinimalTooltip")
        d.set(channelTreeExpand, forKey: "Swimble_ChannelExpand")
        d.set(userSort.rawValue, forKey: "Swimble_UserSort")
        d.set(channelDrag, forKey: "Swimble_ChannelDrag")
        d.set(hoverUserShowsVolume, forKey: "Swimble_HoverUserVol")
        d.set(askBeforeDraggingChannel, forKey: "Swimble_AskDragChannel")
        d.set(alwaysShowChannelUserCount, forKey: "Swimble_ShowChannelCount")
        d.set(filterHidesEmptyChannels, forKey: "Swimble_FilterHideEmpty")
        d.set(showUserAvatarInTooltip, forKey: "Swimble_AvatarTooltip")
        d.set(showTalkingStatusInTray, forKey: "Swimble_TrayTalkingStatus")
        d.set(showUserNameWhenTalking, forKey: "Swimble_TrayUserName")
        d.set(highlightFavoriteEntriesOnTop, forKey: "Swimble_HighlightFavorites")

        d.set(enableGlobalShortcuts, forKey: "Swimble_EnableGlobalShortcuts")
        d.set(handleSideMouseButtons, forKey: "Swimble_HandleSideMouse")

        d.set(useTcpCompatibilityMode, forKey: "Swimble_TcpMode")
        d.set(useQosPrioritizePackets, forKey: "Swimble_UseQos")
        d.set(reconnectAutomatically, forKey: "Swimble_ReconnectAuto")
        d.set(autoConnectLastUsedServer, forKey: "Swimble_AutoConnectLast")
        d.set(suppressCertPasswordWarnings, forKey: "Swimble_SuppressCertWarnings")
        d.set(proxyType.rawValue, forKey: "Swimble_ProxyType")
        d.set(proxyHostname, forKey: "Swimble_ProxyHost")
        d.set(proxyPort, forKey: "Swimble_ProxyPort")
        d.set(proxyUsername, forKey: "Swimble_ProxyUser")
        d.set(maxImageSizeKb, forKey: "Swimble_MaxImageSize")
        d.set(maxImageWidthPx, forKey: "Swimble_MaxImageWidth")
        d.set(maxImageHeightPx, forKey: "Swimble_MaxImageHeight")
        d.set(doNotEmbedExternalImages, forKey: "Swimble_NoExternalImages")
        d.set(clearUserCommentsOnExit, forKey: "Swimble_ClearCommentsExit")
        d.set(clearChatWindowOnExit, forKey: "Swimble_ClearChatExit")
        d.set(hideOsInfoFromServers, forKey: "Swimble_HideOsInfo")
        d.set(checkForUpdatesOnStartup, forKey: "Swimble_CheckUpdates")
        d.set(downloadOfficialPluginsUpdates, forKey: "Swimble_PluginUpdates")

        d.set(soundfileMode.rawValue, forKey: "Swimble_SoundfileMode")
        d.set(ttsVolumePercent, forKey: "Swimble_TtsVolume")
        d.set(ttsLengthThreshold, forKey: "Swimble_TtsThreshold")
        d.set(ttsReadMessageText, forKey: "Swimble_TtsReadMessage")
        d.set(whisperWalkieTalkieMode, forKey: "Swimble_WhisperWalkie")
        d.set(echoMultiTargetMessages, forKey: "Swimble_EchoMultiTarget")
        d.set(maxChatBlockCount, forKey: "Swimble_MaxChatBlocks")
        d.set(highlightUsesRegEx, forKey: "Swimble_HighlightRegex")

        d.set(overlayEnabled, forKey: "Swimble_OverlayEnabled")
        d.set(overlayPositionPreset.rawValue, forKey: "Swimble_OverlayPreset")
        d.set(showFpsCounter, forKey: "Swimble_ShowFps")
        d.set(showCurrentTime, forKey: "Swimble_ShowCurrentTime")
        d.set(overlayFontName, forKey: "Swimble_OverlayFont")
        d.set(overlayColorHex, forKey: "Swimble_OverlayColor")
    }

    private func loadFromUserDefaults() {
        let d = UserDefaults.standard
        if d.object(forKey: "Swimble_TransmitMode") != nil {
            if let s = d.string(forKey: "Swimble_TransmitMode"), let m = TransmitMode(rawValue: s) { transmitMode = m }
            if let s = d.string(forKey: "Swimble_VadMode"), let m = VadMode(rawValue: s) { vadMode = m }
            voiceHold = d.double(forKey: "Swimble_VoiceHold")
            silenceBelowDb = d.double(forKey: "Swimble_SilenceBelowDb")
            speechAboveDb = d.double(forKey: "Swimble_SpeechAboveDb")
            qualityBitrateKbps = d.double(forKey: "Swimble_BitrateKbps")
            audioPacketFrameSizeMs = d.integer(forKey: "Swimble_FrameSizeMs")
            if qualityBitrateKbps == 0 { qualityBitrateKbps = 145.3 }
            if audioPacketFrameSizeMs == 0 { audioPacketFrameSizeMs = 10 }
            if voiceHold == 0 { voiceHold = 0.20 }
            if silenceBelowDb == 0 { silenceBelowDb = -50.0 }
            if speechAboveDb == 0 { speechAboveDb = -35.0 }
            allowLowDelayMode = d.bool(forKey: "Swimble_LowDelay")
            maxAmplification = d.double(forKey: "Swimble_MaxAmplification")
            if maxAmplification == 0 { maxAmplification = 3.76 }
            echoCancellation = d.object(forKey: "Swimble_EchoCancellation") == nil ? true : d.bool(forKey: "Swimble_EchoCancellation")
            if let s = d.string(forKey: "Swimble_NoiseSuppressionMode"), let m = NoiseSuppressionMode(rawValue: s) { noiseSuppressionMode = m }
            noiseSuppressionLevelDb = d.double(forKey: "Swimble_NoiseSuppressionLevel")
            if noiseSuppressionLevelDb == 0 { noiseSuppressionLevelDb = -15.0 }
        }
    }
}
