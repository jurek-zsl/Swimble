import Foundation
import CoreGraphics
import AppKit
import Observation

/// Keybind configuration for Push-to-Talk.
public struct PTTKeybind: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifierFlags: UInt
    public var displayString: String

    public init(keyCode: UInt16, modifierFlags: UInt = 0, displayString: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.displayString = displayString
    }

    public static let defaultSpace = PTTKeybind(keyCode: 49, modifierFlags: 0, displayString: "Space")
    public static let defaultGrave = PTTKeybind(keyCode: 50, modifierFlags: 0, displayString: "` (Tilde)")
    public static let defaultRightOption = PTTKeybind(keyCode: 61, modifierFlags: 0, displayString: "Right Option")

    public static func nameForKeyCode(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 50: return "` (Tilde)"
        case 53: return "Escape"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 58: return "Left Option"
        case 61: return "Right Option"
        case 56: return "Left Shift"
        case 60: return "Right Shift"
        case 59: return "Left Control"
        case 62: return "Right Control"
        case 55: return "Left Command"
        case 54: return "Right Command"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"
        default: return "Key \(keyCode)"
        }
    }
}

/// Identifies which shortcut action is currently being recorded.
public enum KeybindAction: String, Sendable {
    case ptt = "Push-to-Talk"
    case whisper = "Push-to-Whisper"
    case mute = "Toggle Mute"
    case deafen = "Toggle Deafen"
}

/// Global background Push-to-Talk manager leveraging CGEvent tap with fallback monitors.
@Observable
@MainActor
public final class GlobalPTT: @unchecked Sendable {
    public static let shared = GlobalPTT()

    public var activeRecordingAction: KeybindAction? = nil
    public var isRecordingKeybind: Bool {
        get { activeRecordingAction != nil }
        set { activeRecordingAction = newValue ? .ptt : nil }
    }

    public var currentKeybind: PTTKeybind {
        didSet {
            savePTTKeybind()
        }
    }

    public var whisperKeybind: PTTKeybind? {
        didSet {
            saveWhisperKeybind()
        }
    }

    public var muteToggleKeybind: PTTKeybind? {
        didSet {
            saveMuteKeybind()
        }
    }

    public var deafenToggleKeybind: PTTKeybind? {
        didSet {
            saveDeafenKeybind()
        }
    }

    public var onToggleMute: (@MainActor @Sendable () -> Void)?
    public var onToggleDeafen: (@MainActor @Sendable () -> Void)?
    public var onWhisperChanged: (@MainActor @Sendable (Bool) -> Void)?

    public var isAccessibilityTrusted: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var audioEngine: MacAudioEngine?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "Swimble_PTTKeybind") ?? UserDefaults.standard.data(forKey: "MumbleGlass_PTTKeybind"),
           let saved = try? JSONDecoder().decode(PTTKeybind.self, from: data) {
            self.currentKeybind = saved
        } else {
            self.currentKeybind = .defaultGrave
        }

        if let whisperData = UserDefaults.standard.data(forKey: "Swimble_WhisperKeybind"),
           let savedWhisper = try? JSONDecoder().decode(PTTKeybind.self, from: whisperData) {
            self.whisperKeybind = savedWhisper
        } else {
            self.whisperKeybind = nil
        }

        if let muteData = UserDefaults.standard.data(forKey: "Swimble_MuteKeybind"),
           let savedMute = try? JSONDecoder().decode(PTTKeybind.self, from: muteData) {
            self.muteToggleKeybind = savedMute
        } else {
            self.muteToggleKeybind = nil
        }

        if let deafenData = UserDefaults.standard.data(forKey: "Swimble_DeafenKeybind"),
           let savedDeafen = try? JSONDecoder().decode(PTTKeybind.self, from: deafenData) {
            self.deafenToggleKeybind = savedDeafen
        } else {
            self.deafenToggleKeybind = nil
        }

        self.isAccessibilityTrusted = Self.checkAccessibility(prompt: false)
    }

    public func configure(audioEngine: MacAudioEngine) {
        self.audioEngine = audioEngine
        startMonitoring()
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility Permissions

    public static func checkAccessibility(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func requestAccessibility() {
        self.isAccessibilityTrusted = Self.checkAccessibility(prompt: true)
        if isAccessibilityTrusted && eventTap == nil {
            setupEventTap()
        }
    }

    public func refreshAccessibilityStatus() {
        self.isAccessibilityTrusted = Self.checkAccessibility(prompt: false)
        if isAccessibilityTrusted && eventTap == nil {
            setupEventTap()
        }
    }

    // MARK: - Monitoring & Event Tap

    public func startMonitoring() {
        stopMonitoring()
        self.isAccessibilityTrusted = Self.checkAccessibility(prompt: false)

        // 1. In-app local event monitor for immediate foreground responsiveness
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            if self.isRecordingKeybind {
                self.recordEvent(event)
                return nil
            }
            self.handleKeyEvent(keyCode: event.keyCode, isDown: event.type == .keyDown)
            return event
        }

        // 2. Global background event monitor (works without full event interception)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self else { return }
            self.handleKeyEvent(keyCode: event.keyCode, isDown: event.type == .keyDown)
        }

        // 3. CGEvent Tap for low-latency background game PTT (requires Accessibility)
        if isAccessibilityTrusted {
            setupEventTap()
        }
    }

    public func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
                self.runLoopSource = nil
            }
            self.eventTap = nil
        }
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            self.localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            self.globalMonitor = nil
        }
    }

    private func setupEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                (1 << CGEventType.keyUp.rawValue) |
                                (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let ptt = Unmanaged<GlobalPTT>.fromOpaque(refcon).takeUnretainedValue()

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let isDown = (type == .keyDown)

                DispatchQueue.main.async {
                    ptt.handleKeyEvent(keyCode: keyCode, isDown: isDown)
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )

        guard let tap = tap else {
            print("[GlobalPTT] Notice: Unable to create CGEvent tap (Accessibility permission required)")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleKeyEvent(keyCode: UInt16, isDown: Bool) {
        // 1. Push-to-Talk Handling
        if let engine = audioEngine, engine.isPushToTalk, keyCode == currentKeybind.keyCode {
            engine.setPushToTalkActive(isDown)
        }

        // 2. Whisper Hotkey Handling
        if let whisperKey = whisperKeybind, keyCode == whisperKey.keyCode {
            if let engine = audioEngine {
                engine.setPushToTalkActive(isDown)
            }
            onWhisperChanged?(isDown)
        }

        // 3. Global Mute & Deafen Toggles (on key down)
        if isDown {
            if let muteKey = muteToggleKeybind, keyCode == muteKey.keyCode {
                onToggleMute?()
            } else if let deafenKey = deafenToggleKeybind, keyCode == deafenKey.keyCode {
                onToggleDeafen?()
            }
        }
    }

    private func recordEvent(_ event: NSEvent) {
        guard let action = activeRecordingAction else { return }
        let code = event.keyCode
        let name = PTTKeybind.nameForKeyCode(code)
        let newKeybind = PTTKeybind(keyCode: code, modifierFlags: event.modifierFlags.rawValue, displayString: name)

        switch action {
        case .ptt:
            self.currentKeybind = newKeybind
        case .whisper:
            self.whisperKeybind = newKeybind
        case .mute:
            self.muteToggleKeybind = newKeybind
        case .deafen:
            self.deafenToggleKeybind = newKeybind
        }
        self.activeRecordingAction = nil
    }

    private func savePTTKeybind() {
        if let data = try? JSONEncoder().encode(currentKeybind) {
            UserDefaults.standard.set(data, forKey: "Swimble_PTTKeybind")
        }
    }

    private func saveWhisperKeybind() {
        if let whisper = whisperKeybind, let data = try? JSONEncoder().encode(whisper) {
            UserDefaults.standard.set(data, forKey: "Swimble_WhisperKeybind")
        } else {
            UserDefaults.standard.removeObject(forKey: "Swimble_WhisperKeybind")
        }
    }

    private func saveMuteKeybind() {
        if let mute = muteToggleKeybind, let data = try? JSONEncoder().encode(mute) {
            UserDefaults.standard.set(data, forKey: "Swimble_MuteKeybind")
        } else {
            UserDefaults.standard.removeObject(forKey: "Swimble_MuteKeybind")
        }
    }

    private func saveDeafenKeybind() {
        if let deafen = deafenToggleKeybind, let data = try? JSONEncoder().encode(deafen) {
            UserDefaults.standard.set(data, forKey: "Swimble_DeafenKeybind")
        } else {
            UserDefaults.standard.removeObject(forKey: "Swimble_DeafenKeybind")
        }
    }
}
