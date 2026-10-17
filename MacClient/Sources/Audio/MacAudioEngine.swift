import Foundation
import AVFoundation
import AppKit
import Observation

@Observable
@MainActor
public final class MacAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let client: MumbleClient

    public var isRunning: Bool = false
    public var inputLevelDb: Float = -100.0
    public var isTransmitting: Bool = false
    public var onTransmissionChanged: (@Sendable (Bool) -> Void)?

    // Configuration
    private let transmitState: AudioTransmitState

    public var isMuted: Bool = false {
        didSet {
            transmitState.setMuted(isMuted)
        }
    }

    public var vadThresholdDb: Float = -45.0 {
        didSet {
            transmitState.setVadThresholdDb(vadThresholdDb)
        }
    }
    public var isPushToTalk: Bool {
        get { transmitState.isPushToTalkMode }
        set { transmitState.setPushToTalk(newValue) }
    }
    public var isPushToTalkActive: Bool = false {
        didSet {
            transmitState.setPushToTalkActive(isPushToTalkActive)
        }
    }
    public var activeVoiceTargetId: UInt8? = nil {
        didSet {
            transmitState.setActiveVoiceTargetId(activeVoiceTargetId)
        }
    }

    // Audio Settings Integration
    private let playbackConfig = AudioPlaybackConfig()

    public var outputVolume: Float {
        get { playbackConfig.outputVolume }
        set { playbackConfig.outputVolume = newValue }
    }

    private let captureConfig = AudioCaptureConfig()

    public var micAmplification: Float {
        get { captureConfig.amplification }
        set { captureConfig.amplification = newValue }
    }

    public var pttAudioCueEnabled: Bool = false
    public var pttOnCuePath: String = ""
    public var pttOffCuePath: String = ""

    public func configureFromSettings(state: SettingsState) {
        transmitState.configureTransmission(
            mode: state.transmitMode,
            silenceDb: Float(state.silenceBelowDb),
            speechDb: Float(state.speechAboveDb),
            voiceHold: state.voiceHold,
            pttHold: state.pttHoldTime
        )
        self.micAmplification = Float(max(0.1, state.maxAmplification))
        self.outputVolume = Float(max(0.0, state.outputVolumePercent / 100.0))
        self.pttAudioCueEnabled = state.pttAudioCue
        self.pttOnCuePath = state.pttOnCuePath
        self.pttOffCuePath = state.pttOffCuePath
        self.isVoiceProcessingEnabled = state.echoCancellation
        self.isAudioDuckingEnabled = (state.attenuateWhileOthersTalk || state.attenuateWhileYouTalk)
        self.isLoopbackTestEnabled = (state.loopbackMode == .local)
    }
    public var isAirPodsAudioLockEnabled: Bool = true {
        didSet {
            AirPodsAudioLock.shared.setEnabled(isAirPodsAudioLockEnabled)
            UserDefaults.standard.set(isAirPodsAudioLockEnabled, forKey: "Swimble_AirPodsAudioLock")
        }
    }

    /// Controls whether macOS VoiceProcessingIO ducks (quiets) background applications like Spotify, games, or YouTube.
    /// Default is false so background music and games remain at 100% volume.
    public var isAudioDuckingEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isAudioDuckingEnabled, forKey: "Swimble_AudioDucking")
            applyAudioDuckingConfig()
        }
    }

    /// Controls hardware voice processing (Acoustic Echo Cancellation, AGC, and Voice Isolation).
    public var isVoiceProcessingEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isVoiceProcessingEnabled, forKey: "Swimble_VoiceProcessing")
            applyVoiceProcessingConfig()
        }
    }

    // Loopback Audio Test
    private let loopbackBuffer = LoopbackBuffer()
    public var isLoopbackTestEnabled: Bool = false {
        didSet {
            loopbackBuffer.isEnabled = isLoopbackTestEnabled
        }
    }

    public init(client: MumbleClient) {
        self.client = client
        self.transmitState = AudioTransmitState()
        if UserDefaults.standard.object(forKey: "Swimble_AirPodsAudioLock") != nil {
            self.isAirPodsAudioLockEnabled = UserDefaults.standard.bool(forKey: "Swimble_AirPodsAudioLock")
        } else if UserDefaults.standard.object(forKey: "MumbleGlass_AirPodsAudioLock") != nil {
            self.isAirPodsAudioLockEnabled = UserDefaults.standard.bool(forKey: "MumbleGlass_AirPodsAudioLock")
        } else {
            self.isAirPodsAudioLockEnabled = true
        }

        if UserDefaults.standard.object(forKey: "Swimble_AudioDucking") != nil {
            self.isAudioDuckingEnabled = UserDefaults.standard.bool(forKey: "Swimble_AudioDucking")
        } else {
            self.isAudioDuckingEnabled = false
        }

        if UserDefaults.standard.object(forKey: "Swimble_VoiceProcessing") != nil {
            self.isVoiceProcessingEnabled = UserDefaults.standard.bool(forKey: "Swimble_VoiceProcessing")
        } else {
            self.isVoiceProcessingEnabled = true
        }

        configureFromSettings(state: SettingsState.shared)
    }

    public func applyAudioDuckingConfig() {
        updateDuckingConfig(on: engine.inputNode)
    }

    private func updateDuckingConfig(on node: AVAudioInputNode) {
        if #available(macOS 14.0, *) {
            var duckConfig = node.voiceProcessingOtherAudioDuckingConfiguration
            duckConfig.enableAdvancedDucking = false
            duckConfig.duckingLevel = isAudioDuckingEnabled ? .default : .min
            node.voiceProcessingOtherAudioDuckingConfiguration = duckConfig
        }
    }

    public func applyVoiceProcessingConfig() {
        guard isRunning else { return }
        do {
            try engine.inputNode.setVoiceProcessingEnabled(isVoiceProcessingEnabled)
            if isVoiceProcessingEnabled {
                applyAudioDuckingConfig()
            }
        } catch {
            print("[MacAudioEngine] Notice: applyVoiceProcessingConfig error: \(error)")
        }
    }

    public func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode

        // 1. Enable Hardware Voice Processing (AEC, AGC, Voice Isolation) & Configure Ducking
        if isVoiceProcessingEnabled {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                updateDuckingConfig(on: inputNode)
            } catch {
                print("[MacAudioEngine] Notice: setVoiceProcessingEnabled error: \(error)")
            }
        } else {
            do {
                try inputNode.setVoiceProcessingEnabled(false)
            } catch {
                print("[MacAudioEngine] Notice: setVoiceProcessingEnabled(false) error: \(error)")
            }
        }

        // 2. Configure AirPods Audio Lock if enabled
        AirPodsAudioLock.shared.configure(engine: engine, enabled: isAirPodsAudioLockEnabled)

        // 3. Configure output source node pulling audio from Rust ring buffer and loopback buffer.
        // Created via nonisolated helper to avoid Swift 6 actor-isolation assertion crashes on CoreAudio threads.
        let outFormat = engine.outputNode.inputFormat(forBus: 0)
        let srcNode = Self.createSourceNode(client: self.client, format: outFormat, loopback: self.loopbackBuffer, playbackConfig: self.playbackConfig)
        self.sourceNode = srcNode
        engine.attach(srcNode)
        engine.connect(srcNode, to: engine.outputNode, format: outFormat)

        // 4. Configure input node tap for microphone audio.
        // Created via nonisolated helper to prevent actor-isolation crashes on CoreAudio threads.
        Self.installTap(on: inputNode) { [weak self] buffer in
            self?.processMicBuffer(buffer)
        }

        do {
            try engine.start()
            self.isRunning = true
        } catch {
            // Clean up graph on failure so future start() attempts succeed cleanly
            inputNode.removeTap(onBus: 0)
            engine.disconnectNodeOutput(srcNode)
            engine.detach(srcNode)
            self.sourceNode = nil
            throw error
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        if let srcNode = sourceNode {
            engine.disconnectNodeOutput(srcNode)
            engine.detach(srcNode)
            self.sourceNode = nil
        }
        self.loopbackBuffer.clear()
        self.transmitState.reset()
        self.isRunning = false
        if self.isTransmitting {
            self.isTransmitting = false
            self.onTransmissionChanged?(false)
        }
        self.inputLevelDb = -100.0
    }

    public func setPushToTalkActive(_ active: Bool) {
        let changed = (self.isPushToTalkActive != active)
        self.isPushToTalkActive = active
        let now = CACurrentMediaTime()
        transmitState.setPushToTalkActive(active, now: now)

        if changed && pttAudioCueEnabled {
            if active {
                if !pttOnCuePath.isEmpty {
                    SoundManager.shared.playSound(filePath: pttOnCuePath)
                } else {
                    NSSound(named: "Pop")?.play()
                }
            } else {
                if !pttOffCuePath.isEmpty {
                    SoundManager.shared.playSound(filePath: pttOffCuePath)
                } else {
                    NSSound(named: "Tink")?.play()
                }
            }
        }
    }

    // MARK: - Nonisolated CoreAudio Helpers (Swift 6 Thread-Safety)

    nonisolated private static func createSourceNode(
        client: MumbleClient,
        format: AVAudioFormat,
        loopback: LoopbackBuffer,
        playbackConfig: AudioPlaybackConfig
    ) -> AVAudioSourceNode {
        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let samples = client.pullSpeakerPcm(frameCount: frameCount)
            let count = min(Int(frameCount), samples.count)
            let vol = playbackConfig.outputVolume

            AudioSpectrumAnalyzer.shared.processSpeaker(samples: samples)
            if AudioRecorder.shared.isRecording {
                AudioRecorder.shared.writeFrames(mic: [], speaker: samples, frameCount: Int(frameCount))
            }

            var loopbackSamples = [Float](repeating: 0.0, count: Int(frameCount))
            let loopbackCount = loopbackSamples.withUnsafeMutableBufferPointer { ptr in
                loopback.read(into: ptr.baseAddress!, count: Int(frameCount))
            }

            for buffer in ablPointer {
                guard let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frameCount) {
                    var s: Float = 0.0
                    if i < count {
                        s += samples[i] * vol
                    }
                    if i < loopbackCount {
                        s += loopbackSamples[i]
                    }
                    ptr[i] = max(-1.0, min(1.0, s))
                }
            }

            return noErr
        }
    }

    nonisolated private static func installTap(on node: AVAudioNode, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        node.installTap(onBus: 0, bufferSize: 960, format: nil) { buffer, _ in
            handler(buffer)
        }
    }

    nonisolated private func processMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let samplesPtr = channelData[0]
        var sumSquares: Float = 0.0
        let amp = self.captureConfig.amplification

        var floatSamples = [Float](repeating: 0.0, count: frameCount)
        for i in 0..<frameCount {
            let s = max(-1.0, min(1.0, samplesPtr[i] * amp))
            floatSamples[i] = s
            sumSquares += s * s
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        let db = 20.0 * log10(max(rms, 1e-5))

        // Ensure 48kHz mono samples for Rust Opus encoder
        let targetRate: Double = 48000.0
        let sourceRate = buffer.format.sampleRate
        let outputSamples: [Float]
        if abs(sourceRate - targetRate) < 1.0 {
            outputSamples = floatSamples
        } else if sourceRate > 0 {
            let ratio = sourceRate / targetRate
            let targetCount = Int(Double(frameCount) / ratio)
            var resampled = [Float](repeating: 0.0, count: targetCount)
            for i in 0..<targetCount {
                let srcIdx = Double(i) * ratio
                let base = Int(srcIdx)
                let frac = Float(srcIdx - Double(base))
                if base + 1 < frameCount {
                    resampled[i] = floatSamples[base] * (1.0 - frac) + floatSamples[base + 1] * frac
                } else if base < frameCount {
                    resampled[i] = floatSamples[base]
                }
            }
            outputSamples = resampled
        } else {
            outputSamples = floatSamples
        }

        // Write to loopback buffer if monitoring is enabled
        self.loopbackBuffer.write(samples: outputSamples)

        // Feed to Audio Statistics spectrum analyzer and WAV recorder
        AudioSpectrumAnalyzer.shared.processMic(samples: outputSamples, db: db)
        if AudioRecorder.shared.isRecording {
            AudioRecorder.shared.writeFrames(mic: outputSamples, speaker: [], frameCount: outputSamples.count)
        }

        // Process transmission synchronously on the audio thread with zero latency
        let now = CACurrentMediaTime()
        let result = self.transmitState.processAudio(db: db, now: now)

        if result.shouldTransmit {
            self.client.pushMicPcm(samples: outputSamples, target: result.target)
        } else if result.wasTransmitting {
            self.client.finishMicStream(target: result.target)
        }

        // Only dispatch to MainActor if UI metering update is needed (~15Hz or state transition)
        if result.needsUiUpdate {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.inputLevelDb = db
                let wasTransmitting = self.isTransmitting
                self.isTransmitting = result.shouldTransmit
                if wasTransmitting != result.shouldTransmit {
                    self.onTransmissionChanged?(result.shouldTransmit)
                }
            }
        }
    }
}

/// Thread-safe lock-protected audio sample ring buffer for local loopback mic testing.
final class LoopbackBuffer: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var buffer: [Float] = []
    private let maxCapacity: Int = 48000 // ~1 sec buffer at 48kHz
    private var enabled: Bool = false

    var isEnabled: Bool {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return enabled
        }
        set {
            os_unfair_lock_lock(&lock)
            enabled = newValue
            if !newValue {
                buffer.removeAll()
            }
            os_unfair_lock_unlock(&lock)
        }
    }

    func write(samples: [Float]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard enabled else { return }
        buffer.append(contentsOf: samples)
        if buffer.count > maxCapacity {
            buffer.removeFirst(buffer.count - maxCapacity)
        }
    }

    func read(into dest: UnsafeMutablePointer<Float>, count: Int) -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard enabled else { return 0 }
        let toRead = min(count, buffer.count)
        if toRead > 0 {
            for i in 0..<toRead {
                dest[i] = buffer[i]
            }
            buffer.removeFirst(toRead)
        }
        return toRead
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        buffer.removeAll()
    }
}

/// Thread-safe capture configuration for mic amplification on CoreAudio input callback.
final class AudioCaptureConfig: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var amp: Float = 1.0

    var amplification: Float {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return amp
        }
        set {
            os_unfair_lock_lock(&lock)
            amp = max(0.1, min(10.0, newValue))
            os_unfair_lock_unlock(&lock)
        }
    }
}

/// Thread-safe playback configuration for real-time output volume adjustment on CoreAudio thread.
final class AudioPlaybackConfig: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var volume: Float = 1.0

    var outputVolume: Float {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return volume
        }
        set {
            os_unfair_lock_lock(&lock)
            volume = max(0.0, min(2.5, newValue))
            os_unfair_lock_unlock(&lock)
        }
    }
}

/// Thread-safe lock-protected state manager for audio processing and transmission.
final class AudioTransmitState: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var isMuted: Bool = false
    private var transmitMode: TransmitMode = .voiceActivity
    private var isPushToTalkActive: Bool = false
    private var silenceBelowDb: Float = -50.0
    private var speechAboveDb: Float = -35.0
    private var voiceHoldSeconds: Double = 0.20
    private var pttHoldSeconds: Double = 0.00
    private var pttReleaseTime: Double = 0.0
    private var activeVoiceTargetId: UInt8? = nil
    private var vadHangoverFrames: Int = 0
    private var isTransmitting: Bool = false
    private var lastMeterUpdateTime: Double = 0

    var isPushToTalkMode: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return transmitMode == .pushToTalk
    }

    func setMuted(_ muted: Bool) {
        os_unfair_lock_lock(&lock)
        isMuted = muted
        os_unfair_lock_unlock(&lock)
    }

    func setPushToTalk(_ enabled: Bool) {
        os_unfair_lock_lock(&lock)
        transmitMode = enabled ? .pushToTalk : .voiceActivity
        os_unfair_lock_unlock(&lock)
    }

    func configureTransmission(
        mode: TransmitMode,
        silenceDb: Float,
        speechDb: Float,
        voiceHold: Double,
        pttHold: Double
    ) {
        os_unfair_lock_lock(&lock)
        transmitMode = mode
        silenceBelowDb = silenceDb
        speechAboveDb = speechDb
        voiceHoldSeconds = voiceHold
        pttHoldSeconds = pttHold
        os_unfair_lock_unlock(&lock)
    }

    func setPushToTalkActive(_ active: Bool, now: Double = CACurrentMediaTime()) {
        os_unfair_lock_lock(&lock)
        if isPushToTalkActive && !active {
            pttReleaseTime = now
        }
        isPushToTalkActive = active
        os_unfair_lock_unlock(&lock)
    }

    func setVadThresholdDb(_ db: Float) {
        os_unfair_lock_lock(&lock)
        silenceBelowDb = db
        speechAboveDb = db + 10.0
        os_unfair_lock_unlock(&lock)
    }

    func setActiveVoiceTargetId(_ id: UInt8?) {
        os_unfair_lock_lock(&lock)
        activeVoiceTargetId = id
        os_unfair_lock_unlock(&lock)
    }

    func processAudio(db: Float, now: Double) -> (shouldTransmit: Bool, wasTransmitting: Bool, target: UInt8?, needsUiUpdate: Bool) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let shouldTransmit: Bool
        if isMuted {
            shouldTransmit = false
        } else {
            switch transmitMode {
            case .continuous:
                shouldTransmit = true

            case .pushToTalk:
                if isPushToTalkActive {
                    shouldTransmit = true
                } else if pttHoldSeconds > 0 && (now - pttReleaseTime) < pttHoldSeconds {
                    shouldTransmit = true
                } else {
                    shouldTransmit = false
                }

            case .voiceActivity:
                let maxHangover = max(1, Int(voiceHoldSeconds * 50))
                if isTransmitting {
                    if db < silenceBelowDb {
                        if vadHangoverFrames > 0 {
                            vadHangoverFrames -= 1
                            shouldTransmit = true
                        } else {
                            shouldTransmit = false
                        }
                    } else {
                        vadHangoverFrames = maxHangover
                        shouldTransmit = true
                    }
                } else {
                    if db >= speechAboveDb {
                        vadHangoverFrames = maxHangover
                        shouldTransmit = true
                    } else {
                        shouldTransmit = false
                    }
                }
            }
        }

        let wasTransmitting = isTransmitting
        isTransmitting = shouldTransmit

        let stateChanged = (shouldTransmit != wasTransmitting)
        let timeElapsed = (now - lastMeterUpdateTime >= 0.06)
        let needsUiUpdate = stateChanged || timeElapsed

        if needsUiUpdate {
            lastMeterUpdateTime = now
        }

        return (shouldTransmit, wasTransmitting, activeVoiceTargetId, needsUiUpdate)
    }

    func reset() {
        os_unfair_lock_lock(&lock)
        vadHangoverFrames = 0
        isTransmitting = false
        lastMeterUpdateTime = 0
        pttReleaseTime = 0
        os_unfair_lock_unlock(&lock)
    }
}

