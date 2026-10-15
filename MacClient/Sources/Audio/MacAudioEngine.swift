import Foundation
import AVFoundation
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
    public var isPushToTalk: Bool = false {
        didSet {
            transmitState.setPushToTalk(isPushToTalk)
        }
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
    public var isAirPodsAudioLockEnabled: Bool = true {
        didSet {
            AirPodsAudioLock.shared.setEnabled(isAirPodsAudioLockEnabled)
            UserDefaults.standard.set(isAirPodsAudioLockEnabled, forKey: "Swimble_AirPodsAudioLock")
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
    }

    public func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode

        // 1. Enable Hardware Voice Processing (AEC, AGC, Voice Isolation)
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            print("[MacAudioEngine] Notice: setVoiceProcessingEnabled error: \(error)")
        }

        // 2. Configure AirPods Audio Lock if enabled
        AirPodsAudioLock.shared.configure(engine: engine, enabled: isAirPodsAudioLockEnabled)

        // 3. Configure output source node pulling audio from Rust ring buffer and loopback buffer.
        // Created via nonisolated helper to avoid Swift 6 actor-isolation assertion crashes on CoreAudio threads.
        let outFormat = engine.outputNode.inputFormat(forBus: 0)
        let srcNode = Self.createSourceNode(client: self.client, format: outFormat, loopback: self.loopbackBuffer)
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
        self.isTransmitting = false
        self.inputLevelDb = -100.0
    }

    public func setPushToTalkActive(_ active: Bool) {
        self.isPushToTalkActive = active
    }

    // MARK: - Nonisolated CoreAudio Helpers (Swift 6 Thread-Safety)

    nonisolated private static func createSourceNode(
        client: MumbleClient,
        format: AVAudioFormat,
        loopback: LoopbackBuffer
    ) -> AVAudioSourceNode {
        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let samples = client.pullSpeakerPcm(frameCount: frameCount)
            let count = min(Int(frameCount), samples.count)

            var loopbackSamples = [Float](repeating: 0.0, count: Int(frameCount))
            let loopbackCount = loopbackSamples.withUnsafeMutableBufferPointer { ptr in
                loopback.read(into: ptr.baseAddress!, count: Int(frameCount))
            }

            for buffer in ablPointer {
                guard let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frameCount) {
                    var s: Float = 0.0
                    if i < count {
                        s += samples[i]
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

        var floatSamples = [Float](repeating: 0.0, count: frameCount)
        for i in 0..<frameCount {
            let s = samplesPtr[i]
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
                self.isTransmitting = result.shouldTransmit
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

/// Thread-safe lock-protected state manager for audio processing and transmission.
final class AudioTransmitState: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var isMuted: Bool = false
    private var isPushToTalk: Bool = false
    private var isPushToTalkActive: Bool = false
    private var vadThresholdDb: Float = -45.0
    private var activeVoiceTargetId: UInt8? = nil
    private var vadHangoverFrames: Int = 0
    private let hangoverMaxFrames: Int = 12
    private var isTransmitting: Bool = false
    private var lastMeterUpdateTime: Double = 0

    func setMuted(_ muted: Bool) {
        os_unfair_lock_lock(&lock)
        isMuted = muted
        os_unfair_lock_unlock(&lock)
    }

    func setPushToTalk(_ enabled: Bool) {
        os_unfair_lock_lock(&lock)
        isPushToTalk = enabled
        os_unfair_lock_unlock(&lock)
    }

    func setPushToTalkActive(_ active: Bool) {
        os_unfair_lock_lock(&lock)
        isPushToTalkActive = active
        os_unfair_lock_unlock(&lock)
    }

    func setVadThresholdDb(_ db: Float) {
        os_unfair_lock_lock(&lock)
        vadThresholdDb = db
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
        } else if isPushToTalk {
            shouldTransmit = isPushToTalkActive
        } else {
            if db >= vadThresholdDb {
                vadHangoverFrames = hangoverMaxFrames
                shouldTransmit = true
            } else if vadHangoverFrames > 0 {
                vadHangoverFrames -= 1
                shouldTransmit = true
            } else {
                shouldTransmit = false
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
        os_unfair_lock_unlock(&lock)
    }
}

