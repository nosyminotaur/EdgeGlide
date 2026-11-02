import Testing
@testable import EdgeGlideCore

/// Drives a recognizer with scripted single-finger strokes.
private struct Driver {
    var recognizer = EdgeGestureRecognizer()
    var time = 0.0
    var events: [EdgeGestureEvent] = []

    /// Moves one finger along a straight line from `from` to `to`, then lifts it.
    mutating func stroke(
        id: Int, from: (Double, Double), to: (Double, Double),
        steps: Int = 20, duration: Double = 0.3
    ) {
        let dt = duration / Double(steps)
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            let x = from.0 + (to.0 - from.0) * f
            let y = from.1 + (to.1 - from.1) * f
            frame([TouchSample(id: id, x: x, y: y, timestamp: time)])
            if i < steps { time += dt }
        }
        lift()
    }

    /// Short contact at one point.
    mutating func tap(id: Int, at p: (Double, Double), duration: Double = 0.08) {
        frame([TouchSample(id: id, x: p.0, y: p.1, timestamp: time)])
        time += duration
        frame([TouchSample(id: id, x: p.0, y: p.1, timestamp: time)])
        lift()
    }

    mutating func lift() {
        time += 0.01
        frame([])
    }

    mutating func wait(_ seconds: Double) { time += seconds }

    mutating func frame(_ touches: [TouchSample]) {
        events += recognizer.process(frame: touches, at: time)
    }
}

private func volumeTotal(_ events: [EdgeGestureEvent]) -> Double {
    events.reduce(0) { acc, e in
        if case .volumeDelta(let d) = e { return acc + d }
        return acc
    }
}

private func brightnessTotal(_ events: [EdgeGestureEvent]) -> Double {
    events.reduce(0) { acc, e in
        if case .brightnessDelta(let d) = e { return acc + d }
        return acc
    }
}

@Suite("Edge gesture recognizer")
struct EdgeGestureRecognizerTests {
    @Test("Right edge slide up raises volume in quantized steps")
    func rightEdgeUp() {
        var d = Driver()
        d.stroke(id: 1, from: (0.95, 0.2), to: (0.95, 0.7))
        #expect(!d.events.isEmpty)
        #expect(d.events.allSatisfy { if case .volumeDelta(let v) = $0 { v == 1.0 / 16 } else { false } })
        // 0.5 travel × sensitivity 1 = 8 steps of 1/16.
        #expect(d.events.count == 8)
        #expect(abs(volumeTotal(d.events) - 0.5) < 1e-9)
    }

    @Test("Right edge slide down lowers volume")
    func rightEdgeDown() {
        var d = Driver()
        d.stroke(id: 1, from: (0.95, 0.7), to: (0.95, 0.2))
        #expect(d.events.count == 8)
        #expect(abs(volumeTotal(d.events) + 0.5) < 1e-9)
    }

    @Test("Sensitivity scales the number of steps")
    func sensitivity() {
        var d = Driver()
        d.recognizer.config.sensitivity = 2
        d.stroke(id: 1, from: (0.95, 0.2), to: (0.95, 0.45))
        #expect(abs(volumeTotal(d.events) - 0.5) < 1e-9)
    }

    @Test("Left edge slide changes brightness, not volume")
    func leftEdge() {
        var d = Driver()
        d.stroke(id: 1, from: (0.05, 0.3), to: (0.05, 0.8))
        #expect(abs(brightnessTotal(d.events) - 0.5) < 1e-9)
        #expect(volumeTotal(d.events) == 0)

        var down = Driver()
        down.stroke(id: 2, from: (0.05, 0.8), to: (0.05, 0.3))
        #expect(abs(brightnessTotal(down.events) + 0.5) < 1e-9)
    }

    @Test("A touch that starts in the middle produces nothing, even when it reaches an edge")
    func middleStart() {
        var d = Driver()
        d.stroke(id: 1, from: (0.5, 0.5), to: (0.97, 0.9))
        d.stroke(id: 2, from: (0.5, 0.5), to: (0.03, 0.1))
        d.stroke(id: 3, from: (0.5, 0.5), to: (0.9, 0.05))
        #expect(d.events.isEmpty)
    }

    @Test("Corner double-tap toggles mute exactly once")
    func cornerDoubleTap() {
        var d = Driver()
        d.tap(id: 1, at: (0.95, 0.95))
        d.wait(0.15)
        d.tap(id: 2, at: (0.95, 0.95))
        #expect(d.events == [.toggleMute])
    }

    @Test("A single corner tap does nothing")
    func singleCornerTap() {
        var d = Driver()
        d.tap(id: 1, at: (0.95, 0.95))
        d.wait(1.0)
        #expect(d.events.isEmpty)
    }

    @Test("Two corner taps too far apart do nothing")
    func slowCornerTaps() {
        var d = Driver()
        d.tap(id: 1, at: (0.95, 0.95))
        d.wait(0.6)
        d.tap(id: 2, at: (0.95, 0.95))
        #expect(d.events.isEmpty)
    }

    @Test("A long press in the corner is not a tap")
    func longCornerPress() {
        var d = Driver()
        d.tap(id: 1, at: (0.95, 0.95), duration: 0.5)
        d.wait(0.1)
        d.tap(id: 2, at: (0.95, 0.95))
        #expect(d.events.isEmpty)
    }

    @Test("Bottom swipe right is next track, left is previous track, once per swipe")
    func bottomSwipe() {
        var d = Driver()
        d.stroke(id: 1, from: (0.3, 0.05), to: (0.8, 0.06))
        #expect(d.events == [.nextTrack])

        var l = Driver()
        l.stroke(id: 2, from: (0.8, 0.05), to: (0.3, 0.06))
        #expect(l.events == [.previousTrack])
    }

    @Test("Two-finger touches produce nothing")
    func twoFingers() {
        var d = Driver()
        for i in 0...20 {
            let y = 0.2 + 0.5 * Double(i) / 20
            d.frame([
                TouchSample(id: 1, x: 0.95, y: y, timestamp: d.time),
                TouchSample(id: 2, x: 0.05, y: y, timestamp: d.time),
            ])
            d.time += 0.015
        }
        d.lift()
        // Two fingers swiping along the bottom.
        for i in 0...20 {
            let x = 0.3 + 0.5 * Double(i) / 20
            d.frame([
                TouchSample(id: 3, x: x, y: 0.05, timestamp: d.time),
                TouchSample(id: 4, x: x, y: 0.1, timestamp: d.time),
            ])
            d.time += 0.015
        }
        d.lift()
        #expect(d.events.isEmpty)
    }

    @Test("A second finger cancels an edge slide in progress")
    func secondFingerCancels() {
        var d = Driver()
        d.frame([TouchSample(id: 1, x: 0.95, y: 0.2, timestamp: d.time)])
        d.time += 0.02
        d.frame([
            TouchSample(id: 1, x: 0.95, y: 0.25, timestamp: d.time),
            TouchSample(id: 2, x: 0.5, y: 0.5, timestamp: d.time),
        ])
        d.time += 0.02
        // Second finger lifts; the first keeps sliding but must stay unclaimed.
        for i in 0...10 {
            d.frame([TouchSample(id: 1, x: 0.95, y: 0.25 + 0.05 * Double(i), timestamp: d.time)])
            d.time += 0.02
        }
        d.lift()
        #expect(d.events.isEmpty)
    }

    @Test("Disabled gestures do not fire")
    func disabled() {
        var d = Driver()
        d.recognizer.config.volumeEnabled = false
        d.recognizer.config.mediaEnabled = false
        d.stroke(id: 1, from: (0.95, 0.3), to: (0.95, 0.8))
        d.stroke(id: 2, from: (0.3, 0.05), to: (0.8, 0.05))
        #expect(d.events.isEmpty)
    }

    @Test("A vertical slide that starts in the corner becomes a volume slide")
    func cornerSlideBecomesVolume() {
        var d = Driver()
        d.stroke(id: 1, from: (0.95, 0.95), to: (0.95, 0.45))
        #expect(abs(volumeTotal(d.events) + 0.5) < 1e-9)
        #expect(!d.events.contains(.toggleMute))
    }
}
