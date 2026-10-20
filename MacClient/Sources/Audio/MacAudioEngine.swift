import Foundation
import AVFoundation
import AppKit
import Observation
import AudioToolbox
import CoreAudio
import Synchronization

@Observable
@MainActor
public final class MacAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var testPlayers: [UUID: AVAudioPlayerNode] = [:]
    private let client: MumbleClient
    private let endpoint: NativeAudioEndpoint
    private var meterTimer: Timer?
    private var previewUsers = 0
    private var shouldRun = false
    private var restarting = false
    private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var selectedInputUID = ""
    private var selectedOutputUID = ""
    private var routedInput = false
    private var routedOutput = false
    public var lastError: String?
    public var isPreviewing: Bool { previewUsers > 0 }
    public func beginPreview() { previewUsers += 1; do { try start() } catch { lastError = error.localizedDescription } }
    public func endPreview() { previewUsers = max(0, previewUsers - 1); if previewUsers == 0 && client.getMySession() == nil { stop() } }
    public func selectDevices(input: String, output: String) {
        guard selectedInputUID != input || selectedOutputUID != output else { return }
        selectedInputUID = input; selectedOutputUID = output
        if isRunning { restartForHardwareChange() }
    }
    public func restartForHardwareChange() {
        guard shouldRun, !restarting else { return }
        restarting = true; stopGraph()
        do { try start() } catch { lastError = error.localizedDescription }
        restarting = false
    }


    public var isRunning: Bool = false
    var playbackChannelCount: AVAudioChannelCount { engine.mainMixerNode.outputFormat(forBus: 0).channelCount }
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
        self.isVoiceProcessingEnabled = state.echoCancellation || state.audioDuckingEnabled
        self.isAudioDuckingEnabled = state.audioDuckingEnabled
        self.isAirPodsAudioLockEnabled = state.airPodsAudioLockEnabled
        client.setLoopbackMode(mode: state.loopbackMode == .server ? 2 : state.loopbackMode == .local ? 1 : 0)
    }
    public var isAirPodsAudioLockEnabled: Bool = true {
        didSet {
            if oldValue != isAirPodsAudioLockEnabled && isRunning { restartForHardwareChange() }
            UserDefaults.standard.set(isAirPodsAudioLockEnabled, forKey: "Swimble_AirPodsAudioLock")
        }
    }

    /// Controls whether macOS VoiceProcessingIO ducks (quiets) background applications like Spotify, games, or YouTube.
    /// Disabled selects Apple's minimum attenuation; enabled follows speech activity.
    public var isAudioDuckingEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isAudioDuckingEnabled, forKey: "Swimble_AudioDucking")
            applyAudioDuckingConfig()
        }
    }

    /// Controls hardware voice processing (Acoustic Echo Cancellation, AGC, and Voice Isolation).
    public var isVoiceProcessingEnabled: Bool = true {
        didSet {
            guard oldValue != isVoiceProcessingEnabled else { return }
            UserDefaults.standard.set(isVoiceProcessingEnabled, forKey: "Swimble_VoiceProcessing")
            applyVoiceProcessingConfig()
        }
    }

    // Loopback Audio Test
    public let spectrum = AudioSpectrumAnalyzer()
    public init(client: MumbleClient) {
        self.client = client
        self.endpoint = NativeAudioEndpoint(client: client)
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
        observeLifecycle(.AVAudioEngineConfigurationChange, center: .default, object: engine) { [weak self] in
            guard let self, self.isRunning, !self.engine.isRunning else { return }
            self.restartForHardwareChange()
        }
        observeLifecycle(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.stopGraph() }
        observeLifecycle(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.restartForHardwareChange() }
    }
    private func observeLifecycle(_ name: Notification.Name, center: NotificationCenter, object: AnyObject? = nil, action: @escaping @MainActor @Sendable () -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { _ in Task { @MainActor in action() } }
        lifecycleObservers.append((center,token))
    }
    isolated deinit {
        meterTimer?.invalidate(); engine.stop()
        for (center,token) in lifecycleObservers { center.removeObserver(token) }
    }

    public func applyAudioDuckingConfig() {
        guard isRunning, engine.inputNode.isVoiceProcessingEnabled else { return }
        updateDuckingConfig(on: engine.inputNode)
    }

    private func updateDuckingConfig(on node: AVAudioInputNode) {
        if #available(macOS 14.0, *) {
            var duckConfig = node.voiceProcessingOtherAudioDuckingConfiguration
            duckConfig.enableAdvancedDucking = true
            duckConfig.duckingLevel = isAudioDuckingEnabled ? .default : .min
            node.voiceProcessingOtherAudioDuckingConfiguration = duckConfig
        }
    }

    public func applyVoiceProcessingConfig() {
        guard isRunning else { return }
        // VoiceProcessingIO changes require rebuilding a stopped graph.
        stop()
        do {
            try start()
        } catch {
            print("[MacAudioEngine] Audio restart failed: \(error)")
        }
    }

    public func start() throws {
        guard !isRunning else { return }
        shouldRun = true

        let inputNode = engine.inputNode

        // Select the physical devices before VoiceProcessingIO constructs its
        // private aggregate. Reassigning its default device afterwards tears
        // down that aggregate while the engine is negotiating formats.
        try configureDeviceRouting()

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

        // 3. Configure output source node pulling audio from Rust ring buffer and loopback buffer.
        // Created via nonisolated helper to avoid Swift 6 actor-isolation assertion crashes on CoreAudio threads.
        let outFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let srcNode = Self.createSourceNode(endpoint: self.endpoint, format: outFormat, playbackConfig: self.playbackConfig)
        self.sourceNode = srcNode
        engine.attach(srcNode)
        engine.connect(srcNode, to: engine.mainMixerNode, format: outFormat)
        // VoiceProcessingIO shares a sample clock for capture and playback.
        // Negotiate its playback format explicitly instead of retaining the
        // speaker's default rate when the microphone uses a different rate.
        let captureFormat = inputNode.outputFormat(forBus: 0)
        if inputNode.isVoiceProcessingEnabled {
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: captureFormat)
        }

        // 4. Configure input node tap for microphone audio.
        // Created via nonisolated helper to prevent actor-isolation crashes on CoreAudio threads.
        Self.installTap(on: inputNode) { [weak self] buffer in
            self?.processMicBuffer(buffer)
        }

        do {
            try engine.start()
            self.isRunning = true
            self.lastError = nil
            swimble_audio_active(endpoint.handle, true)
            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let metrics = self.client.audioMetrics()
                    self.inputLevelDb = metrics.micDb
                    let transmitting = metrics.transmitting
                    if self.isTransmitting != transmitting { self.isTransmitting = transmitting; self.onTransmissionChanged?(transmitting) }
                    self.spectrum.processMic(samples: metrics.micSamples, db: metrics.micDb)
                    self.spectrum.processSpeaker(samples: metrics.speakerSamples)
                }
            }
        } catch {
            print("[MacAudioEngine] Start failed: \(error); capture=\(captureFormat), playback=\(engine.outputNode.inputFormat(forBus: 0))")
            // Clean up graph on failure so future start() attempts succeed cleanly
            inputNode.removeTap(onBus: 0)
            engine.disconnectNodeOutput(srcNode)
            engine.detach(srcNode)
            self.sourceNode = nil
            throw error
        }
    }

    public func stop() { shouldRun = false; stopGraph() }
    private func stopGraph() {
        meterTimer?.invalidate(); meterTimer = nil
        guard isRunning else { swimble_audio_active(endpoint.handle, false); return }
        engine.stop()
        swimble_audio_active(endpoint.handle, false)
        for player in testPlayers.values { player.stop(); engine.detach(player) }
        testPlayers.removeAll()

        engine.inputNode.removeTap(onBus: 0)
        if let srcNode = sourceNode {
            engine.disconnectNodeOutput(srcNode)
            engine.detach(srcNode)
            self.sourceNode = nil
        }
        self.transmitState.reset()
        self.isRunning = false
        if self.isTransmitting {
            self.isTransmitting = false
            self.onTransmissionChanged?(false)
        }
        self.inputLevelDb = -100.0
    }

    public func setTemporaryMute(_ muted: Bool) { transmitState.setTemporaryMute(muted) }

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

    public func playTestTone() {
        do {
            try start()
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            let player = AVAudioPlayerNode()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 28800), let data = buffer.floatChannelData else { return }
            let id = UUID()
            testPlayers[id] = player
            engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format)
            buffer.frameLength = 28800
            for i in 0..<28800 {
                let envelope = min(1.0, Double(i)/240.0) * min(1.0, Double(28800-i)/2400.0)
                let value = Float(sin(2.0 * .pi * 440.0 * Double(i)/48000.0) * 0.12 * envelope)
                data[0][i] = value; data[1][i] = value
            }
            player.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let completed = self.testPlayers.removeValue(forKey: id) else { return }
                    completed.stop(); self.engine.detach(completed)
                }
            }
            player.play()
        } catch { lastError = error.localizedDescription }
    }

    private func configureDeviceRouting() throws {
        let manager = CoreAudioDeviceManager.shared
        manager.refreshDevices()
        let input = manager.inputDevices.first { $0.uid == selectedInputUID || $0.name == selectedInputUID }
        let output = manager.outputDevices.first { $0.uid == selectedOutputUID || $0.name == selectedOutputUID }
        var inputID = input?.id ?? manager.selectedInputDeviceID
        let outputID = output?.id ?? manager.selectedOutputDeviceID
        let protectBluetooth = selectedInputUID.isEmpty && isAirPodsAudioLockEnabled && AirPodsAudioLock.shared.isBluetooth(deviceID: outputID)
        if protectBluetooth, let builtIn = AirPodsAudioLock.shared.findBuiltInMicrophone() { inputID = builtIn }
        // Leave untouched defaults to AVAudioEngine. Explicit selection uses
        // AUAudioUnit's device API rather than a property on its v2 wrapper.
        if input != nil || protectBluetooth || routedInput {
            let unit = engine.inputNode.auAudioUnit
            if inputID != 0 && unit.deviceID != inputID { try unit.setDeviceID(inputID) }
            routedInput = input != nil || protectBluetooth
        }
        if output != nil || routedOutput {
            let unit = engine.outputNode.auAudioUnit
            if outputID != 0 && unit.deviceID != outputID { try unit.setDeviceID(outputID) }
            routedOutput = output != nil
        }
    }

    // MARK: - Nonisolated CoreAudio Helpers (Swift 6 Thread-Safety)

    nonisolated private static func createSourceNode(endpoint: NativeAudioEndpoint, format: AVAudioFormat, playbackConfig: AudioPlaybackConfig) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, list -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            swimble_audio_playback(endpoint.handle, left, right, frameCount, playbackConfig.outputVolume)
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

        for i in 0..<frameCount { let sample = samplesPtr[i] * amp; sumSquares += sample * sample }
        let rms = sqrt(sumSquares / Float(frameCount))
        let db = 20.0 * log10(max(rms, 1e-5))
        let now = CACurrentMediaTime()
        let result = self.transmitState.processAudio(db: db, now: now)
        swimble_audio_capture(endpoint.handle, samplesPtr, UInt32(frameCount), UInt32(buffer.format.sampleRate), amp,
                              result.shouldTransmit ? Int32(result.target ?? 0) : -1)


    }
}

/// Thread-safe capture configuration for mic amplification on CoreAudio input callback.
final class AudioCaptureConfig: Sendable {
    private let bits = Atomic<UInt32>(Float(1.0).bitPattern)
    var amplification: Float {
        get { Float(bitPattern: bits.load(ordering: .relaxed)) }
        set { bits.store(max(0.1, min(10.0, newValue)).bitPattern, ordering: .relaxed) }
    }
}
final class AudioPlaybackConfig: Sendable {
    private let bits = Atomic<UInt32>(Float(1.0).bitPattern)
    var outputVolume: Float {
        get { Float(bitPattern: bits.load(ordering: .relaxed)) }
        set { bits.store(max(0.0, min(2.5, newValue)).bitPattern, ordering: .relaxed) }
    }
}

/// Thread-safe lock-protected state manager for audio processing and transmission.
final class AudioTransmitState: @unchecked Sendable {
    // UI writes atomic controls; only the serialized capture callback changes
    // hysteresis/meter state. reset() is called after engine.stop().
    private let muted = Atomic<Bool>(false)
    private let temporaryMute = Atomic<Bool>(false)
    private let mode = Atomic<Int>(0)
    private let ptt = Atomic<Bool>(false)
    private let silence = Atomic<UInt32>(Float(-50).bitPattern)
    private let speech = Atomic<UInt32>(Float(-35).bitPattern)
    private let voiceHold = Atomic<UInt64>(Double(0.2).bitPattern)
    private let pttHold = Atomic<UInt64>(Double(0).bitPattern)
    private let releaseTime = Atomic<UInt64>(Double(-1000).bitPattern)
    private let target = Atomic<Int32>(-1)
    private var transmitting = false
    private var lastVoiceTime = -1000.0
    private var lastMeterUpdateTime = 0.0
    var isPushToTalkMode: Bool { mode.load(ordering: .relaxed) == 1 }
    func setMuted(_ value: Bool) { muted.store(value, ordering: .relaxed) }
    func setTemporaryMute(_ value: Bool) { temporaryMute.store(value, ordering: .relaxed) }
    func setPushToTalk(_ enabled: Bool) { mode.store(enabled ? 1 : 0, ordering: .relaxed) }
    func configureTransmission(mode: TransmitMode, silenceDb: Float, speechDb: Float, voiceHold: Double, pttHold: Double) {
        self.mode.store(mode == .pushToTalk ? 1 : mode == .continuous ? 2 : 0, ordering: .relaxed)
        silence.store(silenceDb.bitPattern, ordering: .relaxed); speech.store(speechDb.bitPattern, ordering: .relaxed)
        self.voiceHold.store(voiceHold.bitPattern, ordering: .relaxed); self.pttHold.store(pttHold.bitPattern, ordering: .relaxed)
    }
    func setPushToTalkActive(_ active: Bool, now: Double = CACurrentMediaTime()) {
        if ptt.exchange(active, ordering: .relaxed) && !active { releaseTime.store(now.bitPattern, ordering: .relaxed) }
    }
    func setVadThresholdDb(_ db: Float) { silence.store(db.bitPattern, ordering: .relaxed); speech.store((db+10).bitPattern, ordering: .relaxed) }
    func setActiveVoiceTargetId(_ id: UInt8?) { target.store(id.map(Int32.init) ?? -1, ordering: .relaxed) }
    func processAudio(db: Float, now: Double) -> (shouldTransmit: Bool, wasTransmitting: Bool, target: UInt8?, needsUiUpdate: Bool) {
        let before = transmitting
        if muted.load(ordering: .relaxed) || temporaryMute.load(ordering: .relaxed) { transmitting = false }
        else if ptt.load(ordering: .relaxed) { transmitting = true }
        else {
            switch mode.load(ordering: .relaxed) {
            case 1: transmitting = ptt.load(ordering: .relaxed) || now - Double(bitPattern: releaseTime.load(ordering: .relaxed)) < Double(bitPattern: pttHold.load(ordering: .relaxed))
            case 2: transmitting = true
            default:
                let threshold = Float(bitPattern: (transmitting ? silence.load(ordering: .relaxed) : speech.load(ordering: .relaxed)))
                if db >= threshold { lastVoiceTime = now; transmitting = true }
                else { transmitting = before && now-lastVoiceTime < Double(bitPattern: voiceHold.load(ordering: .relaxed)) }
            }
        }
        let update = before != transmitting || now-lastMeterUpdateTime >= 1.0/15.0
        if update { lastMeterUpdateTime = now }
        let id = target.load(ordering: .relaxed)
        return (transmitting,before,id >= 0 ? UInt8(clamping: id) : nil,update)
    }
    func reset() { transmitting = false; lastVoiceTime = -1000; lastMeterUpdateTime = 0; releaseTime.store(Double(-1000).bitPattern, ordering: .relaxed) }
}

/// Arc ownership belongs to this endpoint; source/tap closures retain it until
/// CoreAudio releases the callbacks. Rust guards SPSC endpoints with nonblocking
/// atomic flags. No Swift actor state crosses this boundary.
final class NativeAudioEndpoint: @unchecked Sendable {
    let handle: UInt64
    init(client: MumbleClient) { handle = client.audioPortHandle() }
    deinit { swimble_audio_release(handle) }
}
