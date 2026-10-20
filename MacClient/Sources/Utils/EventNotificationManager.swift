import Foundation
import AppKit
import UserNotifications

/// Manages event notifications across Console, macOS User Notifications, TTS, and Sound cues
/// based on the Messages Settings Events Matrix.
@MainActor
public final class EventNotificationManager {
    public static let shared = EventNotificationManager()

    private init() {
        requestNotificationPermissions()
    }

    public func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[EventNotificationManager] Notification auth error: \(error)")
            }
        }
    }

    /// Dispatches an event through the 4 channels (Console, Notification, TTS, Soundfile)
    /// configured in SettingsState.shared.eventsMatrix.
    public func dispatch(
        eventName: String,
        detail: String,
        store: MumbleStore,
        ttsOverride: String? = nil,
        soundNameOverride: String? = nil
    ) {
        let state = SettingsState.shared
        guard let item = state.eventsMatrix.first(where: { $0.eventName == eventName }) else {
            return
        }

        // 1. Console (System message in chat)
        if item.console {
            if eventName == "You muted/deafened yourself" {
                let icon = detail.contains("unmuted") ? "mic.fill" : (detail.contains("undeafened") ? "speaker.wave.2.fill" : (detail.contains("deafened") ? "speaker.slash.fill" : "mic.slash.fill"))
                store.logSystemMessage(detail, icon: icon)
            } else {
                store.logSystemMessage("\(eventName): \(detail)")
            }
        }

        // 2. Notification (macOS System Notification)
        if item.notification {
            sendSystemNotification(title: eventName, body: detail)
        }

        // 3. Text-to-Speech
        if item.tts {
            speakTts(eventName: eventName, detail: detail, override: ttsOverride, state: state)
        }

        // 4. Soundfile
        if item.soundfile {
            playSound(eventName: eventName, soundOverride: soundNameOverride, state: state, detail: detail)
        }
    }

    private func sendSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Swimble"
        content.subtitle = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // immediate delivery
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[EventNotificationManager] Failed to post notification: \(error)")
            }
        }
    }

    private func speakTts(eventName: String, detail: String, override: String?, state: SettingsState) {
        let rawText: String
        if let ov = override, !ov.isEmpty {
            rawText = state.ttsReadMessageText ? ov : "\(eventName). \(detail)"
        } else {
            rawText = "\(eventName). \(detail)"
        }

        var textToSpeak = rawText
        if state.ttsLengthThreshold > 0 && textToSpeak.count > state.ttsLengthThreshold {
            textToSpeak = String(textToSpeak.prefix(state.ttsLengthThreshold)) + "..."
        }

        TTSEngine.shared.speechVolume = Float(state.ttsVolumePercent / 100.0)
        TTSEngine.shared.speak(textToSpeak)
    }

    private func playSound(eventName: String, soundOverride: String?, state: SettingsState, detail: String) {
        if eventName == "You muted/deafened yourself" {
            guard state.muteMicrophoneCue else { return }
            if !state.muteCuePath.isEmpty { SoundManager.shared.playSound(filePath: state.muteCuePath) }
            else { SoundManager.shared.playMute(isMuted: !detail.contains("unmuted") && !detail.contains("undeafened")) }
            return
        }
        if state.soundfileMode == .customSound && !state.customSoundFilePath.isEmpty {
            SoundManager.shared.playSound(filePath: state.customSoundFilePath)
            return
        }

        if let override = soundOverride {
            NSSound(named: override)?.play()
            return
        }

        switch eventName {
        case "Connected":
            NSSound(named: "Hero")?.play()
        case "Disconnected":
            NSSound(named: "Basso")?.play()
        case "You were kicked", "User kicked (you or by you)":
            NSSound(named: "Sosumi")?.play()
        case "You were muted/deafened (by admin)":
            SoundManager.shared.playMute(isMuted: true)
        case "Text message received", "Private text message received":
            SoundManager.shared.playMessageReceived()
        case "User joined channel":
            SoundManager.shared.playUserJoined()
        case "User left channel":
            SoundManager.shared.playUserLeft()
        case "User moved (between other channels)":
            NSSound(named: "Pop")?.play()
        case "Permission denied":
            SoundManager.shared.playPermissionDenied()
        case "Recording state changed":
            NSSound(named: "Glass")?.play()
        default:
            NSSound(named: "Pop")?.play()
        }
    }
}
