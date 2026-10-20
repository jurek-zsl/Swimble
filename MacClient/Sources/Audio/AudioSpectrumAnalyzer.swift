import Foundation
import Accelerate
import Observation

/// Real-time FFT / frequency spectrum analyzer for the Mumble Audio Statistics view.
/// Analyzes 48kHz audio buffers and computes 64 frequency magnitude bins.
@Observable
public final class AudioSpectrumAnalyzer: @unchecked Sendable {
    public static let shared = AudioSpectrumAnalyzer()

    /// 64 frequency magnitude bins normalized from 0.0 to 1.0 for rendering the spectrum graph
    public var magnitudes: [Float] = Array(repeating: 0.02, count: 64)

    /// Peak statistics
    public var peakMicDb: Float = -100.0
    public var peakSpeakerDb: Float = -100.0
    public var micPowerPercent: Int = 0

    @ObservationIgnored private let binCount = 64
    @ObservationIgnored private let sampleCount = 512
    @ObservationIgnored private var fftSetup: vDSP_DFT_Setup?
    @ObservationIgnored private let processingQueue = DispatchQueue(label: "com.swimble.spectrum", qos: .utility)

    @ObservationIgnored private let demandLock = NSLock()
    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var micJobPending = false
    @ObservationIgnored private var speakerJobPending = false
    @ObservationIgnored private var lastMicUpdate: TimeInterval = 0
    @ObservationIgnored private var lastSpeakerUpdate: TimeInterval = 0

    public func beginObserving() {
        demandLock.lock(); defer { demandLock.unlock() }
        observers += 1
    }

    public func endObserving() {
        demandLock.lock(); defer { demandLock.unlock() }
        observers = max(0, observers - 1)
    }

    private func reserveUpdate(microphone: Bool) -> Bool {
        demandLock.lock(); defer { demandLock.unlock() }
        guard observers > 0 else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if microphone {
            guard !micJobPending, now - lastMicUpdate >= 1.0 / 15.0 else { return false }
            micJobPending = true
            lastMicUpdate = now
        } else {
            guard !speakerJobPending, now - lastSpeakerUpdate >= 1.0 / 15.0 else { return false }
            speakerJobPending = true
            lastSpeakerUpdate = now
        }
        return true
    }

    private func finishUpdate(microphone: Bool) {
        demandLock.lock(); defer { demandLock.unlock() }
        if microphone { micJobPending = false } else { speakerJobPending = false }
    }

    public init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(sampleCount), .FORWARD)
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    /// Feeds microphone samples for FFT frequency analysis
    nonisolated public func processMic(samples: [Float], db: Float) {
        guard !samples.isEmpty, reserveUpdate(microphone: true) else { return }

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let count = min(samples.count, self.sampleCount)
            var inputReal = [Float](repeating: 0.0, count: self.sampleCount)
            var inputImag = [Float](repeating: 0.0, count: self.sampleCount)
            var outReal = [Float](repeating: 0.0, count: self.sampleCount)
            var outImag = [Float](repeating: 0.0, count: self.sampleCount)

            // Apply Hanning window
            var window = [Float](repeating: 0.0, count: count)
            vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
            vDSP_vmul(samples, 1, window, 1, &inputReal, 1, vDSP_Length(count))

            guard let setup = self.fftSetup else {
                self.finishUpdate(microphone: true)
                return
            }
            vDSP_DFT_Execute(setup, &inputReal, &inputImag, &outReal, &outImag)

            // Compute magnitudes
            var mags = [Float](repeating: 0.0, count: self.binCount)
            let step = (self.sampleCount / 2) / self.binCount

            for bin in 0..<self.binCount {
                var sum: Float = 0.0
                let start = bin * step
                let end = min(start + step, self.sampleCount / 2)
                for j in start..<end {
                    let r = outReal[j]
                    let im = outImag[j]
                    sum += sqrt(r * r + im * im)
                }
                let avg = sum / Float(max(1, end - start))
                // Logarithmic scaling for visual display
                let normalized = min(1.0, max(0.01, log10(1.0 + avg * 15.0)))
                mags[bin] = normalized
            }

            // Calculate signal metrics
            let micPower = Int(max(0, min(100, pow(10.0, db / 20.0) * 100.0)))

            DispatchQueue.main.async {
                defer { self.finishUpdate(microphone: true) }
                self.magnitudes = mags
                self.peakMicDb = db
                self.micPowerPercent = micPower
            }
        }
    }

    /// Feeds speaker audio for peak speaker level tracking
    nonisolated public func processSpeaker(samples: [Float]) {
        guard !samples.isEmpty, reserveUpdate(microphone: false) else { return }
        var sumSquares: Float = 0.0
        for s in samples { sumSquares += s * s }
        let rms = sqrt(sumSquares / Float(samples.count))
        let db = 20.0 * log10(max(rms, 1e-5))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.finishUpdate(microphone: false) }
            self.peakSpeakerDb = db
        }
    }
}
