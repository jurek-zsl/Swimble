import Foundation
import CoreAudio

/// Read-only Bluetooth/built-in device discovery. Routing is scoped to each
/// MacAudioEngine; this helper never changes system defaults.
@MainActor
public final class AirPodsAudioLock {
    public static let shared = AirPodsAudioLock()
    private init() {}
    public func isBluetooth(deviceID: AudioDeviceID) -> Bool {
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var propSize = UInt32(MemoryLayout<UInt32>.size)

        let tStatus = AudioObjectGetPropertyData(
            deviceID,
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

}
