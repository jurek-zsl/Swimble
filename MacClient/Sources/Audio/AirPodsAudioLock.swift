import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

/// Manages locking the Mac's default input device to the built-in microphone
/// when Bluetooth output devices (such as AirPods) are detected, preventing macOS
/// from downgrading stereo game audio to the 16kHz Bluetooth Hands-Free Profile.
public final class AirPodsAudioLock: @unchecked Sendable {
    public static let shared = AirPodsAudioLock()

    private var isListenerActive: Bool = false
    private weak var currentEngine: AVAudioEngine?
    private var isLockEnabled: Bool = false
    private var previousInputDeviceID: AudioDeviceID?
    private var isCurrentlyLocked: Bool = false

    private init() {}

    public func configure(engine: AVAudioEngine, enabled: Bool) {
        self.currentEngine = engine
        self.isLockEnabled = enabled

        if enabled {
            applyLockIfNeeded()
            startDeviceListener()
        } else {
            stopDeviceListener()
            unlock()
        }
    }

    public func setEnabled(_ enabled: Bool) {
        self.isLockEnabled = enabled
        if let engine = currentEngine {
            configure(engine: engine, enabled: enabled)
        } else if !enabled {
            unlock()
        }
    }

    /// Checks if the current default output is a Bluetooth device and locks input to built-in mic.
    public func applyLockIfNeeded() {
        guard isLockEnabled, currentEngine != nil else { return }

        let isBluetoothOutput = isDefaultOutputBluetooth()
        if isBluetoothOutput {
            if !isCurrentlyLocked {
                if let builtInMicID = findBuiltInMicrophone() {
                    let currentInput = currentDefaultInputDevice()
                    if currentInput != builtInMicID {
                        previousInputDeviceID = currentInput
                        if setDefaultInputDevice(builtInMicID) {
                            isCurrentlyLocked = true
                            print("[AirPodsAudioLock] Successfully locked default input to built-in mic (ID: \(builtInMicID))")
                        }
                    } else {
                        isCurrentlyLocked = true
                    }
                }
            }
        } else {
            unlock()
        }
    }

    public func unlock() {
        if isCurrentlyLocked, let prev = previousInputDeviceID {
            _ = setDefaultInputDevice(prev)
            previousInputDeviceID = nil
            isCurrentlyLocked = false
            print("[AirPodsAudioLock] Restored default input to device ID: \(prev)")
        } else {
            isCurrentlyLocked = false
        }
    }

    // MARK: - CoreAudio Device Discovery & Management

    public func currentDefaultInputDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultInputDeviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultInputDeviceID
        )
        guard status == noErr, defaultInputDeviceID != 0 else { return nil }
        return defaultInputDeviceID
    }

    @discardableResult
    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dev = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &dev
        )
        return status == noErr
    }

    /// Returns true if the default output device is connected via Bluetooth.
    public func isDefaultOutputBluetooth() -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultOutputDeviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultOutputDeviceID
        )
        guard status == noErr, defaultOutputDeviceID != 0 else { return false }

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var propSize = UInt32(MemoryLayout<UInt32>.size)

        let tStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &transportAddress,
            0,
            nil,
            &propSize,
            &transportType
        )
        guard tStatus == noErr else { return false }

        return transportType == kAudioDeviceTransportTypeBluetooth ||
               transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Finds the Mac's built-in microphone AudioDeviceID.
    public func findBuiltInMicrophone() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &devices
        )
        guard getStatus == noErr else { return nil }

        for device in devices {
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transportType: UInt32 = 0
            var propSize = UInt32(MemoryLayout<UInt32>.size)
            let tStatus = AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &propSize, &transportType)
            if tStatus == noErr && transportType == kAudioDeviceTransportTypeBuiltIn {
                // Verify device has input channels
                var streamAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreams,
                    mScope: kAudioDevicePropertyScopeInput,
                    mElement: kAudioObjectPropertyElementMain
                )
                var streamSize: UInt32 = 0
                if AudioObjectGetPropertyDataSize(device, &streamAddress, 0, nil, &streamSize) == noErr && streamSize > 0 {
                    return device
                }
            }
        }
        return nil
    }

    // MARK: - Hardware Listener

    private func startDeviceListener() {
        guard !isListenerActive else { return }
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.applyLockIfNeeded()
        }
        if status == noErr {
            isListenerActive = true
        }
    }

    private func stopDeviceListener() {
        guard isListenerActive else { return }
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.applyLockIfNeeded()
        }
        isListenerActive = false
    }
}
