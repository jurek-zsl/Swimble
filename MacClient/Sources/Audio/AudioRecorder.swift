import Foundation
import Observation

/// UI lifetime for the Rust writer. A single playback sample clock aligns the
/// microphone and remote mix; recording never writes from a CoreAudio callback.
@Observable @MainActor
public final class AudioRecorder {
    public private(set) var isRecording = false
    public private(set) var durationSeconds: TimeInterval = 0
    public private(set) var currentRecordingUrl: URL?
    public private(set) var lastError: String?
    @ObservationIgnored private var client: MumbleClient?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startTime: Date?
    public init() {}
    public func startRecording(client: MumbleClient, directory: URL? = nil) -> Bool {
        guard !isRecording else { return true }
        let root = directory ?? FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("Swimble")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = root.appendingPathComponent("Swimble_\(stamp)_\(UUID().uuidString.prefix(6)).wav")
            guard client.startRecording(path: url.path) else { throw CocoaError(.fileWriteUnknown) }
            self.client = client; currentRecordingUrl = url; startTime = Date(); durationSeconds = 0; isRecording = true; lastError = nil
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in guard let self, let startTime = self.startTime else { return }; self.durationSeconds = Date().timeIntervalSince(startTime) }
            }
            return true
        } catch { lastError = error.localizedDescription; return false }
    }
    @discardableResult public func stopRecording() -> URL? {
        guard isRecording else { return nil }
        timer?.invalidate(); timer = nil; client?.stopRecording(); client = nil; isRecording = false
        return currentRecordingUrl
    }
}
