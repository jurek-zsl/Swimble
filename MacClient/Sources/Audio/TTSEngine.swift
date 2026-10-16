import Foundation
import AVFoundation
import Observation

/// System Text-to-Speech engine speaking incoming Mumble chat messages and server activity events.
@Observable
@MainActor
public final class TTSEngine: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public static let shared = TTSEngine()

    private let synthesizer = AVSpeechSynthesizer()

    public var isEnabled: Bool = UserDefaults.standard.bool(forKey: "Swimble_TTS_Enabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "Swimble_TTS_Enabled")
            if !isEnabled {
                stop()
            }
        }
    }

    public var readChatMessages: Bool = UserDefaults.standard.object(forKey: "Swimble_TTS_Chat") == nil ? true : UserDefaults.standard.bool(forKey: "Swimble_TTS_Chat") {
        didSet { UserDefaults.standard.set(readChatMessages, forKey: "Swimble_TTS_Chat") }
    }

    public var readChannelEvents: Bool = UserDefaults.standard.object(forKey: "Swimble_TTS_Events") == nil ? true : UserDefaults.standard.bool(forKey: "Swimble_TTS_Events") {
        didSet { UserDefaults.standard.set(readChannelEvents, forKey: "Swimble_TTS_Events") }
    }

    public var speechRate: Float = UserDefaults.standard.float(forKey: "Swimble_TTS_Rate") == 0 ? AVSpeechUtteranceDefaultSpeechRate : UserDefaults.standard.float(forKey: "Swimble_TTS_Rate") {
        didSet { UserDefaults.standard.set(speechRate, forKey: "Swimble_TTS_Rate") }
    }

    public var speechVolume: Float = UserDefaults.standard.float(forKey: "Swimble_TTS_Volume") == 0 ? 1.0 : UserDefaults.standard.float(forKey: "Swimble_TTS_Volume") {
        didSet { UserDefaults.standard.set(speechVolume, forKey: "Swimble_TTS_Volume") }
    }

    public var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "Swimble_TTS_Voice") ?? "" {
        didSet { UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "Swimble_TTS_Voice") }
    }

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speakChatMessage(sender: String, htmlBody: String) {
        guard isEnabled && readChatMessages else { return }
        let clean = cleanTextForSpeech(htmlBody)
        guard !clean.isEmpty else { return }
        speak("\(sender) says: \(clean)")
    }

    public func speakEvent(_ text: String) {
        guard isEnabled && readChannelEvents else { return }
        let clean = cleanTextForSpeech(text)
        guard !clean.isEmpty else { return }
        speak(clean)
    }

    public func speak(_ text: String) {
        let clean = cleanTextForSpeech(text)
        guard !clean.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: clean)
        utterance.rate = speechRate
        utterance.volume = speechVolume

        if !selectedVoiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func cleanTextForSpeech(_ raw: String) -> String {
        return raw
            .replacingOccurrences(of: #"(?i)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)https?:\/\/\S+"#, with: "link", options: .regularExpression)
            .replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
