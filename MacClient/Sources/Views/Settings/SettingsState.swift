import SwiftUI
import AppKit

// MARK: - Enums for Settings

public enum TransmitMode: String, CaseIterable, Identifiable, Sendable {
    case voiceActivity = "Voice Activity"
    case continuous = "Continuous"
    case pushToTalk = "Push To Talk"

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
    case local = "Local Test"

    public var id: String { rawValue }
}

public enum UserSortMode: String, CaseIterable, Identifiable, Sendable {
    case alphabetically = "Alphabetically"
    case byId = "By ID"

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

public struct EventNotificationItem: Identifiable, Sendable, Codable {
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
    public var audioInputDevice: String = ""
    public var transmitMode: TransmitMode = .voiceActivity
    public var voiceHold: Double = 0.20
    public var silenceBelowDb: Double = -50.0
    public var speechAboveDb: Double = -35.0
    public var pttHoldTime: Double = 0.05
    public var pttAudioCue: Bool = false
    public var pttOnCuePath: String = ""
    public var pttOffCuePath: String = ""
    public var maxAmplification: Double = 2.0
    public var echoCancellation: Bool = true
    public var airPodsAudioLockEnabled: Bool = true
    public var muteMicrophoneCue: Bool = true
    public var muteCuePath: String = ""
    public var highlightMicIconWhenOpen: Bool = true
    public var idleActionTimeoutMinutes: Int = 5
    public var idleActionType: IdleActionType = .doNothing
    public var undoIdleActionOnActivity: Bool = true

    // 2. Audio Output
    public var audioOutputDevice: String = ""
    public var defaultJitterBufferMs: Double = 10.0
    public var outputVolumePercent: Double = 100.0
    public var audioDuckingEnabled: Bool = false
    public var loopbackMode: LoopbackMode = .none

    // 3. User Interface
    public var uiTheme: String = "System Default"
    public var displayQuitConfirmation: Bool = false
    public var includeUnreadCountInTaskbar: Bool = true
    public var userSort: UserSortMode = .alphabetically
    public var hoverUserShowsVolume: Bool = true
    public var alwaysShowChannelUserCount: Bool = true
    public var filterHidesEmptyChannels: Bool = false
    public var showTalkingStatusInTray: Bool = true
    public var showUserNameWhenTalking: Bool = false
    public var highlightFavoriteEntriesOnTop: Bool = true

    // 4. Shortcuts
    public var enableGlobalShortcuts: Bool = true
    public var handleSideMouseButtons: Bool = true

    // 5. Network
    public var useTcpCompatibilityMode: Bool = false
    public var reconnectAutomatically: Bool = true
    public var autoConnectLastUsedServer: Bool = false
    public var suppressCertPasswordWarnings: Bool = false
    public var doNotEmbedExternalImages: Bool = false
    public var clearUserCommentsOnExit: Bool = false
    public var clearChatWindowOnExit: Bool = false
    public var hideOsInfoFromServers: Bool = false
    public var checkForUpdatesOnStartup: Bool = true

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
    public var maxChatBlockCount: Int = 5000

    // 7. Overlay
    public var overlayEnabled: Bool = false
    public var overlayPositionPreset: OverlayPositionPreset = .topRight
    public var showFpsCounter: Bool = false
    public var showCurrentTime: Bool = false
    public var overlayColorHex: String = "#00E5FF"

    // Snapshot storage for Reset / Cancel
    private var snapshotData: [String: Any] = [:]

    public init() {
        loadFromUserDefaults()
        takeSnapshot()
    }

    public func takeSnapshot() {
        snapshotData = [
            "audioInputDevice": audioInputDevice,
            "transmitMode": transmitMode.rawValue,
            "voiceHold": voiceHold,
            "silenceBelowDb": silenceBelowDb,
            "speechAboveDb": speechAboveDb,
            "pttHoldTime": pttHoldTime,
            "pttAudioCue": pttAudioCue,
            "pttOnCuePath": pttOnCuePath,
            "pttOffCuePath": pttOffCuePath,
            "maxAmplification": maxAmplification,
            "echoCancellation": echoCancellation,
            "airPodsAudioLockEnabled": airPodsAudioLockEnabled,
            "muteMicrophoneCue": muteMicrophoneCue,
            "muteCuePath": muteCuePath,
            "highlightMicIconWhenOpen": highlightMicIconWhenOpen,
            "idleActionTimeoutMinutes": idleActionTimeoutMinutes,
            "idleActionType": idleActionType.rawValue,
            "undoIdleActionOnActivity": undoIdleActionOnActivity,
            "audioOutputDevice": audioOutputDevice,
            "defaultJitterBufferMs": defaultJitterBufferMs,
            "outputVolumePercent": outputVolumePercent,
            "audioDuckingEnabled": audioDuckingEnabled,
            "loopbackMode": loopbackMode.rawValue,
            "uiTheme": uiTheme,
            "displayQuitConfirmation": displayQuitConfirmation,
            "includeUnreadCountInTaskbar": includeUnreadCountInTaskbar,
            "userSort": userSort.rawValue,
            "hoverUserShowsVolume": hoverUserShowsVolume,
            "alwaysShowChannelUserCount": alwaysShowChannelUserCount,
            "filterHidesEmptyChannels": filterHidesEmptyChannels,
            "showTalkingStatusInTray": showTalkingStatusInTray,
            "showUserNameWhenTalking": showUserNameWhenTalking,
            "highlightFavoriteEntriesOnTop": highlightFavoriteEntriesOnTop,
            "enableGlobalShortcuts": enableGlobalShortcuts,
            "handleSideMouseButtons": handleSideMouseButtons,
            "useTcpCompatibilityMode": useTcpCompatibilityMode,
            "reconnectAutomatically": reconnectAutomatically,
            "autoConnectLastUsedServer": autoConnectLastUsedServer,
            "suppressCertPasswordWarnings": suppressCertPasswordWarnings,
            "doNotEmbedExternalImages": doNotEmbedExternalImages,
            "clearUserCommentsOnExit": clearUserCommentsOnExit,
            "clearChatWindowOnExit": clearChatWindowOnExit,
            "hideOsInfoFromServers": hideOsInfoFromServers,
            "checkForUpdatesOnStartup": checkForUpdatesOnStartup,
            "soundfileMode": soundfileMode.rawValue,
            "customSoundFilePath": customSoundFilePath,
            "ttsVolumePercent": ttsVolumePercent,
            "ttsLengthThreshold": ttsLengthThreshold,
            "ttsReadMessageText": ttsReadMessageText,
            "maxChatBlockCount": maxChatBlockCount,
            "overlayEnabled": overlayEnabled,
            "overlayPositionPreset": overlayPositionPreset.rawValue,
            "showFpsCounter": showFpsCounter,
            "showCurrentTime": showCurrentTime,
            "overlayColorHex": overlayColorHex,
            "eventsMatrix": eventsMatrix
        ]
    }

    public func resetToSnapshot() {
        if let v = snapshotData["audioInputDevice"] as? String { audioInputDevice = v }
        if let s = snapshotData["transmitMode"] as? String, let m = TransmitMode(rawValue: s) { transmitMode = m }
        if let v = snapshotData["voiceHold"] as? Double { voiceHold = v }
        if let v = snapshotData["silenceBelowDb"] as? Double { silenceBelowDb = v }
        if let v = snapshotData["speechAboveDb"] as? Double { speechAboveDb = v }
        if let v = snapshotData["pttHoldTime"] as? Double { pttHoldTime = v }
        if let v = snapshotData["pttAudioCue"] as? Bool { pttAudioCue = v }
        if let v = snapshotData["pttOnCuePath"] as? String { pttOnCuePath = v }
        if let v = snapshotData["pttOffCuePath"] as? String { pttOffCuePath = v }
        if let v = snapshotData["maxAmplification"] as? Double { maxAmplification = v }
        if let v = snapshotData["echoCancellation"] as? Bool { echoCancellation = v }
        if let v = snapshotData["airPodsAudioLockEnabled"] as? Bool { airPodsAudioLockEnabled = v }
        if let v = snapshotData["muteMicrophoneCue"] as? Bool { muteMicrophoneCue = v }
        if let v = snapshotData["muteCuePath"] as? String { muteCuePath = v }
        if let v = snapshotData["highlightMicIconWhenOpen"] as? Bool { highlightMicIconWhenOpen = v }
        if let v = snapshotData["idleActionTimeoutMinutes"] as? Int { idleActionTimeoutMinutes = v }
        if let s = snapshotData["idleActionType"] as? String, let m = IdleActionType(rawValue: s) { idleActionType = m }
        if let v = snapshotData["undoIdleActionOnActivity"] as? Bool { undoIdleActionOnActivity = v }
        if let v = snapshotData["audioOutputDevice"] as? String { audioOutputDevice = v }
        if let v = snapshotData["defaultJitterBufferMs"] as? Double { defaultJitterBufferMs = v }
        if let v = snapshotData["outputVolumePercent"] as? Double { outputVolumePercent = v }
        if let v = snapshotData["audioDuckingEnabled"] as? Bool { audioDuckingEnabled = v }
        if let s = snapshotData["loopbackMode"] as? String, let m = LoopbackMode(rawValue: s) { loopbackMode = m }
        if let v = snapshotData["uiTheme"] as? String { uiTheme = v }
        if let v = snapshotData["displayQuitConfirmation"] as? Bool { displayQuitConfirmation = v }
        if let v = snapshotData["includeUnreadCountInTaskbar"] as? Bool { includeUnreadCountInTaskbar = v }
        if let s = snapshotData["userSort"] as? String, let m = UserSortMode(rawValue: s) { userSort = m }
        if let v = snapshotData["hoverUserShowsVolume"] as? Bool { hoverUserShowsVolume = v }
        if let v = snapshotData["alwaysShowChannelUserCount"] as? Bool { alwaysShowChannelUserCount = v }
        if let v = snapshotData["filterHidesEmptyChannels"] as? Bool { filterHidesEmptyChannels = v }
        if let v = snapshotData["showTalkingStatusInTray"] as? Bool { showTalkingStatusInTray = v }
        if let v = snapshotData["showUserNameWhenTalking"] as? Bool { showUserNameWhenTalking = v }
        if let v = snapshotData["highlightFavoriteEntriesOnTop"] as? Bool { highlightFavoriteEntriesOnTop = v }
        if let v = snapshotData["enableGlobalShortcuts"] as? Bool { enableGlobalShortcuts = v }
        if let v = snapshotData["handleSideMouseButtons"] as? Bool { handleSideMouseButtons = v }
        if let v = snapshotData["useTcpCompatibilityMode"] as? Bool { useTcpCompatibilityMode = v }
        if let v = snapshotData["reconnectAutomatically"] as? Bool { reconnectAutomatically = v }
        if let v = snapshotData["autoConnectLastUsedServer"] as? Bool { autoConnectLastUsedServer = v }
        if let v = snapshotData["suppressCertPasswordWarnings"] as? Bool { suppressCertPasswordWarnings = v }
        if let v = snapshotData["doNotEmbedExternalImages"] as? Bool { doNotEmbedExternalImages = v }
        if let v = snapshotData["clearUserCommentsOnExit"] as? Bool { clearUserCommentsOnExit = v }
        if let v = snapshotData["clearChatWindowOnExit"] as? Bool { clearChatWindowOnExit = v }
        if let v = snapshotData["hideOsInfoFromServers"] as? Bool { hideOsInfoFromServers = v }
        if let v = snapshotData["checkForUpdatesOnStartup"] as? Bool { checkForUpdatesOnStartup = v }
        if let s = snapshotData["soundfileMode"] as? String, let m = SoundfileMode(rawValue: s) { soundfileMode = m }
        if let v = snapshotData["customSoundFilePath"] as? String { customSoundFilePath = v }
        if let v = snapshotData["ttsVolumePercent"] as? Double { ttsVolumePercent = v }
        if let v = snapshotData["ttsLengthThreshold"] as? Int { ttsLengthThreshold = v }
        if let v = snapshotData["ttsReadMessageText"] as? Bool { ttsReadMessageText = v }
        if let v = snapshotData["maxChatBlockCount"] as? Int { maxChatBlockCount = v }
        if let v = snapshotData["overlayEnabled"] as? Bool { overlayEnabled = v }
        if let s = snapshotData["overlayPositionPreset"] as? String, let m = OverlayPositionPreset(rawValue: s) { overlayPositionPreset = m }
        if let v = snapshotData["showFpsCounter"] as? Bool { showFpsCounter = v }
        if let v = snapshotData["showCurrentTime"] as? Bool { showCurrentTime = v }
        if let v = snapshotData["overlayColorHex"] as? String { overlayColorHex = v }
        if let v = snapshotData["eventsMatrix"] as? [EventNotificationItem] { eventsMatrix = v }

        saveToUserDefaults()
    }

    public func restoreDefaults(for tab: SettingsTab) {
        switch tab {
        case .audioInput:
            audioInputDevice = ""
            transmitMode = .voiceActivity
            voiceHold = 0.20
            silenceBelowDb = -50.0
            speechAboveDb = -35.0
            pttHoldTime = 0.05
            pttAudioCue = false
            maxAmplification = 2.0
            echoCancellation = true
            airPodsAudioLockEnabled = true
            muteMicrophoneCue = true
            highlightMicIconWhenOpen = true
            idleActionTimeoutMinutes = 5
            idleActionType = .doNothing
            undoIdleActionOnActivity = true

        case .audioOutput:
            audioOutputDevice = ""
            defaultJitterBufferMs = 10.0
            outputVolumePercent = 100.0
            audioDuckingEnabled = false
            loopbackMode = .none

        case .userInterface:
            uiTheme = "System Default"
            displayQuitConfirmation = false
            includeUnreadCountInTaskbar = true
            userSort = .alphabetically
            hoverUserShowsVolume = true
            alwaysShowChannelUserCount = true
            filterHidesEmptyChannels = false
            showTalkingStatusInTray = true
            showUserNameWhenTalking = false
            highlightFavoriteEntriesOnTop = true

        case .shortcuts:
            enableGlobalShortcuts = true
            handleSideMouseButtons = true

        case .network:
            useTcpCompatibilityMode = false
            reconnectAutomatically = true
            autoConnectLastUsedServer = false
            suppressCertPasswordWarnings = false
            doNotEmbedExternalImages = false
            clearUserCommentsOnExit = false
            clearChatWindowOnExit = false
            hideOsInfoFromServers = false
            checkForUpdatesOnStartup = true

        case .messages:
            soundfileMode = .defaultSound
            customSoundFilePath = ""
            ttsVolumePercent = 85.0
            ttsLengthThreshold = 150
            ttsReadMessageText = true
            maxChatBlockCount = 5000

        case .overlay:
            overlayEnabled = false
            overlayPositionPreset = .topRight
            showFpsCounter = false
            showCurrentTime = false
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
            engine.configureFromSettings(state: self)
        }

        // 2. Hardware device selection
        if !audioInputDevice.isEmpty, let dev = CoreAudioDeviceManager.shared.inputDevices.first(where: { $0.name == audioInputDevice }) {
            _ = CoreAudioDeviceManager.shared.setInputDevice(dev.id)
        }
        if !audioOutputDevice.isEmpty, let dev = CoreAudioDeviceManager.shared.outputDevices.first(where: { $0.name == audioOutputDevice }) {
            _ = CoreAudioDeviceManager.shared.setOutputDevice(dev.id)
        }

        // 3. UI Theme
        switch uiTheme {
        case "Dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "Light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil
        }

        // 4. Dock Badge & Channel Tree
        store.updateDockBadge()
        store.rebuildChannelTree()

        // 5. Global Shortcuts
        GlobalPTT.shared.syncWithSettings(state: self)

        // 6. Overlay configuration & repositioning
        let overlayMgr = FloatingOverlayManager.shared
        overlayMgr.applyPosition(preset: overlayPositionPreset)
        if overlayEnabled && !overlayMgr.isVisible {
            overlayMgr.show(store: store)
        } else if !overlayEnabled && overlayMgr.isVisible {
            overlayMgr.hide()
        }

        // 7. TTS Volume sync
        TTSEngine.shared.speechVolume = Float(ttsVolumePercent / 100.0)

        // 8. Persist to UserDefaults
        saveToUserDefaults()

        // Take fresh snapshot after applying
        takeSnapshot()
    }

    public func saveToUserDefaults() {
        let d = UserDefaults.standard
        // 1. Audio Input
        d.set(audioInputDevice, forKey: "Swimble_AudioInputDevice")
        d.set(transmitMode.rawValue, forKey: "Swimble_TransmitMode")
        d.set(voiceHold, forKey: "Swimble_VoiceHold")
        d.set(silenceBelowDb, forKey: "Swimble_SilenceBelowDb")
        d.set(speechAboveDb, forKey: "Swimble_SpeechAboveDb")
        d.set(pttHoldTime, forKey: "Swimble_PttHold")
        d.set(pttAudioCue, forKey: "Swimble_PttAudioCue")
        d.set(pttOnCuePath, forKey: "Swimble_PttOnCuePath")
        d.set(pttOffCuePath, forKey: "Swimble_PttOffCuePath")
        d.set(maxAmplification, forKey: "Swimble_MaxAmplification")
        d.set(echoCancellation, forKey: "Swimble_EchoCancellation")
        d.set(airPodsAudioLockEnabled, forKey: "Swimble_AirPodsAudioLock")
        d.set(muteMicrophoneCue, forKey: "Swimble_MuteMicCue")
        d.set(muteCuePath, forKey: "Swimble_MuteCuePath")
        d.set(highlightMicIconWhenOpen, forKey: "Swimble_HighlightMic")
        d.set(idleActionTimeoutMinutes, forKey: "Swimble_IdleTimeout")
        d.set(idleActionType.rawValue, forKey: "Swimble_IdleAction")
        d.set(undoIdleActionOnActivity, forKey: "Swimble_UndoIdle")

        // 2. Audio Output
        d.set(audioOutputDevice, forKey: "Swimble_AudioOutputDevice")
        d.set(defaultJitterBufferMs, forKey: "Swimble_JitterBufferMs")
        d.set(outputVolumePercent, forKey: "Swimble_OutputVolume")
        d.set(audioDuckingEnabled, forKey: "Swimble_AudioDucking")
        d.set(loopbackMode.rawValue, forKey: "Swimble_LoopbackMode")

        // 3. User Interface
        d.set(uiTheme, forKey: "Swimble_UiTheme")
        d.set(displayQuitConfirmation, forKey: "Swimble_QuitConfirm")
        d.set(includeUnreadCountInTaskbar, forKey: "Swimble_UnreadBadge")
        d.set(userSort.rawValue, forKey: "Swimble_UserSort")
        d.set(hoverUserShowsVolume, forKey: "Swimble_HoverUserVol")
        d.set(alwaysShowChannelUserCount, forKey: "Swimble_ShowChannelCount")
        d.set(filterHidesEmptyChannels, forKey: "Swimble_FilterHideEmpty")
        d.set(showTalkingStatusInTray, forKey: "Swimble_TrayTalkingStatus")
        d.set(showUserNameWhenTalking, forKey: "Swimble_TrayUserName")
        d.set(highlightFavoriteEntriesOnTop, forKey: "Swimble_HighlightFavorites")

        // 4. Shortcuts
        d.set(enableGlobalShortcuts, forKey: "Swimble_EnableGlobalShortcuts")
        d.set(handleSideMouseButtons, forKey: "Swimble_HandleSideMouse")

        // 5. Network
        d.set(useTcpCompatibilityMode, forKey: "Swimble_TcpMode")
        d.set(reconnectAutomatically, forKey: "Swimble_ReconnectAuto")
        d.set(autoConnectLastUsedServer, forKey: "Swimble_AutoConnectLast")
        d.set(suppressCertPasswordWarnings, forKey: "Swimble_SuppressCertWarnings")
        d.set(doNotEmbedExternalImages, forKey: "Swimble_NoExternalImages")
        d.set(clearUserCommentsOnExit, forKey: "Swimble_ClearCommentsExit")
        d.set(clearChatWindowOnExit, forKey: "Swimble_ClearChatExit")
        d.set(hideOsInfoFromServers, forKey: "Swimble_HideOsInfo")
        d.set(checkForUpdatesOnStartup, forKey: "Swimble_CheckUpdates")

        // 6. Messages
        d.set(soundfileMode.rawValue, forKey: "Swimble_SoundfileMode")
        d.set(customSoundFilePath, forKey: "Swimble_CustomSoundFile")
        d.set(ttsVolumePercent, forKey: "Swimble_TtsVolume")
        d.set(ttsLengthThreshold, forKey: "Swimble_TtsThreshold")
        d.set(ttsReadMessageText, forKey: "Swimble_TtsReadMessage")
        d.set(maxChatBlockCount, forKey: "Swimble_MaxChatBlocks")
        if let data = try? JSONEncoder().encode(eventsMatrix) {
            d.set(data, forKey: "Swimble_EventsMatrix")
        }

        // 7. Overlay
        d.set(overlayEnabled, forKey: "Swimble_OverlayEnabled")
        d.set(overlayPositionPreset.rawValue, forKey: "Swimble_OverlayPreset")
        d.set(showFpsCounter, forKey: "Swimble_ShowFps")
        d.set(showCurrentTime, forKey: "Swimble_ShowCurrentTime")
        d.set(overlayColorHex, forKey: "Swimble_OverlayColor")
    }

    public func loadFromUserDefaults() {
        let d = UserDefaults.standard

        // 1. Audio Input
        if let dev = d.string(forKey: "Swimble_AudioInputDevice") { audioInputDevice = dev }
        if let s = d.string(forKey: "Swimble_TransmitMode"), let m = TransmitMode(rawValue: s) { transmitMode = m }
        if d.object(forKey: "Swimble_VoiceHold") != nil { voiceHold = d.double(forKey: "Swimble_VoiceHold") }
        if d.object(forKey: "Swimble_SilenceBelowDb") != nil { silenceBelowDb = d.double(forKey: "Swimble_SilenceBelowDb") }
        if d.object(forKey: "Swimble_SpeechAboveDb") != nil { speechAboveDb = d.double(forKey: "Swimble_SpeechAboveDb") }
        if d.object(forKey: "Swimble_PttHold") != nil { pttHoldTime = d.double(forKey: "Swimble_PttHold") }
        if d.object(forKey: "Swimble_PttAudioCue") != nil { pttAudioCue = d.bool(forKey: "Swimble_PttAudioCue") }
        if let p = d.string(forKey: "Swimble_PttOnCuePath") { pttOnCuePath = p }
        if let p = d.string(forKey: "Swimble_PttOffCuePath") { pttOffCuePath = p }
        if d.object(forKey: "Swimble_MaxAmplification") != nil { maxAmplification = d.double(forKey: "Swimble_MaxAmplification") }
        if d.object(forKey: "Swimble_EchoCancellation") != nil { echoCancellation = d.bool(forKey: "Swimble_EchoCancellation") }
        if d.object(forKey: "Swimble_AirPodsAudioLock") != nil { airPodsAudioLockEnabled = d.bool(forKey: "Swimble_AirPodsAudioLock") }
        if d.object(forKey: "Swimble_MuteMicCue") != nil { muteMicrophoneCue = d.bool(forKey: "Swimble_MuteMicCue") }
        if let p = d.string(forKey: "Swimble_MuteCuePath") { muteCuePath = p }
        if d.object(forKey: "Swimble_HighlightMic") != nil { highlightMicIconWhenOpen = d.bool(forKey: "Swimble_HighlightMic") }
        if d.object(forKey: "Swimble_IdleTimeout") != nil { idleActionTimeoutMinutes = d.integer(forKey: "Swimble_IdleTimeout") }
        if let s = d.string(forKey: "Swimble_IdleAction"), let m = IdleActionType(rawValue: s) { idleActionType = m }
        if d.object(forKey: "Swimble_UndoIdle") != nil { undoIdleActionOnActivity = d.bool(forKey: "Swimble_UndoIdle") }

        // 2. Audio Output
        if let dev = d.string(forKey: "Swimble_AudioOutputDevice") { audioOutputDevice = dev }
        if d.object(forKey: "Swimble_JitterBufferMs") != nil { defaultJitterBufferMs = d.double(forKey: "Swimble_JitterBufferMs") }
        if d.object(forKey: "Swimble_OutputVolume") != nil { outputVolumePercent = d.double(forKey: "Swimble_OutputVolume") }
        if d.object(forKey: "Swimble_AudioDucking") != nil { audioDuckingEnabled = d.bool(forKey: "Swimble_AudioDucking") }
        if let s = d.string(forKey: "Swimble_LoopbackMode"), let m = LoopbackMode(rawValue: s) { loopbackMode = m }

        // 3. User Interface
        if let t = d.string(forKey: "Swimble_UiTheme") { uiTheme = t }
        if d.object(forKey: "Swimble_QuitConfirm") != nil { displayQuitConfirmation = d.bool(forKey: "Swimble_QuitConfirm") }
        if d.object(forKey: "Swimble_UnreadBadge") != nil { includeUnreadCountInTaskbar = d.bool(forKey: "Swimble_UnreadBadge") }
        if let s = d.string(forKey: "Swimble_UserSort"), let m = UserSortMode(rawValue: s) { userSort = m }
        if d.object(forKey: "Swimble_HoverUserVol") != nil { hoverUserShowsVolume = d.bool(forKey: "Swimble_HoverUserVol") }
        if d.object(forKey: "Swimble_ShowChannelCount") != nil { alwaysShowChannelUserCount = d.bool(forKey: "Swimble_ShowChannelCount") }
        if d.object(forKey: "Swimble_FilterHideEmpty") != nil { filterHidesEmptyChannels = d.bool(forKey: "Swimble_FilterHideEmpty") }
        if d.object(forKey: "Swimble_TrayTalkingStatus") != nil { showTalkingStatusInTray = d.bool(forKey: "Swimble_TrayTalkingStatus") }
        if d.object(forKey: "Swimble_TrayUserName") != nil { showUserNameWhenTalking = d.bool(forKey: "Swimble_TrayUserName") }
        if d.object(forKey: "Swimble_HighlightFavorites") != nil { highlightFavoriteEntriesOnTop = d.bool(forKey: "Swimble_HighlightFavorites") }

        // 4. Shortcuts
        if d.object(forKey: "Swimble_EnableGlobalShortcuts") != nil { enableGlobalShortcuts = d.bool(forKey: "Swimble_EnableGlobalShortcuts") }
        if d.object(forKey: "Swimble_HandleSideMouse") != nil { handleSideMouseButtons = d.bool(forKey: "Swimble_HandleSideMouse") }

        // 5. Network
        if d.object(forKey: "Swimble_TcpMode") != nil { useTcpCompatibilityMode = d.bool(forKey: "Swimble_TcpMode") }
        if d.object(forKey: "Swimble_ReconnectAuto") != nil { reconnectAutomatically = d.bool(forKey: "Swimble_ReconnectAuto") }
        if d.object(forKey: "Swimble_AutoConnectLast") != nil { autoConnectLastUsedServer = d.bool(forKey: "Swimble_AutoConnectLast") }
        if d.object(forKey: "Swimble_SuppressCertWarnings") != nil { suppressCertPasswordWarnings = d.bool(forKey: "Swimble_SuppressCertWarnings") }
        if d.object(forKey: "Swimble_NoExternalImages") != nil { doNotEmbedExternalImages = d.bool(forKey: "Swimble_NoExternalImages") }
        if d.object(forKey: "Swimble_ClearCommentsExit") != nil { clearUserCommentsOnExit = d.bool(forKey: "Swimble_ClearCommentsExit") }
        if d.object(forKey: "Swimble_ClearChatExit") != nil { clearChatWindowOnExit = d.bool(forKey: "Swimble_ClearChatExit") }
        if d.object(forKey: "Swimble_HideOsInfo") != nil { hideOsInfoFromServers = d.bool(forKey: "Swimble_HideOsInfo") }
        if d.object(forKey: "Swimble_CheckUpdates") != nil { checkForUpdatesOnStartup = d.bool(forKey: "Swimble_CheckUpdates") }

        // 6. Messages
        if let s = d.string(forKey: "Swimble_SoundfileMode"), let m = SoundfileMode(rawValue: s) { soundfileMode = m }
        if let p = d.string(forKey: "Swimble_CustomSoundFile") { customSoundFilePath = p }
        if d.object(forKey: "Swimble_TtsVolume") != nil { ttsVolumePercent = d.double(forKey: "Swimble_TtsVolume") }
        if d.object(forKey: "Swimble_TtsThreshold") != nil { ttsLengthThreshold = d.integer(forKey: "Swimble_TtsThreshold") }
        if d.object(forKey: "Swimble_TtsReadMessage") != nil { ttsReadMessageText = d.bool(forKey: "Swimble_TtsReadMessage") }
        if d.object(forKey: "Swimble_MaxChatBlocks") != nil { maxChatBlockCount = d.integer(forKey: "Swimble_MaxChatBlocks") }
        if let data = d.data(forKey: "Swimble_EventsMatrix"),
           let items = try? JSONDecoder().decode([EventNotificationItem].self, from: data) {
            eventsMatrix = items
        }

        // 7. Overlay
        if d.object(forKey: "Swimble_OverlayEnabled") != nil { overlayEnabled = d.bool(forKey: "Swimble_OverlayEnabled") }
        if let s = d.string(forKey: "Swimble_OverlayPreset"), let m = OverlayPositionPreset(rawValue: s) { overlayPositionPreset = m }
        if d.object(forKey: "Swimble_ShowFps") != nil { showFpsCounter = d.bool(forKey: "Swimble_ShowFps") }
        if d.object(forKey: "Swimble_ShowCurrentTime") != nil { showCurrentTime = d.bool(forKey: "Swimble_ShowCurrentTime") }
        if let c = d.string(forKey: "Swimble_OverlayColor") { overlayColorHex = c }
    }
}
