import AudioToolbox
import CoreAudio
import Foundation

/// State of the default output device.
public struct VolumeState: Equatable, Sendable {
    public var deviceName: String
    /// 0…1.
    public var volume: Float
    public var isMuted: Bool
    /// False for devices whose volume is fixed (e.g. HDMI or some USB devices).
    public var canSetVolume: Bool

    public init(deviceName: String, volume: Float, isMuted: Bool, canSetVolume: Bool = true) {
        self.deviceName = deviceName
        self.volume = volume
        self.isMuted = isMuted
        self.canSetVolume = canSetVolume
    }

    public var symbolName: String {
        if isMuted || volume <= 0.0001 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    public var percentageText: String { "\(Int((volume * 100).rounded()))%" }
}

/// Output volume of the default sound device through the Core Audio HAL (public API,
/// no permission needed). Uses the device's virtual main volume, which is what the
/// volume keys and Control Center change.
public enum VolumeControl {
    public static func defaultOutputDevice() -> AudioDeviceID? {
        var address = defaultOutputDeviceAddress
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// Current state, or nil when there is no output device.
    public static func currentState() -> VolumeState? {
        guard let device = defaultOutputDevice() else { return nil }
        var volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let hasVolume = AudioObjectHasProperty(device, &volumeAddress)
            && AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr
        return VolumeState(deviceName: MicrophoneControl.name(of: device) ?? L("Speakers"),
                           volume: hasVolume ? min(1, max(0, volume)) : 1,
                           isMuted: readMute(device) ?? false,
                           canSetVolume: hasVolume && isSettable(device, &volumeAddress))
    }

    /// Sets the volume (0…1). Raising it above zero also unmutes, like the volume keys.
    public static func setVolume(_ value: Float) throws {
        guard let device = defaultOutputDevice() else { throw ActionError.noOutputDevice }
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var volume = Float32(min(1, max(0, value)))
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        guard status == noErr else { throw ActionError.volumeControlFailed(Int(status)) }
        if volume > 0, readMute(device) == true { try setMuted(false, device: device) }
    }

    public static func setMuted(_ muted: Bool) throws {
        guard let device = defaultOutputDevice() else { throw ActionError.noOutputDevice }
        try setMuted(muted, device: device)
    }

    private static func setMuted(_ muted: Bool, device: AudioDeviceID) throws {
        var address = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { throw ActionError.volumeControlFailed(Int(kAudioHardwareUnknownPropertyError)) }
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else { throw ActionError.volumeControlFailed(Int(status)) }
    }

    // MARK: Listening

    /// Property addresses whose changes affect `currentState()` for `device`.
    public static func observedAddresses(for device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        [address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume), address(kAudioDevicePropertyMute)].filter { address in
            var address = address
            return AudioObjectHasProperty(device, &address)
        }
    }

    public static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: Helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func readMute(_ device: AudioDeviceID) -> Bool? {
        var address = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }

    private static func isSettable(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}
