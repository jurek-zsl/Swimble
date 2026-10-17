import Foundation
import AppKit

/// Sound manager providing subtle audio cues for Mumble voice and chat events.
@MainActor
public final class SoundManager {
    public static let shared = SoundManager()

    // User settings persisted in UserDefaults
    public var isAudioCuesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "Swimble_AudioCuesEnabled") == nil {
                return true // default enabled
            }
            return UserDefaults.standard.bool(forKey: "Swimble_AudioCuesEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Swimble_AudioCuesEnabled")
        }
    }

    public var isMuteCueEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "Swimble_MuteCueEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "Swimble_MuteCueEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Swimble_MuteCueEnabled")
        }
    }

    public var isUserActivityCueEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "Swimble_UserActivityCueEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "Swimble_UserActivityCueEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Swimble_UserActivityCueEnabled")
        }
    }

    public var isWhisperCueEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "Swimble_WhisperCueEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "Swimble_WhisperCueEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Swimble_WhisperCueEnabled")
        }
    }

    public var isMessageCueEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "Swimble_MessageCueEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "Swimble_MessageCueEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Swimble_MessageCueEnabled")
        }
    }

    private init() {}

    // MARK: - Playback Methods

    public func playMute(isMuted: Bool) {
        guard isAudioCuesEnabled && isMuteCueEnabled else { return }
        if isMuted {
            NSSound(named: "Basso")?.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
    }

    public func playDeafen(isDeafened: Bool) {
        guard isAudioCuesEnabled && isMuteCueEnabled else { return }
        if isDeafened {
            NSSound(named: "Funk")?.play()
        } else {
            NSSound(named: "Hero")?.play()
        }
    }

    public func playUserJoined() {
        guard isAudioCuesEnabled && isUserActivityCueEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    public func playUserLeft() {
        guard isAudioCuesEnabled && isUserActivityCueEnabled else { return }
        NSSound(named: "Bottle")?.play()
    }

    public func playWhisper() {
        guard isAudioCuesEnabled && isWhisperCueEnabled else { return }
        NSSound(named: "Purr")?.play()
    }

    public func playMessageReceived() {
        guard isAudioCuesEnabled && isMessageCueEnabled else { return }
        NSSound(named: "Ping")?.play()
    }

    public func playPrioritySpeaker(isActive: Bool) {
        guard isAudioCuesEnabled && isMuteCueEnabled else { return }
        if isActive {
            NSSound(named: "Glass")?.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
    }

    public func playPermissionDenied() {
        guard isAudioCuesEnabled else { return }
        NSSound(named: "Sosumi")?.play()
    }

    public func playSelfMuted() {
        playMute(isMuted: true)
    }

    public func playSound(filePath: String?) {
        guard let path = filePath, !path.isEmpty else { return }
        if let sound = NSSound(contentsOfFile: path, byReference: true) {
            sound.play()
        }
    }
}
