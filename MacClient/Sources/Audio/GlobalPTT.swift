import Foundation
import CoreGraphics
import AppKit
import Observation
import Carbon

/// Keybind configuration supporting single keys and multi-key combinations (e.g. Ctrl + Shift + Z).
public struct PTTKeybind: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifierFlags: UInt
    public var displayString: String

    public static let relevantModifierMask: UInt =
        NSEvent.ModifierFlags.control.rawValue |
        NSEvent.ModifierFlags.option.rawValue |
        NSEvent.ModifierFlags.shift.rawValue |
        NSEvent.ModifierFlags.command.rawValue

    public init(keyCode: UInt16, modifierFlags: UInt = 0, displayString: String? = nil) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags & Self.relevantModifierMask
        if let displayString = displayString, !displayString.isEmpty {
            self.displayString = displayString
        } else {
            self.displayString = Self.formatDisplayString(keyCode: keyCode, modifierFlags: modifierFlags)
        }
    }

    public static let defaultSpace = PTTKeybind(keyCode: 49, modifierFlags: 0, displayString: "Space")
    public static let defaultGrave = PTTKeybind(keyCode: 50, modifierFlags: 0, displayString: "` (Tilde)")
    public static let defaultRightOption = PTTKeybind(keyCode: 61, modifierFlags: 0, displayString: "Right Option")

    public var isModifierKey: Bool {
        Self.isModifierKeyCode(keyCode)
    }

    /// Checks if a key event matches this keybind definition.
    public func matches(keyCode: UInt16, modifierFlags: UInt) -> Bool {
        guard self.keyCode == keyCode else { return false }
        if isModifierKey {
            // Standalone modifier keys (e.g. Right Option for PTT) match on their own keycode
            return true
        }
        let expectedMods = self.modifierFlags & Self.relevantModifierMask
        let actualMods = modifierFlags & Self.relevantModifierMask
        return expectedMods == actualMods
    }

    /// Formats a shortcut combination into a clear, readable string (e.g. "Ctrl + Shift + Z").
    public static func formatDisplayString(keyCode: UInt16, modifierFlags: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var parts: [String] = []

        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option) { parts.append("Opt") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Cmd") }

        let baseName = nameForKeyCode(keyCode)
        if isModifierKeyCode(keyCode) {
            return baseName
        }

        if parts.isEmpty {
            return baseName
        } else {
            parts.append(baseName)
            return parts.joined(separator: " + ")
        }
    }

    /// Formats active modifiers alone for dynamic live preview during shortcut recording (e.g. "Ctrl + Shift").
    public static func formatModifiersOnly(_ modifierFlags: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var parts: [String] = []

        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option) { parts.append("Opt") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Cmd") }

        return parts.joined(separator: " + ")
    }

    public static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, // Right / Left Command
             56, 60, // Left / Right Shift
             58, 61, // Left / Right Option
             59, 62, // Left / Right Control
             57,     // Caps Lock
             63:     // Fn
            return true
        default:
            return false
        }
    }

    public static func isModifierDown(keyCode: UInt16, modifierFlags: UInt) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        switch keyCode {
        case 56, 60: return flags.contains(.shift)
        case 58, 61: return flags.contains(.option)
        case 59, 62: return flags.contains(.control)
        case 54, 55: return flags.contains(.command)
        case 57: return flags.contains(.capsLock)
        case 63: return flags.contains(.function)
        default: return false
        }
    }

    public static func nameForKeyCode(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Letters (ANSI)
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"

        // Number row
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"

        // Symbols & Punctuation
        case 50: return "` (Tilde)"
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 42: return "\\"
        case 41: return ";"
        case 39: return "'"
        case 43: return ","
        case 47: return "."
        case 44: return "/"

        // Whitespace & Controls
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 117: return "Forward Delete"
        case 53: return "Escape"

        // Arrow keys
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"

        // Navigation
        case 115: return "Home"
        case 119: return "End"
        case 116: return "Page Up"
        case 121: return "Page Down"

        // Modifier keys
        case 58: return "Left Option"
        case 61: return "Right Option"
        case 56: return "Left Shift"
        case 60: return "Right Shift"
        case 59: return "Left Control"
        case 62: return "Right Control"
        case 55: return "Left Command"
        case 54: return "Right Command"
        case 57: return "Caps Lock"
        case 63: return "Fn"

        // Function keys
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"

        // Keypad
        case 65: return "Keypad ."
        case 67: return "Keypad *"
        case 69: return "Keypad +"
        case 75: return "Keypad /"
        case 76: return "Keypad Enter"
        case 78: return "Keypad -"
        case 81: return "Keypad ="
        case 82: return "Keypad 0"
        case 83: return "Keypad 1"
        case 84: return "Keypad 2"
        case 85: return "Keypad 3"
        case 86: return "Keypad 4"
        case 87: return "Keypad 5"
        case 88: return "Keypad 6"
        case 89: return "Keypad 7"
        case 91: return "Keypad 8"
        case 92: return "Keypad 9"

        default:
            // Dynamic translation from active keyboard layout for international layouts
            if let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
               let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) {
                let layoutPtr = unsafeBitCast(layoutData, to: CFData.self)
                if let layout = CFDataGetBytePtr(layoutPtr) {
                    var keysDown: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var realLength: Int = 0
                    let result = layout.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutHeader in
                        UCKeyTranslate(
                            layoutHeader,
                            keyCode,
                            UInt16(kUCKeyActionDisplay),
                            0,
                            UInt32(LMGetKbdType()),
                            OptionBits(kUCKeyTranslateNoDeadKeysBit),
                            &keysDown,
                            chars.count,
                            &realLength,
                            &chars
                        )
                    }
                    if result == noErr && realLength > 0 {
                        let str = String(utf16CodeUnits: chars, count: realLength).uppercased()
                        if !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return str
                        }
                    }
                }
            }
            return "Key \(keyCode)"
        }
    }
}

/// Identifies which shortcut action is currently being recorded.
public enum KeybindAction: String, Sendable, CaseIterable {
    case ptt = "Push-to-Talk"
    case whisper = "Push-to-Whisper"
    case mute = "Toggle Mute"
    case deafen = "Toggle Deafen"
    case overlay = "Toggle Overlay"
}

/// Global background Push-to-Talk and Hotkey manager leveraging CGEvent tap with fallback monitors.
@Observable
@MainActor
public final class GlobalPTT: @unchecked Sendable {
    public static let shared = GlobalPTT()

    public var activeRecordingAction: KeybindAction? = nil
    public var recordedModifiers: UInt = 0
    private var lastModifierKeyCode: UInt16? = nil

    public var isRecordingKeybind: Bool {
        get { activeRecordingAction != nil }
        set {
            activeRecordingAction = newValue ? .ptt : nil
            if !newValue {
                recordedModifiers = 0
                lastModifierKeyCode = nil
            }
        }
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

    public var overlayToggleKeybind: PTTKeybind? {
        didSet {
            saveOverlayKeybind()
        }
    }

    public var onToggleMute: (@MainActor @Sendable () -> Void)?
    public var onToggleDeafen: (@MainActor @Sendable () -> Void)?
    public var onWhisperChanged: (@MainActor @Sendable (Bool) -> Void)?
    public var onToggleOverlay: (@MainActor @Sendable () -> Void)?

    public var isAccessibilityTrusted: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var audioEngine: MacAudioEngine?
    private var lastToggleTimes: [KeybindAction: Date] = [:]

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

        if let overlayData = UserDefaults.standard.data(forKey: "Swimble_OverlayKeybind"),
           let savedOverlay = try? JSONDecoder().decode(PTTKeybind.self, from: overlayData) {
            self.overlayToggleKeybind = savedOverlay
        } else {
            self.overlayToggleKeybind = nil
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

    /// Returns human-readable feedback while recording (e.g. "Ctrl + Shift + ..." or "Press shortcut...")
    public func recordingPreviewString(for action: KeybindAction) -> String {
        guard activeRecordingAction == action else { return "" }
        if recordedModifiers != 0 {
            let mods = PTTKeybind.formatModifiersOnly(recordedModifiers)
            return "\(mods) + ..."
        }
        return "Press shortcut..."
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

        // 1. In-app local event monitor for immediate foreground responsiveness & key recording
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            if self.isRecordingKeybind {
                self.recordEvent(event)
                return nil // Prevent key combinations from triggering menu shortcuts or typing during recording
            }
            self.handleNSEvent(event)
            return event
        }

        // 2. Global background event monitor (fallback when CGEventTap is not yet initialized)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return }
            // If the event tap is active, avoid duplicate processing from the global monitor
            if self.eventTap != nil { return }
            self.handleNSEvent(event)
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

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tapPort = ptt.eventTap {
                        CGEvent.tapEnable(tap: tapPort, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = UInt(event.flags.rawValue)
                let isModifier = (type == .flagsChanged)
                let isDown: Bool
                if isModifier {
                    isDown = PTTKeybind.isModifierDown(keyCode: keyCode, modifierFlags: flags)
                } else {
                    isDown = (type == .keyDown)
                }

                DispatchQueue.main.async {
                    ptt.handleKeyEvent(
                        keyCode: keyCode,
                        modifierFlags: flags,
                        isDown: isDown,
                        isModifierEvent: isModifier
                    )
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

    private func handleNSEvent(_ event: NSEvent) {
        let isModifier = (event.type == .flagsChanged)
        let flags = UInt(event.modifierFlags.rawValue)
        let isDown: Bool
        if isModifier {
            isDown = PTTKeybind.isModifierDown(keyCode: event.keyCode, modifierFlags: flags)
        } else {
            isDown = (event.type == .keyDown)
        }

        handleKeyEvent(
            keyCode: event.keyCode,
            modifierFlags: flags,
            isDown: isDown,
            isModifierEvent: isModifier
        )
    }

    private func shouldDebounce(action: KeybindAction) -> Bool {
        let now = Date()
        if let last = lastToggleTimes[action], now.timeIntervalSince(last) < 0.25 {
            return true
        }
        lastToggleTimes[action] = now
        return false
    }

    private func handleKeyEvent(keyCode: UInt16, modifierFlags: UInt, isDown: Bool, isModifierEvent: Bool) {
        // Do not process global shortcuts while actively recording a new keybind
        if isRecordingKeybind { return }

        // 1. Push-to-Talk Handling
        if let engine = audioEngine, engine.isPushToTalk {
            if currentKeybind.isModifierKey {
                if isModifierEvent && currentKeybind.keyCode == keyCode {
                    let active = PTTKeybind.isModifierDown(keyCode: keyCode, modifierFlags: modifierFlags)
                    engine.setPushToTalkActive(active)
                }
            } else {
                if currentKeybind.matches(keyCode: keyCode, modifierFlags: modifierFlags) {
                    engine.setPushToTalkActive(isDown)
                } else if !isDown && currentKeybind.keyCode == keyCode {
                    engine.setPushToTalkActive(false)
                } else if isModifierEvent && engine.isTransmitting {
                    // Stop transmission if required modifiers were released early
                    let expectedMods = currentKeybind.modifierFlags & PTTKeybind.relevantModifierMask
                    let actualMods = modifierFlags & PTTKeybind.relevantModifierMask
                    if (actualMods & expectedMods) != expectedMods {
                        engine.setPushToTalkActive(false)
                    }
                }
            }
        }

        // 2. Whisper Hotkey Handling
        if let whisperKey = whisperKeybind {
            if whisperKey.isModifierKey {
                if isModifierEvent && whisperKey.keyCode == keyCode {
                    let active = PTTKeybind.isModifierDown(keyCode: keyCode, modifierFlags: modifierFlags)
                    audioEngine?.setPushToTalkActive(active)
                    onWhisperChanged?(active)
                }
            } else {
                if whisperKey.matches(keyCode: keyCode, modifierFlags: modifierFlags) {
                    audioEngine?.setPushToTalkActive(isDown)
                    onWhisperChanged?(isDown)
                } else if !isDown && whisperKey.keyCode == keyCode {
                    audioEngine?.setPushToTalkActive(false)
                    onWhisperChanged?(false)
                } else if isModifierEvent {
                    let expectedMods = whisperKey.modifierFlags & PTTKeybind.relevantModifierMask
                    let actualMods = modifierFlags & PTTKeybind.relevantModifierMask
                    if (actualMods & expectedMods) != expectedMods {
                        audioEngine?.setPushToTalkActive(false)
                        onWhisperChanged?(false)
                    }
                }
            }
        }

        // 3. Global Toggles (on key down or standalone modifier press)
        if isModifierEvent {
            let active = PTTKeybind.isModifierDown(keyCode: keyCode, modifierFlags: modifierFlags)
            if active {
                if let muteKey = muteToggleKeybind, muteKey.isModifierKey && muteKey.keyCode == keyCode {
                    if !shouldDebounce(action: .mute) {
                        onToggleMute?()
                    }
                } else if let deafenKey = deafenToggleKeybind, deafenKey.isModifierKey && deafenKey.keyCode == keyCode {
                    if !shouldDebounce(action: .deafen) {
                        onToggleDeafen?()
                    }
                } else if let overlayKey = overlayToggleKeybind, overlayKey.isModifierKey && overlayKey.keyCode == keyCode {
                    if !shouldDebounce(action: .overlay) {
                        onToggleOverlay?()
                    }
                }
            }
        } else if isDown {
            if let muteKey = muteToggleKeybind, muteKey.matches(keyCode: keyCode, modifierFlags: modifierFlags) {
                if !shouldDebounce(action: .mute) {
                    onToggleMute?()
                }
            } else if let deafenKey = deafenToggleKeybind, deafenKey.matches(keyCode: keyCode, modifierFlags: modifierFlags) {
                if !shouldDebounce(action: .deafen) {
                    onToggleDeafen?()
                }
            } else if let overlayKey = overlayToggleKeybind, overlayKey.matches(keyCode: keyCode, modifierFlags: modifierFlags) {
                if !shouldDebounce(action: .overlay) {
                    onToggleOverlay?()
                }
            }
        }
    }

    private func recordEvent(_ event: NSEvent) {
        guard let action = activeRecordingAction else { return }

        let currentModifiers = UInt(event.modifierFlags.rawValue) & PTTKeybind.relevantModifierMask

        if event.type == .flagsChanged {
            self.recordedModifiers = currentModifiers

            if PTTKeybind.isModifierKeyCode(event.keyCode) {
                let isDown = PTTKeybind.isModifierDown(keyCode: event.keyCode, modifierFlags: UInt(event.modifierFlags.rawValue))
                if isDown {
                    self.lastModifierKeyCode = event.keyCode
                } else {
                    // Standalone modifier key was pressed and released without any other key
                    if let modKey = self.lastModifierKeyCode, currentModifiers == 0 {
                        let newKeybind = PTTKeybind(keyCode: modKey, modifierFlags: 0)
                        applyRecordedKeybind(newKeybind, for: action)
                        self.activeRecordingAction = nil
                        self.recordedModifiers = 0
                        self.lastModifierKeyCode = nil
                        return
                    }
                }
            }
            return
        }

        if event.type == .keyDown {
            // 1. Escape with no modifiers cancels recording
            if event.keyCode == 53 && currentModifiers == 0 {
                self.activeRecordingAction = nil
                self.recordedModifiers = 0
                self.lastModifierKeyCode = nil
                return
            }

            // 2. Delete / Backspace with no modifiers clears shortcut
            if event.keyCode == 51 && currentModifiers == 0 {
                applyRecordedKeybind(nil, for: action)
                self.activeRecordingAction = nil
                self.recordedModifiers = 0
                self.lastModifierKeyCode = nil
                return
            }

            // 3. Normal key pressed with or without modifiers -> Save combination!
            let newKeybind = PTTKeybind(keyCode: event.keyCode, modifierFlags: currentModifiers)
            applyRecordedKeybind(newKeybind, for: action)
            self.activeRecordingAction = nil
            self.recordedModifiers = 0
            self.lastModifierKeyCode = nil
        }
    }

    private func applyRecordedKeybind(_ keybind: PTTKeybind?, for action: KeybindAction) {
        switch action {
        case .ptt:
            self.currentKeybind = keybind ?? .defaultGrave
        case .whisper:
            self.whisperKeybind = keybind
        case .mute:
            self.muteToggleKeybind = keybind
        case .deafen:
            self.deafenToggleKeybind = keybind
        case .overlay:
            self.overlayToggleKeybind = keybind
        }
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

    private func saveOverlayKeybind() {
        if let overlay = overlayToggleKeybind, let data = try? JSONEncoder().encode(overlay) {
            UserDefaults.standard.set(data, forKey: "Swimble_OverlayKeybind")
        } else {
            UserDefaults.standard.removeObject(forKey: "Swimble_OverlayKeybind")
        }
    }
}
