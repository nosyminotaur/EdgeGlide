import AppKit
import EdgeGlideCore
import Foundation
import Observation
import ServiceManagement

/// App-wide state: settings, component status, and the gesture-to-action
/// wiring. Settings persist in `UserDefaults`.
@MainActor
@Observable
final class AppState {
    // MARK: Settings

    var enabled: Bool { didSet { save(enabled, .enabled); applyConfig() } }
    var edgeWidth: Double { didSet { save(edgeWidth, .edgeWidth); applyConfig() } }
    var sensitivity: Double { didSet { save(sensitivity, .sensitivity); applyConfig() } }
    var volumeEnabled: Bool { didSet { save(volumeEnabled, .volumeEnabled); applyConfig() } }
    var brightnessEnabled: Bool { didSet { save(brightnessEnabled, .brightnessEnabled); applyConfig() } }
    var muteEnabled: Bool { didSet { save(muteEnabled, .muteEnabled); applyConfig() } }
    var mediaEnabled: Bool { didSet { save(mediaEnabled, .mediaEnabled); applyConfig() } }
    var hapticStrength: HapticStrength {
        didSet {
            defaults.set(hapticStrength.rawValue, forKey: Key.hapticStrength.rawValue)
            haptics.strength = hapticStrength
        }
    }

    // MARK: Status shown in the menu

    var trackpadStatus = "Trackpad: starting"
    var volumeStatus = "Volume: not checked"
    var brightnessStatus = "Brightness: not checked"
    var mediaStatus = "Media: not checked"
    var hapticsStatus = "Haptics: not checked"
    var loginStatus = "Launch at login: not checked"
    var lastError: String?
    var lastAction: String?
    var launchAtLogin = false

    // MARK: Components

    private let defaults = UserDefaults.standard
    private let monitor = TouchMonitor()
    private let volume = VolumeControl()
    private let brightness = BrightnessControl()
    private let media = MediaControl()
    private let haptics = Haptics()
    private var wakeObserver: NSObjectProtocol?

    private enum Key: String {
        case enabled, edgeWidth, sensitivity, volumeEnabled, brightnessEnabled, muteEnabled, mediaEnabled, hapticStrength
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Key.enabled.rawValue: true,
            Key.edgeWidth.rawValue: 0.12,
            Key.sensitivity.rawValue: 1.0,
            Key.volumeEnabled.rawValue: true,
            Key.brightnessEnabled.rawValue: true,
            Key.muteEnabled.rawValue: true,
            Key.mediaEnabled.rawValue: true,
            Key.hapticStrength.rawValue: HapticStrength.medium.rawValue,
        ])
        enabled = d.bool(forKey: Key.enabled.rawValue)
        edgeWidth = d.double(forKey: Key.edgeWidth.rawValue)
        sensitivity = d.double(forKey: Key.sensitivity.rawValue)
        volumeEnabled = d.bool(forKey: Key.volumeEnabled.rawValue)
        brightnessEnabled = d.bool(forKey: Key.brightnessEnabled.rawValue)
        muteEnabled = d.bool(forKey: Key.muteEnabled.rawValue)
        mediaEnabled = d.bool(forKey: Key.mediaEnabled.rawValue)
        hapticStrength = HapticStrength(rawValue: d.string(forKey: Key.hapticStrength.rawValue) ?? "") ?? .medium
        haptics.strength = hapticStrength

        TouchDispatch.shared.configure(config: config, enabled: enabled) { [weak self] deviceID, events in
            self?.handle(events, deviceID: deviceID)
        }
        startMonitor()
        refreshStatus()

        // Multitouch devices stop sending frames after sleep, so restart them.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.app.notice("Woke from sleep; restarting multitouch devices")
                self?.startMonitor()
            }
        }
    }

    var config: EdgeGestureConfig {
        EdgeGestureConfig(
            edgeWidth: edgeWidth,
            sensitivity: sensitivity,
            volumeEnabled: volumeEnabled,
            brightnessEnabled: brightnessEnabled,
            muteEnabled: muteEnabled,
            mediaEnabled: mediaEnabled)
    }

    private func save(_ value: Any, _ key: Key) { defaults.set(value, forKey: key.rawValue) }
    private func applyConfig() { TouchDispatch.shared.update(config: config, enabled: enabled) }

    // MARK: Monitor

    func startMonitor() {
        do {
            let devices = try monitor.start()
            let builtIn = devices.filter(\.isBuiltIn).count
            trackpadStatus = "Trackpad: connected (\(devices.count) device\(devices.count == 1 ? "" : "s"), \(builtIn) built-in)"
            Log.touch.notice("\(self.trackpadStatus, privacy: .public)")
        } catch {
            trackpadStatus = "Trackpad: \(error.localizedDescription)"
            report(error, in: "Trackpad")
        }
    }

    /// Reads every component's state without changing anything.
    func refreshStatus() {
        do { volumeStatus = "Volume: \(try volume.describe())" } catch {
            volumeStatus = "Volume: \(error.localizedDescription)"
            Log.volume.error("\(error.localizedDescription, privacy: .public)")
        }
        do { brightnessStatus = "Brightness: \(try brightness.describe())" } catch {
            brightnessStatus = "Brightness: \(error.localizedDescription)"
            Log.brightness.error("\(error.localizedDescription, privacy: .public)")
        }
        mediaStatus = "Media: \(media.describe())"
        hapticsStatus = "Haptics: \(haptics.status)"
        refreshLoginStatus()
        Log.app.notice(
            "Status | \(self.trackpadStatus, privacy: .public) | \(self.volumeStatus, privacy: .public) | \(self.brightnessStatus, privacy: .public) | \(self.mediaStatus, privacy: .public) | \(self.hapticsStatus, privacy: .public) | \(self.loginStatus, privacy: .public)")
    }

    // MARK: Actions

    private func handle(_ events: [EdgeGestureEvent], deviceID: UInt64) {
        for event in events {
            do {
                switch event {
                case .volumeDelta(let delta):
                    let v = try volume.adjust(by: delta)
                    lastAction = "Volume \(Int((v * 100).rounded()))%"
                    volumeStatus = "Volume: \(Int((v * 100).rounded()))%"
                case .brightnessDelta(let delta):
                    let b = try brightness.adjust(by: delta)
                    lastAction = "Brightness \(Int((b * 100).rounded()))%"
                    brightnessStatus = "Brightness: \(Int((b * 100).rounded()))%"
                case .toggleMute:
                    let muted = try volume.toggleMute()
                    lastAction = muted ? "Muted" : "Unmuted"
                case .nextTrack:
                    lastAction = "Next track via \(try media.send(.nextTrack))"
                case .previousTrack:
                    lastAction = "Previous track via \(try media.send(.previousTrack))"
                }
                haptics.tick(deviceID: deviceID)
            } catch {
                report(error, in: "Gesture \(event)")
            }
        }
        hapticsStatus = "Haptics: \(haptics.status)"
    }

    private func report(_ error: Error, in context: String) {
        let message = "\(context): \(error.localizedDescription)"
        // Log every distinct failure; repeats of the same one during a slide
        // would flood the log without adding anything.
        if message != lastError { Log.app.error("\(message, privacy: .public)") }
        lastError = message
    }

    func requestMediaKeyAccess() {
        media.requestPostEventAccess()
        refreshStatus()
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            report(error, in: "Launch at login")
        }
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        switch status {
        case .enabled: loginStatus = "Launch at login: on"
        case .notRegistered: loginStatus = "Launch at login: off"
        case .requiresApproval: loginStatus = "Launch at login: approve in System Settings > General > Login Items"
        case .notFound: loginStatus = "Launch at login: off (system reports notFound; move EdgeGlide.app to /Applications if turning it on fails)"
        @unknown default: loginStatus = "Launch at login: unknown status \(status.rawValue)"
        }
    }
}
