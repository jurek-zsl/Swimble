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
    public var peakCleanDb: Float = -100.0
    public var micPowerPercent: Int = 0
    public var snrValue: Float = 0.0
    public var speechProbabilityPercent: Int = 0

    @ObservationIgnored private let binCount = 64
    @ObservationIgnored private let sampleCount = 512
    @ObservationIgnored private var fftSetup: vDSP_DFT_Setup?
    @ObservationIgnored private let processingQueue = DispatchQueue(label: "com.swimble.spectrum", qos: .userInteractive)

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
        guard !samples.isEmpty else { return }

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

            guard let setup = self.fftSetup else { return }
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
            let micPower = Int(max(0, min(300, (db + 90.0) * 3.5)))
            let cleanDb = max(-60.0, db - 3.5)
            let snr = max(1.0, pow(10.0, max(0.0, db + 60.0) / 10.0) * 1000.0)
            let speechProb = db > -45.0 ? min(99, Int(65 + (db + 45.0) * 2.0)) : max(2, Int((db + 90.0) * 0.8))

            DispatchQueue.main.async {
                self.magnitudes = mags
                self.peakMicDb = db
                self.peakCleanDb = cleanDb
                self.micPowerPercent = micPower
                self.snrValue = snr
                self.speechProbabilityPercent = speechProb
            }
        }
    }

    /// Feeds speaker audio for peak speaker level tracking
    nonisolated public func processSpeaker(samples: [Float]) {
        guard !samples.isEmpty else { return }
        var sumSquares: Float = 0.0
        for s in samples { sumSquares += s * s }
        let rms = sqrt(sumSquares / Float(samples.count))
        let db = 20.0 * log10(max(rms, 1e-5))

        DispatchQueue.main.async { [weak self] in
            self?.peakSpeakerDb = db
        }
    }
}
