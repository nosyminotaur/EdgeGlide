import CoreGraphics
import Foundation

enum BrightnessError: LocalizedError {
    case unavailable(String)
    case noBuiltInDisplay
    case call(String, Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Brightness control unavailable: \(reason)"
        case .noBuiltInDisplay: "No built-in display is online"
        case .call(let fn, let status): "\(fn) returned \(status)"
        }
    }
}

/// Changes built-in display brightness through the private DisplayServices
/// framework, which is what the brightness keys use on Apple silicon.
@MainActor
final class BrightnessControl {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias ChangedFn = @convention(c) (CGDirectDisplayID, Double) -> Int32

    private var get: GetFn?
    private var set: SetFn?
    private var changed: ChangedFn?
    private(set) var loadError: Error?

    init() {
        switch PrivateFramework.open("DisplayServices") {
        case .failure(let error):
            loadError = error
            Log.brightness.error("\(error.localizedDescription, privacy: .public)")
        case .success(let fw):
            do {
                get = try fw.require("DisplayServicesGetBrightness", as: GetFn.self)
                set = try fw.require("DisplayServicesSetBrightness", as: SetFn.self)
                // Optional: tells the system the value changed so other UI updates.
                changed = fw.symbol("DisplayServicesBrightnessChanged", as: ChangedFn.self)
                Log.brightness.notice(
                    "DisplayServicesGetBrightness/SetBrightness resolved; BrightnessChanged \(self.changed == nil ? "missing" : "resolved", privacy: .public)")
            } catch {
                loadError = error
                Log.brightness.error("\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The built-in display, or the main display when none is marked built-in.
    func targetDisplay() throws -> CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        let status = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        if status == .success, let builtIn = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return builtIn
        }
        throw BrightnessError.noBuiltInDisplay
    }

    func brightness() throws -> Float {
        guard let get else { throw BrightnessError.unavailable(loadError?.localizedDescription ?? "not loaded") }
        let display = try targetDisplay()
        var value: Float = 0
        let status = get(display, &value)
        guard status == 0 else { throw BrightnessError.call("DisplayServicesGetBrightness", status) }
        return value
    }

    @discardableResult
    func adjust(by delta: Double) throws -> Float {
        guard let set else { throw BrightnessError.unavailable(loadError?.localizedDescription ?? "not loaded") }
        let display = try targetDisplay()
        let new = min(max(try brightness() + Float(delta), 0), 1)
        let status = set(display, new)
        guard status == 0 else { throw BrightnessError.call("DisplayServicesSetBrightness", status) }
        if let changed {
            let note = changed(display, Double(new))
            if note != 0 { Log.brightness.error("DisplayServicesBrightnessChanged returned \(note, privacy: .public)") }
        }
        return new
    }

    /// Read-only status for the menu.
    func describe() throws -> String {
        "\(Int((try brightness() * 100).rounded()))%"
    }
}
