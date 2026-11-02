import AudioToolbox
import CoreAudio
import Foundation

enum VolumeError: LocalizedError {
    case noDefaultDevice(OSStatus)
    case volumeUnsupported(device: String)
    case muteUnsupported(device: String)
    case coreAudio(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .noDefaultDevice(let s): "No default output device (OSStatus \(s))"
        case .volumeUnsupported(let d): "\(d) has no software volume control"
        case .muteUnsupported(let d): "\(d) has no mute control"
        case .coreAudio(let op, let s): "\(op) failed (OSStatus \(s))"
        }
    }
}

/// Reads and changes volume and mute on the current default output device.
///
/// It prefers `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, which
/// moves all channels while keeping balance. When a device lacks it, it falls
/// back to `kAudioDevicePropertyVolumeScalar` on the main element, then on
/// channels 1 and 2.
struct VolumeControl {
    private func address(_ selector: AudioObjectPropertySelector, element: UInt32 = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress
    {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    func defaultOutputDevice() throws -> AudioDeviceID {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { throw VolumeError.noDefaultDevice(status) }
        return device
    }

    func deviceName(_ device: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name)
        guard status == noErr, let name else { return "Output device \(device)" }
        return name.takeRetainedValue() as String
    }

    /// The volume addresses this device supports, best first.
    private func volumeAddresses(_ device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        var virtualMain = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if AudioObjectHasProperty(device, &virtualMain) { return [virtualMain] }
        var main = address(kAudioDevicePropertyVolumeScalar)
        if AudioObjectHasProperty(device, &main) { return [main] }
        return [UInt32(1), UInt32(2)].compactMap { channel in
            var a = address(kAudioDevicePropertyVolumeScalar, element: channel)
            return AudioObjectHasProperty(device, &a) ? a : nil
        }
    }

    func volume() throws -> Float {
        let device = try defaultOutputDevice()
        let addresses = volumeAddresses(device)
        guard !addresses.isEmpty else { throw VolumeError.volumeUnsupported(device: deviceName(device)) }
        var values: [Float] = []
        for var a in addresses {
            var v = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v)
            guard status == noErr else { throw VolumeError.coreAudio(operation: "Read volume", status: status) }
            values.append(v)
        }
        return values.reduce(0, +) / Float(values.count)
    }

    func setVolume(_ value: Float) throws {
        let device = try defaultOutputDevice()
        let addresses = volumeAddresses(device)
        guard !addresses.isEmpty else { throw VolumeError.volumeUnsupported(device: deviceName(device)) }
        var v = Float32(min(max(value, 0), 1))
        for var a in addresses {
            var settable: DarwinBoolean = false
            let check = AudioObjectIsPropertySettable(device, &a, &settable)
            guard check == noErr, settable.boolValue else {
                throw VolumeError.volumeUnsupported(device: deviceName(device))
            }
            let status = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            guard status == noErr else { throw VolumeError.coreAudio(operation: "Set volume", status: status) }
        }
    }

    func isMuted() throws -> Bool {
        let device = try defaultOutputDevice()
        var a = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &a) else { throw VolumeError.muteUnsupported(device: deviceName(device)) }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &a, 0, nil, &size, &muted)
        guard status == noErr else { throw VolumeError.coreAudio(operation: "Read mute", status: status) }
        return muted != 0
    }

    func setMuted(_ muted: Bool) throws {
        let device = try defaultOutputDevice()
        var a = address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &a),
              AudioObjectIsPropertySettable(device, &a, &settable) == noErr, settable.boolValue
        else { throw VolumeError.muteUnsupported(device: deviceName(device)) }
        var value = UInt32(muted ? 1 : 0)
        let status = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else { throw VolumeError.coreAudio(operation: "Set mute", status: status) }
    }

    /// Adds `delta` to the volume and returns the new value. Raising the
    /// volume also unmutes, as the hardware volume keys do.
    @discardableResult
    func adjust(by delta: Double) throws -> Float {
        let new = min(max(try volume() + Float(delta), 0), 1)
        try setVolume(new)
        // A device without a mute control has nothing to unmute, so only a
        // device that reports mute is unmuted. Write errors still throw.
        if delta > 0, case .success(true) = Result(catching: { try isMuted() }) {
            try setMuted(false)
        }
        return new
    }

    /// Flips mute and returns the new state.
    @discardableResult
    func toggleMute() throws -> Bool {
        let new = !(try isMuted())
        try setMuted(new)
        return new
    }

    /// A read-only description for the status line. Never changes anything.
    func describe() throws -> String {
        let device = try defaultOutputDevice()
        let name = deviceName(device)
        guard !volumeAddresses(device).isEmpty else { throw VolumeError.volumeUnsupported(device: name) }
        let percent = Int((try volume() * 100).rounded())
        let muted = (try? isMuted()) == true ? ", muted" : ""
        return "\(name), \(percent)%\(muted)"
    }
}
