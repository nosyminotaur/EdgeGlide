import AppKit
import EdgeGlideCore
import Foundation

/// Plays a haptic tick on the trackpad.
///
/// It uses the private MTActuator API in MultitouchSupport when it resolves,
/// because that works without the app being frontmost. Otherwise it falls back
/// to `NSHapticFeedbackManager`, which the system may ignore while another app
/// is active.
@MainActor
final class Haptics {
    private typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenFn = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private var create: CreateFn?
    private var open: OpenFn?
    private var actuate: ActuateFn?
    private var actuators: [UInt64: CFTypeRef] = [:]
    /// Device IDs whose actuator failed, so the failure is logged once.
    private var failedDevices: Set<UInt64> = []
    private(set) var status = "Not checked"

    var strength: HapticStrength = .medium

    init() {
        switch PrivateFramework.open("MultitouchSupport") {
        case .failure(let error):
            status = "MTActuator unavailable, using system haptics"
            Log.haptics.error("\(error.localizedDescription, privacy: .public)")
        case .success(let fw):
            create = fw.symbol("MTActuatorCreateFromDeviceID", as: CreateFn.self)
            open = fw.symbol("MTActuatorOpen", as: OpenFn.self)
            actuate = fw.symbol("MTActuatorActuate", as: ActuateFn.self)
            let resolved = create != nil && open != nil && actuate != nil
            Log.haptics.notice(
                "MTActuator symbols: create=\(self.create != nil, privacy: .public) open=\(self.open != nil, privacy: .public) actuate=\(self.actuate != nil, privacy: .public)")
            status = resolved ? "MTActuator ready" : "MTActuator missing, using system haptics"
        }
    }

    /// Actuation IDs as used by HapticKey (github.com/niw/HapticKey):
    /// weak 3, medium 4, strong 6, with arguments (0, 0.0, 2.0).
    private var actuationID: Int32? {
        switch strength {
        case .off: nil
        case .weak: 3
        case .medium: 4
        case .strong: 6
        }
    }

    private var fallbackPattern: NSHapticFeedbackManager.FeedbackPattern {
        switch strength {
        case .off, .weak: .alignment
        case .medium: .levelChange
        case .strong: .generic
        }
    }

    func tick(deviceID: UInt64) {
        guard let actuationID else { return }
        if let actuator = actuator(for: deviceID), let actuate {
            let result = actuate(actuator, actuationID, 0, 0.0, 2.0)
            if result == 0 { return }
            Log.haptics.error("MTActuatorActuate returned \(result, privacy: .public); using system haptics")
            status = "MTActuatorActuate failed (\(result)), using system haptics"
        }
        NSHapticFeedbackManager.defaultPerformer.perform(fallbackPattern, performanceTime: .now)
    }

    private func actuator(for deviceID: UInt64) -> CFTypeRef? {
        if let cached = actuators[deviceID] { return cached }
        guard deviceID != 0, !failedDevices.contains(deviceID), let create, let open else { return nil }
        guard let actuator = create(deviceID)?.takeRetainedValue() else {
            failedDevices.insert(deviceID)
            Log.haptics.error("MTActuatorCreateFromDeviceID(\(deviceID, privacy: .public)) returned nil")
            status = "No actuator for device \(deviceID), using system haptics"
            return nil
        }
        let result = open(actuator)
        guard result == 0 else {
            failedDevices.insert(deviceID)
            Log.haptics.error("MTActuatorOpen(\(deviceID, privacy: .public)) returned \(result, privacy: .public)")
            status = "MTActuatorOpen failed (\(result)), using system haptics"
            return nil
        }
        Log.haptics.notice("Opened MTActuator for device \(deviceID, privacy: .public)")
        actuators[deviceID] = actuator
        status = "MTActuator open"
        return actuator
    }
}
