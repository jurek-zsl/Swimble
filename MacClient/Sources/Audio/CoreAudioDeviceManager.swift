import Foundation
import CoreAudio
import AudioToolbox
import Observation

/// Information about a connected CoreAudio device.
public struct AudioDeviceInfo: Identifiable, Hashable, Sendable {
    public var id: AudioDeviceID
    public var uid: String
    public var name: String
    public var isInput: Bool
    public var isOutput: Bool

    public init(id: AudioDeviceID, uid: String, name: String, isInput: Bool, isOutput: Bool) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isInput = isInput
        self.isOutput = isOutput
    }
}

/// Discovers, enumerates, and switches CoreAudio hardware input and output devices.
@Observable
@MainActor
public final class CoreAudioDeviceManager: @unchecked Sendable {
    public static let shared = CoreAudioDeviceManager()

    public var inputDevices: [AudioDeviceInfo] = []
    public var outputDevices: [AudioDeviceInfo] = []
    public var selectedInputDeviceID: AudioDeviceID = 0
    public var selectedOutputDeviceID: AudioDeviceID = 0

    private var isListening: Bool = false

    private init() {
        refreshDevices()
        startHardwareListener()
    }

    deinit {
        // Stop listener
    }

    /// Queries CoreAudio for all currently connected audio input and output devices.
    public func refreshDevices() {
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
        guard status == noErr, dataSize > 0 else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return }

        var inputs: [AudioDeviceInfo] = []
        var outputs: [AudioDeviceInfo] = []

        for id in deviceIDs {
            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>? = nil
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var devName = "Audio Device \(id)"
            if AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &cfName) == noErr,
               let unmanaged = cfName {
                devName = unmanaged.takeRetainedValue() as String
            }

            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfUid: Unmanaged<CFString>? = nil
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var devUid = "\(id)"
            if AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &cfUid) == noErr,
               let unmanaged = cfUid {
                devUid = unmanaged.takeRetainedValue() as String
            }

            // Check input streams
            var inStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inStreamSize: UInt32 = 0
            let hasInput = (AudioObjectGetPropertyDataSize(id, &inStreamAddress, 0, nil, &inStreamSize) == noErr && inStreamSize > 0)

            // Check output streams
            var outStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var outStreamSize: UInt32 = 0
            let hasOutput = (AudioObjectGetPropertyDataSize(id, &outStreamAddress, 0, nil, &outStreamSize) == noErr && outStreamSize > 0)

            let info = AudioDeviceInfo(id: id, uid: devUid, name: devName, isInput: hasInput, isOutput: hasOutput)
            if hasInput {
                inputs.append(info)
            }
            if hasOutput {
                outputs.append(info)
            }
        }

        self.inputDevices = inputs
        self.outputDevices = outputs

        // Update current defaults
        var defInAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defInID = AudioDeviceID(0)
        var defInSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defInAddress, 0, nil, &defInSize, &defInID) == noErr {
            self.selectedInputDeviceID = defInID
        }

        var defOutAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defOutID = AudioDeviceID(0)
        var defOutSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defOutAddress, 0, nil, &defOutSize, &defOutID) == noErr {
            self.selectedOutputDeviceID = defOutID
        }
    }

    /// Sets the system default input device.
    @discardableResult
    public func setInputDevice(_ deviceID: AudioDeviceID) -> Bool {
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
        if status == noErr {
            self.selectedInputDeviceID = deviceID
            return true
        }
        return false
    }

    /// Sets the system default output device.
    @discardableResult
    public func setOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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
        if status == noErr {
            self.selectedOutputDeviceID = deviceID
            return true
        }
        return false
    }

    private func startHardwareListener() {
        guard !isListening else { return }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }

        var inAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }

        var outAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }

        self.isListening = true
    }
}
