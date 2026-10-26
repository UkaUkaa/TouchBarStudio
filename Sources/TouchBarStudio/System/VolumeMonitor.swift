import CoreAudio
import Foundation
import Observation
import TouchBarStudioCore

/// Publishes the default output device's volume and mute state. Listens to Core Audio for
/// changes (volume keys, Control Center, other apps) and for a different default output
/// device being selected, e.g. when headphones are plugged in.
@MainActor
@Observable
final class VolumeMonitor {
    private(set) var state: VolumeState? = VolumeControl.currentState()

    @ObservationIgnored var onChange: ((VolumeState?) -> Void)?
    @ObservationIgnored private var observedDevice: AudioDeviceID?
    @ObservationIgnored private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        var address = VolumeControl.defaultOutputDeviceAddress
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
        let new = VolumeControl.currentState()
        guard new != state else { return }
        state = new
        onChange?(new)
    }

    private func attachToDefaultDevice() {
        let device = VolumeControl.defaultOutputDevice()
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
        for address in VolumeControl.observedAddresses(for: device) {
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
