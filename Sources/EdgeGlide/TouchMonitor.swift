import CoreFoundation
import EdgeGlideCore
import Foundation
import os

// MARK: - MultitouchSupport ABI

/// Opaque `MTDeviceRef`.
typealias MTDeviceRef = UnsafeMutableRawPointer

/// `typedef int (*MTContactCallbackFunction)(MTDeviceRef, MTTouch*, int nTouches, double timestamp, int frame);`
/// Some headers declare the return type as `void`. On arm64 and x86_64 the
/// caller ignores the return register, so returning `Int32` is safe either way.
typealias MTContactCallback = @convention(c) (
    MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterContactFrameCallbackFn = @convention(c) (MTDeviceRef?, MTContactCallback?) -> Void
private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef?, Int32) -> Int32
private typealias MTDeviceStopFn = @convention(c) (MTDeviceRef?) -> Int32
private typealias MTDeviceGetDeviceIDFn = @convention(c) (MTDeviceRef?, UnsafeMutablePointer<UInt64>?) -> Int32
private typealias MTDeviceIsBuiltInFn = @convention(c) (MTDeviceRef?) -> Bool

/// Byte layout of one `MTTouch` record.
///
/// Source: the `MTTouch` struct in OpenMultitouchSupport
/// (github.com/Kyome22/OpenMultitouchSupport, `OpenMultitouchSupportXCF/OpenMTInternal.h`),
/// which matches the layout MiddleClick (github.com/artginzburg/MiddleClick)
/// and Fingerglide use:
///
/// ```c
/// typedef struct { float x, y; } MTPoint;
/// typedef struct { MTPoint position, velocity; } MTVector;
/// typedef struct {
///     int      frame;            //  0
///     double   timestamp;        //  8 (4 bytes padding before it)
///     int      identifier;       // 16
///     int      state;            // 20  MTTouchState
///     int      fingerId;         // 24
///     int      handId;           // 28
///     MTVector normalizedVector; // 32  position x,y in 0...1, y = 0 at bottom
///     float    zTotal;           // 48  contact size
///     int      field9;           // 52
///     float    angle;            // 56
///     float    majorAxis;        // 60
///     float    minorAxis;        // 64
///     MTVector absoluteVector;   // 68  millimetres
///     int      field14;          // 84
///     int      field15;          // 88
///     float    zDensity;         // 92
/// } MTTouch;                     // sizeof == 96
/// ```
///
/// Swift does not guarantee C layout for its own structs, so the fields are
/// read at these explicit offsets instead of through a mirrored struct.
enum MTTouchLayout {
    static let stride = 96
    static let frame = 0
    static let timestamp = 8
    static let identifier = 16
    static let state = 20
    static let fingerId = 24
    static let handId = 28
    static let normalizedX = 32
    static let normalizedY = 36
    static let velocityX = 40
    static let velocityY = 44
    static let zTotal = 48
    static let angle = 56
    static let majorAxis = 60
    static let minorAxis = 64
}

/// `MTTouchState` values from the same header.
enum MTTouchState: Int32 {
    case notTracking = 0, startInRange, hoverInRange, makeTouch, touching, breakTouch, lingerInRange, outOfRange

    /// True only while the finger is pressed on the surface.
    static func isContact(_ raw: Int32) -> Bool {
        raw == MTTouchState.makeTouch.rawValue || raw == MTTouchState.touching.rawValue
    }
}

// MARK: - Callback dispatch

/// Shared state reached from the C callback, which cannot capture context.
/// MultitouchSupport calls the callback on its own background thread, so all
/// access goes through `lock`.
final class TouchDispatch: @unchecked Sendable {
    static let shared = TouchDispatch()

    private let lock = NSLock()
    private var recognizers: [UInt: EdgeGestureRecognizer] = [:]
    private var deviceIDs: [UInt: UInt64] = [:]
    private var config = EdgeGestureConfig()
    private var enabled = true
    private var loggedFirstFrame = false
    /// Called on the main actor with the multitouch device ID and the events.
    private var handler: (@MainActor @Sendable (UInt64, [EdgeGestureEvent]) -> Void)?

    func configure(
        config: EdgeGestureConfig, enabled: Bool,
        handler: @escaping @MainActor @Sendable (UInt64, [EdgeGestureEvent]) -> Void
    ) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        update(config: config, enabled: enabled, locked: true)
    }

    func update(config: EdgeGestureConfig, enabled: Bool) {
        update(config: config, enabled: enabled, locked: false)
    }

    private func update(config: EdgeGestureConfig, enabled: Bool, locked: Bool) {
        if !locked { lock.lock() }
        defer { if !locked { lock.unlock() } }
        self.config = config
        self.enabled = enabled
        for key in recognizers.keys {
            recognizers[key]?.config = config
            recognizers[key]?.reset()
        }
    }

    func register(device: MTDeviceRef, id: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let key = UInt(bitPattern: device)
        deviceIDs[key] = id
        recognizers[key] = EdgeGestureRecognizer(config: config)
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        recognizers.removeAll()
        deviceIDs.removeAll()
    }

    /// Runs on the MultitouchSupport thread.
    func handle(device: MTDeviceRef?, touches: UnsafeMutableRawPointer?, count: Int32, timestamp: Double) {
        guard let device else { return }
        var samples: [TouchSample] = []
        if let touches, count > 0 {
            samples.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                let base = touches + i * MTTouchLayout.stride
                let state = base.load(fromByteOffset: MTTouchLayout.state, as: Int32.self)
                samples.append(TouchSample(
                    id: Int(base.load(fromByteOffset: MTTouchLayout.identifier, as: Int32.self)),
                    x: Double(base.load(fromByteOffset: MTTouchLayout.normalizedX, as: Float.self)),
                    y: Double(base.load(fromByteOffset: MTTouchLayout.normalizedY, as: Float.self)),
                    isTouching: MTTouchState.isContact(state),
                    timestamp: base.load(fromByteOffset: MTTouchLayout.timestamp, as: Double.self)))
            }
        }

        lock.lock()
        let key = UInt(bitPattern: device)
        if !loggedFirstFrame, !samples.isEmpty {
            loggedFirstFrame = true
            let first = samples[0]
            Log.touch.notice(
                "First contact frame: \(samples.count, privacy: .public) touch(es), x=\(first.x, privacy: .public) y=\(first.y, privacy: .public)")
        }
        guard enabled, var recognizer = recognizers[key] else {
            lock.unlock()
            return
        }
        let events = recognizer.process(frame: samples, at: timestamp)
        recognizers[key] = recognizer
        let deviceID = deviceIDs[key] ?? 0
        let handler = self.handler
        lock.unlock()

        guard !events.isEmpty, let handler else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler(deviceID, events) }
        }
    }
}

/// The C callback. It captures nothing, as `@convention(c)` requires.
private let contactCallback: MTContactCallback = { device, touches, count, timestamp, _ in
    TouchDispatch.shared.handle(device: device, touches: touches, count: count, timestamp: timestamp)
    return 0
}

// MARK: - Monitor

struct TrackpadDevice: Sendable {
    let id: UInt64
    let isBuiltIn: Bool
}

/// Finds multitouch devices and feeds their frames to `TouchDispatch`.
@MainActor
final class TouchMonitor {
    private var framework: PrivateFramework?
    private var deviceList: CFArray?
    private var running: [MTDeviceRef] = []
    private(set) var devices: [TrackpadDevice] = []

    private var register: MTRegisterContactFrameCallbackFn?
    private var unregister: MTRegisterContactFrameCallbackFn?
    private var stopDevice: MTDeviceStopFn?

    /// Starts every multitouch device. Throws when nothing can be started.
    func start() throws -> [TrackpadDevice] {
        stop()

        let fw: PrivateFramework
        switch PrivateFramework.open("MultitouchSupport") {
        case .success(let opened): fw = opened
        case .failure(let error): throw error
        }
        framework = fw
        Log.touch.notice("MultitouchSupport.framework loaded")

        let createList = try fw.require("MTDeviceCreateList", as: MTDeviceCreateListFn.self)
        let register = try fw.require("MTRegisterContactFrameCallback", as: MTRegisterContactFrameCallbackFn.self)
        let startDevice = try fw.require("MTDeviceStart", as: MTDeviceStartFn.self)
        self.register = register
        self.unregister = fw.symbol("MTUnregisterContactFrameCallback", as: MTRegisterContactFrameCallbackFn.self)
        self.stopDevice = fw.symbol("MTDeviceStop", as: MTDeviceStopFn.self)
        let getID = fw.symbol("MTDeviceGetDeviceID", as: MTDeviceGetDeviceIDFn.self)
        let isBuiltIn = fw.symbol("MTDeviceIsBuiltIn", as: MTDeviceIsBuiltInFn.self)
        if getID == nil { Log.touch.error("MTDeviceGetDeviceID missing; haptics fall back to NSHapticFeedbackManager") }

        guard let list = createList()?.takeRetainedValue() else {
            throw TouchMonitorError.noDeviceList
        }
        // Keep the array alive: releasing it stops the callbacks.
        deviceList = list
        let count = CFArrayGetCount(list)
        Log.touch.notice("MTDeviceCreateList returned \(count, privacy: .public) device(s)")
        guard count > 0 else { throw TouchMonitorError.noDevices }

        var found: [TrackpadDevice] = []
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if let getID {
                let status = getID(device, &id)
                if status != 0 {
                    Log.touch.error("MTDeviceGetDeviceID failed on device \(index, privacy: .public): \(status, privacy: .public)")
                }
            }
            let builtIn = isBuiltIn?(device) ?? false
            TouchDispatch.shared.register(device: device, id: id)
            register(device, contactCallback)
            let status = startDevice(device, 0)
            if status != 0 {
                Log.touch.error("MTDeviceStart failed on device id=\(id, privacy: .public): \(status, privacy: .public)")
                unregister?(device, contactCallback)
                continue
            }
            Log.touch.notice(
                "Registered contact callback and started device id=\(id, privacy: .public) builtIn=\(builtIn, privacy: .public)")
            running.append(device)
            found.append(TrackpadDevice(id: id, isBuiltIn: builtIn))
        }
        devices = found
        guard !found.isEmpty else { throw TouchMonitorError.noDevicesStarted(count) }
        return found
    }

    func stop() {
        for device in running {
            unregister?(device, contactCallback)
            if let stopDevice {
                let status = stopDevice(device)
                if status != 0 { Log.touch.error("MTDeviceStop returned \(status, privacy: .public)") }
            }
        }
        running.removeAll()
        devices.removeAll()
        TouchDispatch.shared.removeAll()
        deviceList = nil
    }
}

enum TouchMonitorError: LocalizedError {
    case noDeviceList
    case noDevices
    case noDevicesStarted(Int)

    var errorDescription: String? {
        switch self {
        case .noDeviceList: "MTDeviceCreateList returned nothing"
        case .noDevices: "No multitouch devices found"
        case .noDevicesStarted(let n): "Found \(n) multitouch device(s), but none started"
        }
    }
}
