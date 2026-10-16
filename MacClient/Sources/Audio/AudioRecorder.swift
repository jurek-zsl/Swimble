import Foundation
import AVFoundation
import Observation

/// Thread-safe Audio Recorder writing mixed Mumble voice chat (microphone + incoming speakers)
/// to 48,000 Hz stereo WAV files in ~/Music/Swimble/.
@Observable
public final class AudioRecorder: @unchecked Sendable {
    public static let shared = AudioRecorder()

    public var isRecording: Bool = false
    public var durationSeconds: TimeInterval = 0
    public var currentRecordingUrl: URL? = nil

    @ObservationIgnored private var audioFile: AVAudioFile?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startTime: Date?
    @ObservationIgnored private let recordingQueue = DispatchQueue(label: "com.swimble.audiorecorder", qos: .utility)

    // Formatter for timestamped filenames
    @ObservationIgnored private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return df
    }()

    public init() {}

    /// Starts recording to ~/Music/Swimble/Recording_<timestamp>.wav
    public func startRecording() -> Bool {
        guard !isRecording else { return true }

        let fileManager = FileManager.default
        let musicDir = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let swimbleDir = musicDir.appendingPathComponent("Swimble", isDirectory: true)

        do {
            if !fileManager.fileExists(atPath: swimbleDir.path) {
                try fileManager.createDirectory(at: swimbleDir, withIntermediateDirectories: true)
            }

            let fileName = "Swimble_Recording_\(dateFormatter.string(from: Date())).wav"
            let fileUrl = swimbleDir.appendingPathComponent(fileName)

            // 48,000 Hz, Stereo, 16-bit PCM Linear WAV for universal playback
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000.0,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            let file = try AVAudioFile(forWriting: fileUrl, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)

            self.audioFile = file
            self.currentRecordingUrl = fileUrl
            self.isRecording = true
            self.durationSeconds = 0
            self.startTime = Date()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self = self, let start = self.startTime else { return }
                    self.durationSeconds = Date().timeIntervalSince(start)
                }
            }

            return true
        } catch {
            print("[AudioRecorder] Failed to start recording: \(error)")
            return false
        }
    }

    /// Stops recording and returns the final saved file URL
    @discardableResult
    public func stopRecording() -> URL? {
        guard isRecording else { return nil }

        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
        self.isRecording = false
        let savedUrl = currentRecordingUrl

        recordingQueue.sync {
            self.audioFile = nil
        }

        return savedUrl
    }

    /// Nonisolated frame writer mixing incoming speaker audio with microphone audio into stereo channels
    /// Channel 0 = Microphone, Channel 1 = Remote Speakers (or stereo mix)
    nonisolated public func writeFrames(mic: [Float], speaker: [Float], frameCount: Int) {
        recordingQueue.async { [weak self] in
            guard let self = self, let file = self.audioFile else { return }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
                return
            }
            buffer.frameLength = AVAudioFrameCount(frameCount)

            guard let channelData = buffer.floatChannelData else { return }
            let leftChannel = channelData[0]  // Mic audio
            let rightChannel = channelData[1] // Speaker audio

            let micCount = mic.count
            let spkCount = speaker.count

            for i in 0..<frameCount {
                leftChannel[i] = i < micCount ? mic[i] : 0.0
                rightChannel[i] = i < spkCount ? speaker[i] : 0.0
            }

            do {
                try file.write(from: buffer)
            } catch {
                print("[AudioRecorder] Error writing audio buffer: \(error)")
            }
        }
    }
}
