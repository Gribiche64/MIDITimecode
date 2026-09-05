import XCTest
@testable import MIDITimecode

final class MTCClockTests: XCTestCase {

    private let rate = FrameRate.fps30
    private var frame: Double { rate.frameDuration }
    private var quarter: Double { rate.frameDuration / 4 }
    private let start = Timecode(hours: 4, minutes: 20, seconds: 0, frames: 2, rate: .fps30)
    private let generator = MTCGenerator()

    // MARK: - Helpers

    private func quarterFrames(_ events: [MTCClock.Event]) -> [(time: Double, index: Int, data: UInt8)] {
        events.compactMap {
            if case let .quarterFrame(index, data) = $0.message { return ($0.time, index, data) }
            return nil
        }
    }

    private func fullFrames(_ events: [MTCClock.Event]) -> [Timecode] {
        events.compactMap {
            if case let .fullFrame(tc) = $0.message { return tc }
            return nil
        }
    }

    /// Decode the timecode each 8-message group carries, with the time of its first message.
    private func groups(_ events: [MTCClock.Event]) -> [(start: Double, timecode: Timecode)] {
        var parser = MTCParser()
        var result: [(Double, Timecode)] = []
        var groupStart = 0.0
        for qf in quarterFrames(events) {
            if qf.index == 0 { groupStart = qf.time }
            if parser.processQuarterFrame(qf.data), let tc = parser.assembledTimecode {
                result.append((groupStart, tc))
            }
        }
        return result
    }

    private func groupTimecodes(_ events: [MTCClock.Event]) -> [Timecode] {
        groups(events).map(\.timecode)
    }

    /// The default horizon sits between quarter-frames so each pull returns
    /// exactly one frame's worth (4) of quarter-frames.
    private var pullHorizon: Double { frame - quarter / 2 }

    /// Feed one reference per frame, with optional per-frame time jitter, and
    /// return everything the clock emitted up to `frames` frames plus lookahead.
    /// A priming reference one frame before `start` lets the clock confirm and
    /// anchor the stream exactly at `start` / time 0.
    private func run(_ clock: inout MTCClock, frames: Int, jitter: (Int) -> Double = { _ in 0 },
                     lookahead: Double? = nil) -> [MTCClock.Event] {
        let lookahead = lookahead ?? pullHorizon
        var events: [MTCClock.Event] = []
        clock.reference(start.advanced(by: -1), at: -frame)
        for n in 0..<frames {
            let t = Double(n) * frame
            clock.reference(start.advanced(by: n), at: t + jitter(n))
            events += clock.events(until: t + lookahead)
        }
        return events
    }

    // MARK: - Stream shape

    func testEmitsFourQuarterFramesPerFrameWithExactSpacing() {
        var clock = MTCClock()
        let events = run(&clock, frames: 20)
        let qfs = quarterFrames(events)

        XCTAssertEqual(qfs.count, 20 * 4)
        for (i, qf) in qfs.enumerated() {
            XCTAssertEqual(qf.index, i % 8, "Quarter-frame sequence restarted at message \(i)")
            XCTAssertEqual(qf.time, Double(i) * quarter, accuracy: 1e-9)
        }
    }

    func testGroupsAdvanceByTwoFramesAndEncodeCounterAtFirstMessage() {
        var clock = MTCClock()
        let events = run(&clock, frames: 40)
        let groups = groupTimecodes(events)

        XCTAssertGreaterThanOrEqual(groups.count, 20)
        XCTAssertEqual(groups.first, start, "First group must carry the counter value at its QF0")
        for pair in zip(groups, groups.dropFirst()) {
            XCTAssertEqual(pair.1.frameIndex - pair.0.frameIndex, 2)
        }
    }

    func testFirstLockNeedsTwoConsistentReferencesThenSendsOneFullFrame() {
        var clock = MTCClock()
        XCTAssertEqual(clock.state, .stopped)
        XCTAssertTrue(clock.events(until: 1.0).isEmpty, "Nothing should be emitted before a reference")

        clock.reference(start.advanced(by: -1), at: -frame)
        XCTAssertEqual(clock.state, .stopped, "One reference is not enough to lock")
        XCTAssertTrue(clock.events(until: frame).isEmpty)

        clock.reference(start, at: 0)
        let events = clock.events(until: frame)
        XCTAssertEqual(clock.state, .locked)
        XCTAssertEqual(fullFrames(events), [start])
        XCTAssertEqual(events.first?.message, .fullFrame(start))
        XCTAssertEqual(events.first?.bytes, generator.fullFrameMessage(for: start))
        XCTAssertLessThanOrEqual(events[0].time, events[1].time)
        XCTAssertEqual(clock.jumpCount, 1)
    }

    func testDropFrameStreamSkipsDroppedFrameNumbers() {
        let dfStart = Timecode(hours: 1, minutes: 0, seconds: 59, frames: 20, rate: .df2997)
        var clock = MTCClock()
        var events: [MTCClock.Event] = []
        let d = FrameRate.df2997.frameDuration
        clock.reference(dfStart.advanced(by: -1), at: -d)
        for n in 0..<20 {
            clock.reference(dfStart.advanced(by: n), at: Double(n) * d)
            events += clock.events(until: Double(n) * d + d)
        }
        let groups = groupTimecodes(events)
        XCTAssertTrue(groups.contains(Timecode(hours: 1, minutes: 0, seconds: 59, frames: 28, rate: .df2997)))
        XCTAssertTrue(groups.contains(Timecode(hours: 1, minutes: 1, seconds: 0, frames: 2, rate: .df2997)))
        XCTAssertFalse(groups.contains { $0.minutes == 1 && $0.seconds == 0 && $0.frames < 2 })
    }

    // MARK: - Discipline

    func testJitteredReferencesConvergeWithoutRestarts() {
        var clock = MTCClock()
        // Deterministic ±10 ms jitter, plus a 0.4-frame initial phase offset the
        // clock has to slew out (the first reference anchors the stream 0.4
        // frames late relative to the later, jitter-centred references).
        var seed: UInt64 = 42
        func jitter(_ n: Int) -> Double {
            if n == 0 { return 0.4 * frame }
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(seed >> 11) / Double(1 << 53)
            return (unit * 2 - 1) * 0.010
        }
        let events = run(&clock, frames: 120, jitter: jitter)

        XCTAssertEqual(clock.jumpCount, 1, "Jitter under a frame must never re-anchor the stream")
        XCTAssertEqual(fullFrames(events).count, 1)
        let qfs = quarterFrames(events)
        for (i, qf) in qfs.enumerated() {
            XCTAssertEqual(qf.index, i % 8, "Quarter-frame sequence restarted at message \(i)")
        }

        // Phase should have converged to the jitter-free reference timeline.
        // Residual wander from ±10 ms jitter at the default gain is a few
        // hundredths of a frame; anything near the jump threshold is a failure.
        let t = 120.0 * frame
        let predicted = clock.predictedFrameIndex(at: t)!
        let expected = Double(start.advanced(by: 120).frameIndex)
        XCTAssertEqual(predicted, expected, accuracy: 0.1)
    }

    func testThreeFrameStepCausesExactlyOneJumpAndOneFullFrame() {
        var clock = MTCClock()
        var events = run(&clock, frames: 30)
        XCTAssertEqual(clock.jumpCount, 1)

        // Reference steps forward by 3 frames at frame 30 and continues from there.
        let step = 3
        for n in 30..<60 {
            let t = Double(n) * frame
            clock.reference(start.advanced(by: n + step), at: t)
            events += clock.events(until: t + pullHorizon)
        }

        XCTAssertEqual(clock.jumpCount, 2, "A 3-frame step must re-anchor exactly once")
        XCTAssertEqual(fullFrames(events).count, 2)

        // After the jump the stream must track the new reference.
        let t = 60.0 * frame
        XCTAssertEqual(clock.predictedFrameIndex(at: t)!,
                       Double(start.advanced(by: 60 + step).frameIndex), accuracy: 0.1)

        // Timestamps never go backwards, even across the jump.
        for pair in zip(events, events.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.time, pair.1.time)
        }
        // Every group after the jump encodes the stepped timeline at its first message.
        let afterJump = groups(events).filter { $0.start >= 33 * frame }
        XCTAssertGreaterThan(afterJump.count, 5)
        for group in afterJump {
            let expected = start.advanced(by: Int((group.start / frame).rounded()) + step)
            XCTAssertEqual(group.timecode, expected, "Group at \(group.start / frame) frames")
        }
    }

    func testRateChangeReanchorsWithFullFrame() {
        var clock = MTCClock()
        _ = run(&clock, frames: 10)
        let tc25 = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25)
        let d25 = FrameRate.fps25.frameDuration
        clock.reference(tc25, at: 10 * frame)
        clock.reference(tc25.advanced(by: 1), at: 10 * frame + d25)
        let events = clock.events(until: 10 * frame + 0.1)
        XCTAssertEqual(clock.rate, .fps25)
        XCTAssertEqual(fullFrames(events).first?.rate, .fps25)
        XCTAssertEqual(clock.jumpCount, 2)
    }

    // MARK: - Freewheel

    func testFreewheelsThenStopsAfterConfiguredFramesAndRelocksWithFullFrame() {
        var config = MTCClock.Configuration()
        config.freewheelFrames = 10
        var clock = MTCClock(configuration: config)
        _ = run(&clock, frames: 5)
        XCTAssertEqual(clock.state, .locked)

        // No more references. Pull events frame by frame and watch the state.
        var freewheelSeen = false
        var quarterFramesWhileStopped = 0
        var stoppedAtFrame: Int?
        for n in 5..<30 {
            let t = Double(n) * frame
            let events = clock.events(until: t + pullHorizon)
            if clock.state == .freewheeling { freewheelSeen = true }
            if clock.state == .stopped {
                if stoppedAtFrame == nil { stoppedAtFrame = n }
                if n > stoppedAtFrame! { quarterFramesWhileStopped += quarterFrames(events).count }
            }
        }
        XCTAssertTrue(freewheelSeen, "State must report freewheeling before stopping")
        XCTAssertEqual(clock.state, .stopped)
        XCTAssertNotNil(stoppedAtFrame)
        // Last reference at frame 4; stream may run until frame 4 + freewheelFrames.
        XCTAssertLessThanOrEqual(stoppedAtFrame!, 4 + config.freewheelFrames + 1)
        XCTAssertEqual(quarterFramesWhileStopped, 0, "No quarter-frames once stopped")

        // Relock: two consistent references restart the stream with a Full Frame.
        clock.reference(start.advanced(by: 39), at: 39.0 * frame)
        XCTAssertEqual(clock.state, .stopped, "A single reference must not relock")
        let relockTime = 40.0 * frame
        let relock = start.advanced(by: 40)
        clock.reference(relock, at: relockTime)
        let events = clock.events(until: relockTime + pullHorizon)
        XCTAssertEqual(clock.state, .locked)
        XCTAssertEqual(fullFrames(events), [relock])
        XCTAssertEqual(quarterFrames(events).count, 4)
        XCTAssertEqual(quarterFrames(events).first?.index, 0)
    }

    func testLocateSendsFullFrameOnlyAndHoldsStream() {
        var clock = MTCClock()
        _ = run(&clock, frames: 5)
        let position = Timecode(hours: 2, minutes: 0, seconds: 0, frames: 0, rate: .fps30)
        clock.locate(position, at: 6 * frame)
        let events = clock.events(until: 10 * frame)
        XCTAssertEqual(clock.state, .stopped)
        XCTAssertEqual(fullFrames(events), [position])
        XCTAssertTrue(quarterFrames(events).allSatisfy { $0.time < 6 * frame },
                      "No quarter-frames may be scheduled after a locate")
    }

    func testSingleCorruptReferenceIsIgnored() {
        var clock = MTCClock()
        var events = run(&clock, frames: 30)
        XCTAssertEqual(clock.jumpCount, 1)

        // One garbage frame in the middle of a good stream (what a decoder
        // re-bootstrapping after a dropout can produce).
        let garbage = Timecode(hours: 11, minutes: 0, seconds: 8, frames: 11, rate: .fps30)
        clock.reference(garbage, at: 30 * frame)
        events += clock.events(until: 30 * frame + pullHorizon)
        for n in 31..<60 {
            let t = Double(n) * frame
            clock.reference(start.advanced(by: n), at: t)
            events += clock.events(until: t + pullHorizon)
        }

        XCTAssertEqual(clock.jumpCount, 1, "A lone outlier must not re-anchor the stream")
        XCTAssertEqual(fullFrames(events).count, 1)
        XCTAssertEqual(clock.state, .locked)
        let qfs = quarterFrames(events)
        for (i, qf) in qfs.enumerated() {
            XCTAssertEqual(qf.index, i % 8, "Quarter-frame sequence restarted at message \(i)")
        }
        XCTAssertFalse(groupTimecodes(events).contains { $0.hours == 11 })
        XCTAssertEqual(clock.predictedFrameIndex(at: 60 * frame)!,
                       Double(start.advanced(by: 60).frameIndex), accuracy: 0.1)
    }

    func testTwoConsistentReferencesAfterStepJumpOnce() {
        var clock = MTCClock()
        _ = run(&clock, frames: 10)
        // Step of 5 frames, then an inconsistent frame, then a consistent pair.
        clock.reference(start.advanced(by: 15), at: 10 * frame)
        XCTAssertEqual(clock.jumpCount, 1)
        clock.reference(start.advanced(by: 200), at: 11 * frame)
        XCTAssertEqual(clock.jumpCount, 1, "Two disagreeing outliers must not jump")
        clock.reference(start.advanced(by: 201), at: 12 * frame)
        XCTAssertEqual(clock.jumpCount, 2, "A confirmed new timeline jumps once")
        XCTAssertEqual(clock.predictedFrameIndex(at: 12 * frame)!,
                       Double(start.advanced(by: 201).frameIndex), accuracy: 1e-6)
    }

    func testGroupsStartOnEvenFramesAtThirtyFps() {
        var clock = MTCClock()
        let odd = Timecode(hours: 4, minutes: 20, seconds: 0, frames: 1, rate: .fps30)
        clock.reference(odd.advanced(by: -1), at: -frame)
        clock.reference(odd, at: 0)
        var events = clock.events(until: 2 * frame + pullHorizon)
        for n in 1...4 {
            clock.reference(odd.advanced(by: n), at: Double(n) * frame)
            events += clock.events(until: Double(n) * frame + pullHorizon)
        }
        let first = groups(events).first
        XCTAssertEqual(first?.timecode, odd.advanced(by: 1), "Stream should start on the next even frame")
        XCTAssertEqual(first?.start ?? -1, frame, accuracy: 1e-9)
        XCTAssertTrue(groupTimecodes(events).allSatisfy { $0.frames % 2 == 0 })
    }

    func testGroupsMayStartOnOddFramesAtTwentyFiveFps() {
        var clock = MTCClock()
        let odd = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 1, rate: .fps25)
        let d = FrameRate.fps25.frameDuration
        clock.reference(odd.advanced(by: -1), at: -d)
        clock.reference(odd, at: 0)
        let events = clock.events(until: 2 * d)
        XCTAssertEqual(groups(events).first?.timecode, odd)
    }

    func testTwoIdenticalReferencesMillisecondsApartDoNotLock() {
        var clock = MTCClock()
        let garbage = Timecode(hours: 21, minutes: 0, seconds: 5, frames: 14, rate: .df2997)
        clock.reference(garbage, at: 1.000)
        clock.reference(garbage, at: 1.004)
        clock.reference(garbage, at: 1.009)
        XCTAssertEqual(clock.state, .stopped)
        XCTAssertEqual(clock.jumpCount, 0)
        XCTAssertTrue(clock.events(until: 2.0).isEmpty)
    }

    func testStopClearsPendingAndState() {
        var clock = MTCClock()
        clock.reference(start, at: 0)
        clock.stop()
        XCTAssertEqual(clock.state, .stopped)
        XCTAssertTrue(clock.events(until: 1).isEmpty)
        XCTAssertNil(clock.nextEventTime)
    }
}
