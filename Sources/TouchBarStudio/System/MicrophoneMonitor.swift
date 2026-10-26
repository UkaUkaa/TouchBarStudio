import CoreAudio
import Foundation
import Observation
import TouchBarStudioCore

/// Publishes the default input device's mute state. Listens to Core Audio for mute/volume
/// changes (from this app, System Settings or any other app) and for a different default
/// input device being selected, e.g. when a headset is plugged in.
@MainActor
@Observable
final class MicrophoneMonitor {
    private(set) var state: MicrophoneState? = MicrophoneControl.currentState()

    @ObservationIgnored var onChange: ((MicrophoneState?) -> Void)?
    @ObservationIgnored private var observedDevice: AudioDeviceID?
    @ObservationIgnored private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        var address = MicrophoneControl.defaultInputDeviceAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.attachToDefaultDevice()
                self?.refresh()
            }
        }
        attachToDefaultDevice()
        refresh()
    }

    func refresh() {
        let new = MicrophoneControl.currentState()
        guard new != state else { return }
        state = new
        onChange?(new)
    }

    private func attachToDefaultDevice() {
        let device = MicrophoneControl.defaultInputDevice()
        guard device != observedDevice else { return }
        if let old = observedDevice {
            for (address, block) in deviceListeners {
                var address = address
                AudioObjectRemovePropertyListenerBlock(old, &address, .main, block)
            }
        }
        deviceListeners = []
        observedDevice = device
        guard let device else { return }
        for address in MicrophoneControl.observedAddresses(for: device) {
            var address = address
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }
}
