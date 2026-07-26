import CoreAudio
import Foundation

/// Reports whether the default input device is currently in use, so we can stay
/// quiet while the user is on a call.
///
/// Adapted from Notchy (MIT, Copyright (c) 2026 Adam Lyttle) —
/// https://github.com/bones7456/notchy
enum MicrophoneActivityMonitor {
    static var isInputDeviceActive: Bool {
        guard let deviceID = defaultInputDeviceID() else { return false }
        return isRunningSomewhere(deviceID)
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` is true whenever any
    /// process holds the device open — which is what "on a call" looks like.
    private static func isRunningSomewhere(_ deviceID: AudioDeviceID) -> Bool {
        var isRunning = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
        guard status == noErr else { return false }
        return isRunning != 0
    }
}
