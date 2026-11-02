import Foundation

/// One contact in one trackpad frame, in normalized coordinates.
///
/// `x` and `y` run from 0 to 1. `y == 0` is the bottom edge of the trackpad
/// (the edge closest to you), matching MultitouchSupport's normalized vector.
public struct TouchSample: Sendable, Equatable {
    public var id: Int
    public var x: Double
    public var y: Double
    /// True while the finger is in contact with the surface. Hover and
    /// lift-off states are `false`; the recognizer treats them as lifted.
    public var isTouching: Bool
    /// Seconds, monotonic. Only differences matter.
    public var timestamp: Double

    public init(id: Int, x: Double, y: Double, isTouching: Bool = true, timestamp: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.isTouching = isTouching
        self.timestamp = timestamp
    }
}

/// What a recognized gesture asks the app to do.
public enum EdgeGestureEvent: Sendable, Equatable {
    /// Change output volume by this fraction of full scale (for example 1/16).
    case volumeDelta(Double)
    /// Change built-in display brightness by this fraction of full scale.
    case brightnessDelta(Double)
    case toggleMute
    case nextTrack
    case previousTrack
}

/// Tunable recognizer settings. All distances are fractions of the trackpad.
public struct EdgeGestureConfig: Sendable, Equatable {
    /// Width of the left and right edge zones.
    public var edgeWidth: Double
    /// Height of the bottom swipe zone.
    public var bottomHeight: Double
    /// Width and height of the top-right corner zone.
    public var cornerSize: Double
    /// Multiplier on vertical travel. 1.0 means a full-height slide moves the
    /// value by 100%.
    public var sensitivity: Double
    /// Quantization step for volume and brightness. One event per step.
    public var step: Double
    /// Horizontal travel that triggers a bottom swipe.
    public var swipeThreshold: Double
    /// Longest contact that still counts as a tap, in seconds.
    public var tapMaxDuration: Double
    /// Most movement that still counts as a tap.
    public var tapMaxMovement: Double
    /// Longest gap between the end of the first tap and the start of the second.
    public var doubleTapWindow: Double

    public var volumeEnabled: Bool
    public var brightnessEnabled: Bool
    public var muteEnabled: Bool
    public var mediaEnabled: Bool

    public init(
        edgeWidth: Double = 0.12,
        bottomHeight: Double = 0.15,
        cornerSize: Double = 0.15,
        sensitivity: Double = 1.0,
        step: Double = 1.0 / 16.0,
        swipeThreshold: Double = 0.25,
        tapMaxDuration: Double = 0.25,
        tapMaxMovement: Double = 0.03,
        doubleTapWindow: Double = 0.4,
        volumeEnabled: Bool = true,
        brightnessEnabled: Bool = true,
        muteEnabled: Bool = true,
        mediaEnabled: Bool = true
    ) {
        self.edgeWidth = edgeWidth
        self.bottomHeight = bottomHeight
        self.cornerSize = cornerSize
        self.sensitivity = sensitivity
        self.step = step
        self.swipeThreshold = swipeThreshold
        self.tapMaxDuration = tapMaxDuration
        self.tapMaxMovement = tapMaxMovement
        self.doubleTapWindow = doubleTapWindow
        self.volumeEnabled = volumeEnabled
        self.brightnessEnabled = brightnessEnabled
        self.muteEnabled = muteEnabled
        self.mediaEnabled = mediaEnabled
    }
}

/// Turns per-frame trackpad contacts into edge gesture events.
///
/// Rules:
/// - Only single-finger input counts. When two or more fingers touch, every
///   claim is dropped and nothing fires until all fingers lift.
/// - A gesture claims a touch only if the touch *starts* inside its zone.
///   Touches that start in the middle are ignored, so normal cursor use is
///   unaffected.
/// - Zone precedence at touch start: top-right corner, right edge, left edge,
///   bottom edge.
/// - A corner touch that moves vertically past the tap tolerance becomes a
///   volume slide, so you can still start a volume slide at the top.
///
/// The type is a plain value with no threading of its own. Feed it from one
/// thread at a time.
public struct EdgeGestureRecognizer: Sendable {
    public var config: EdgeGestureConfig

    private enum Zone: Sendable, Equatable {
        case corner
        case rightEdge
        case leftEdge
        case bottom
    }

    private struct Claim: Sendable {
        var touchID: Int
        var zone: Zone
        var startX: Double
        var startY: Double
        var startTime: Double
        var lastY: Double
        var maxMovement: Double = 0
        /// Unemitted vertical travel × sensitivity, for slides.
        var residual: Double = 0
        var swipeFired = false
    }

    private var claim: Claim?
    /// Touch IDs seen in contact in the previous frame.
    private var previousIDs: Set<Int> = []
    /// Set when two or more fingers touch; cleared when all fingers lift.
    private var multiTouchLock = false
    /// End time of the last qualifying corner tap, waiting for a second tap.
    private var pendingTapEnd: Double?

    public init(config: EdgeGestureConfig = EdgeGestureConfig()) {
        self.config = config
    }

    /// Drops all in-flight state, for example after sleep or a config change.
    public mutating func reset() {
        claim = nil
        previousIDs = []
        multiTouchLock = false
        pendingTapEnd = nil
    }

    /// Processes one frame and returns the events it produces, in order.
    ///
    /// - Parameters:
    ///   - touches: Every contact the device reports in this frame.
    ///   - time: The frame timestamp in seconds. Needed because a lift-off
    ///     frame can carry no touches at all.
    public mutating func process(frame touches: [TouchSample], at time: Double) -> [EdgeGestureEvent] {
        let active = touches.filter(\.isTouching)
        let activeIDs = Set(active.map(\.id))
        defer { previousIDs = activeIDs }

        if active.isEmpty {
            multiTouchLock = false
            return endClaimIfPresent(at: time)
        }

        if active.count > 1 {
            multiTouchLock = true
            claim = nil
            pendingTapEnd = nil
            return []
        }

        if multiTouchLock { return [] }

        let touch = active[0]

        // The claimed touch lifted and a different one landed in the same frame.
        var events: [EdgeGestureEvent] = []
        if let current = claim, current.touchID != touch.id {
            events += endClaimIfPresent(at: time)
        }

        if claim == nil {
            // Only a touch we have not seen before may start a gesture. A
            // touch that began in the middle, or survived a cancelled claim,
            // never gets claimed later.
            guard !previousIDs.contains(touch.id) else { return events }
            if let zone = zone(forStartAt: touch) {
                claim = Claim(
                    touchID: touch.id, zone: zone,
                    startX: touch.x, startY: touch.y,
                    startTime: touch.timestamp, lastY: touch.y)
            }
            return events
        }

        events += update(with: touch)
        return events
    }

    // MARK: - Zones

    private func zone(forStartAt t: TouchSample) -> Zone? {
        let c = config
        if c.muteEnabled, t.x >= 1 - c.cornerSize, t.y >= 1 - c.cornerSize { return .corner }
        if c.volumeEnabled, t.x >= 1 - c.edgeWidth { return .rightEdge }
        if c.brightnessEnabled, t.x <= c.edgeWidth { return .leftEdge }
        if c.mediaEnabled, t.y <= c.bottomHeight { return .bottom }
        return nil
    }

    // MARK: - Updates

    private mutating func update(with t: TouchSample) -> [EdgeGestureEvent] {
        guard var c = claim else { return [] }
        let movement = max(abs(t.x - c.startX), abs(t.y - c.startY))
        c.maxMovement = max(c.maxMovement, movement)
        var events: [EdgeGestureEvent] = []

        switch c.zone {
        case .corner:
            // Promote to a volume slide once the finger clearly slides
            // vertically. Count travel from the start so no step is lost.
            if config.volumeEnabled,
               abs(t.y - c.startY) > config.tapMaxMovement,
               abs(t.y - c.startY) >= abs(t.x - c.startX) {
                c.zone = .rightEdge
                c.lastY = c.startY
                events += slide(&c, to: t.y, make: EdgeGestureEvent.volumeDelta)
            }
        case .rightEdge:
            events += slide(&c, to: t.y, make: EdgeGestureEvent.volumeDelta)
        case .leftEdge:
            events += slide(&c, to: t.y, make: EdgeGestureEvent.brightnessDelta)
        case .bottom:
            let dx = t.x - c.startX
            let dy = t.y - c.startY
            if !c.swipeFired, abs(dx) >= config.swipeThreshold, abs(dx) > abs(dy) {
                c.swipeFired = true
                events.append(dx > 0 ? .nextTrack : .previousTrack)
            }
        }

        claim = c
        return events
    }

    private func slide(
        _ c: inout Claim, to y: Double, make: (Double) -> EdgeGestureEvent
    ) -> [EdgeGestureEvent] {
        let step = config.step
        guard step > 0 else { return [] }
        c.residual += (y - c.lastY) * config.sensitivity
        c.lastY = y
        var events: [EdgeGestureEvent] = []
        // Guard against a runaway loop on a bad sensitivity value.
        var budget = Int((1.0 / step).rounded(.up)) * 4
        while abs(c.residual) >= step - 1e-9, budget > 0 {
            let delta = c.residual > 0 ? step : -step
            events.append(make(delta))
            c.residual -= delta
            budget -= 1
        }
        return events
    }

    // MARK: - Lift-off

    private mutating func endClaimIfPresent(at end: Double) -> [EdgeGestureEvent] {
        guard let c = claim else { return [] }
        claim = nil
        guard c.zone == .corner else { return [] }

        let isTap = (end - c.startTime) <= config.tapMaxDuration
            && c.maxMovement <= config.tapMaxMovement
        guard isTap else {
            pendingTapEnd = nil
            return []
        }
        if let first = pendingTapEnd, c.startTime - first <= config.doubleTapWindow {
            pendingTapEnd = nil
            return [.toggleMute]
        }
        pendingTapEnd = end
        return []
    }
}
