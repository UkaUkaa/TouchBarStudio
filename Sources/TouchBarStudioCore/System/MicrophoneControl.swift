import CoreAudio
import Foundation

/// State of the default input device.
public struct MicrophoneState: Equatable, Sendable {
    public var deviceName: String
    public var isMuted: Bool

    public init(deviceName: String, isMuted: Bool) {
        self.deviceName = deviceName
        self.isMuted = isMuted
    }

    public var symbolName: String { isMuted ? "mic.slash.fill" : "mic.fill" }
}

/// System-wide microphone mute through the Core Audio HAL. Muting is a property of the
/// input device itself, so every app recording from it gets silence. No permission is
/// needed: nothing is recorded.
///
/// Devices that expose a settable mute (the built-in MacBook microphone does) are muted
/// directly. Otherwise the input volume is set to 0 and the previous level is remembered
/// per device (also across launches) and restored when unmuting.
public enum MicrophoneControl {
    private static let restoreKeyPrefix = "MicrophoneRestoreVolume."

    public static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// Current state, or nil when there is no input device.
    public static func currentState() -> MicrophoneState? {
        guard let device = defaultInputDevice() else { return nil }
        return MicrophoneState(deviceName: name(of: device) ?? L("Microphone"), isMuted: isMuted(device))
    }

    public static func setMuted(_ muted: Bool) throws {
        guard let device = defaultInputDevice() else { throw ActionError.noInputDevice }
        if var address = muteAddress(device) {
            var value: UInt32 = muted ? 1 : 0
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            guard status == noErr else { throw ActionError.microphoneControlFailed(Int(status)) }
            return
        }
        guard var address = volumeAddress(device) else { throw ActionError.microphoneNotControllable(name(of: device) ?? "") }
        let key = restoreKeyPrefix + (uid(of: device) ?? "\(device)")
        var volume: Float32
        if muted {
            if let current = readVolume(device), current > 0 { UserDefaults.standard.set(current, forKey: key) }
            volume = 0
        } else {
            let saved = UserDefaults.standard.object(forKey: key) as? Float
            volume = Float32(saved ?? 0.75)
            UserDefaults.standard.removeObject(forKey: key)
        }
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        guard status == noErr else { throw ActionError.microphoneControlFailed(Int(status)) }
    }

    // MARK: Listening

    /// Property addresses whose changes affect `currentState()` for `device`.
    public static func observedAddresses(for device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        [muteAddress(device), volumeAddress(device)].compactMap { $0 }
    }

    public static var defaultInputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: Helpers

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        if var address = muteAddress(device) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr { return value != 0 }
        }
        if let volume = readVolume(device) { return volume <= 0.0001 }
        return false
    }

    private static func muteAddress(_ device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        settableAddress(device, selector: kAudioDevicePropertyMute)
    }

    private static func volumeAddress(_ device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        settableAddress(device, selector: kAudioDevicePropertyVolumeScalar)
    }

    private static func settableAddress(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return nil }
        return address
    }

    private static func readVolume(_ device: AudioDeviceID) -> Float32? {
        guard var address = volumeAddress(device) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr ? volume : nil
    }

    private static func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func name(of device: AudioDeviceID) -> String? { stringProperty(device, kAudioObjectPropertyName) }
    static func uid(of device: AudioDeviceID) -> String? { stringProperty(device, kAudioDevicePropertyDeviceUID) }
}
