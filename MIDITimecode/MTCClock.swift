import Foundation

/// Free-running MTC quarter-frame stream, disciplined by an external timecode
/// reference (decoded LTC or incoming MTC).
///
/// This is a pure model: it has no threads, no MIDI and no wall clock. The
/// caller feeds it reference positions with host times (`reference(_:at:)`)
/// and pulls scheduled messages up to a horizon (`events(until:)`). All times
/// are host-clock seconds.
///
/// Behaviour, modelled on hardware LTC→MTC converters:
/// - Quarter-frames are emitted continuously at exactly 4 per frame. Each
///   8-message group encodes the counter value at its first message, so
///   consecutive groups advance by 2 frames.
/// - Small reference errors (under `jumpThresholdFrames`) slew the phase
///   gradually; larger ones re-anchor the stream at the next frame boundary
///   and precede it with an MTC Full Frame so receivers relocate at once.
/// - A reference that would re-anchor the stream is held until a second,
///   consistent reference confirms it, so one corrupt frame cannot move the
///   output. Lock and relock therefore take two reference frames.
/// - With no reference the stream freewheels for `freewheelFrames`, then stops.
struct MTCClock {
    enum State: String, Equatable, Sendable {
        case stopped = "Stopped"
        case locked = "Locked"
        case freewheeling = "Freewheel"
    }

    enum Message: Equatable, Sendable {
        case quarterFrame(index: Int, data: UInt8)
        case fullFrame(Timecode)
    }

    struct Event: Equatable, Sendable {
        /// Host time (seconds) at which the message should reach the receiver.
        let time: Double
        let message: Message
        let bytes: [UInt8]
    }

    struct Configuration: Equatable, Sendable {
        /// Frames of missing reference tolerated before the stream stops.
        var freewheelFrames: Int = 30
        /// Reference error (frames) at or above which the stream re-anchors.
        var jumpThresholdFrames: Double = 1.0
        /// Fraction of the measured error corrected per reference frame.
        var slewGain: Double = 0.05
        /// Largest phase correction (frames) applied per reference frame.
        var maxSlewPerFrame: Double = 0.1
        /// Frames of missing reference before the state reports freewheeling.
        /// References arrive an audio buffer late (up to a few frames on
        /// large-buffer interfaces), so this must not be too tight.
        var freewheelReportAfterFrames: Double = 4.0
    }

    static let quarterFramesPerFrame = 4
    static let quarterFramesPerGroup = 8
    /// How closely a second reference must agree with a pending re-anchor.
    static let confirmationToleranceFrames = 0.75
    /// A pending re-anchor older than this is discarded rather than confirmed.
    static let confirmationMaxSpanFrames = 4.0
    /// Gap between a Full Frame and the quarter-frame that follows it.
    static let fullFrameLeadSeconds = 0.002

    var configuration: Configuration

    private(set) var state: State = .stopped
    private(set) var rate: FrameRate?
    private(set) var jumpCount = 0

    private let generator = MTCGenerator()

    // Stream position
    private var frameIndex = 0          // counter: frame currently in progress
    private var groupIndex = 0          // frame index encoded by the current group
    private var nextQuarterFrame = 0    // 0...7 within the current group
    private var nextQuarterFrameTime = 0.0
    private var lastDispatchedTime = 0.0
    private var lastReferenceTime: Double?
    private var pending: [Event] = []
    private var candidate: (index: Int, time: Double, rate: FrameRate)?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Reference input

    /// Discipline the stream: `position` is the frame that begins at host time `time`.
    mutating func reference(_ position: Timecode, at time: Double) {
        let targetIndex = position.frameIndex

        if state != .stopped, let currentRate = rate, currentRate == position.rate,
           let predicted = predictedFrameIndex(at: time) {
            let error = Double(targetIndex) - predicted
            if abs(error) < configuration.jumpThresholdFrames {
                let correction = max(-configuration.maxSlewPerFrame,
                                     min(configuration.maxSlewPerFrame, error * configuration.slewGain))
                // A positive error means the reference is ahead: bring the stream forward.
                nextQuarterFrameTime -= correction * currentRate.frameDuration
                lastReferenceTime = time
                state = .locked
                candidate = nil
                return
            }
        }

        // This reference wants a re-anchor. Only act once a second reference
        // continues the same timeline; a lone outlier is dropped.
        let duration = position.rate.frameDuration
        if let candidate, candidate.rate == position.rate, time > candidate.time,
           time - candidate.time <= Self.confirmationMaxSpanFrames * duration {
            let predicted = Double(candidate.index) + (time - candidate.time) / duration
            if abs(Double(targetIndex) - predicted) <= Self.confirmationToleranceFrames {
                self.candidate = nil
                jump(to: targetIndex, rate: position.rate, at: time)
                return
            }
        }
        candidate = (targetIndex, time, position.rate)
    }

    /// Stop the quarter-frame stream and announce `position` with a Full Frame.
    /// Used while the reference runs backwards, which MTC cannot express.
    mutating func locate(_ position: Timecode, at time: Double) {
        state = .stopped
        rate = position.rate
        lastReferenceTime = nil
        candidate = nil
        let at = max(time, lastDispatchedTime)
        pending.append(Event(time: at, message: .fullFrame(position),
                             bytes: generator.fullFrameMessage(for: position)))
    }

    /// Stop the stream without announcing anything.
    mutating func stop() {
        state = .stopped
        lastReferenceTime = nil
        candidate = nil
        pending.removeAll()
    }

    // MARK: - Output

    /// Fractional frame index the stream is at when the host clock reads `time`.
    func predictedFrameIndex(at time: Double) -> Double? {
        guard let rate, state != .stopped else { return nil }
        let quarter = rate.frameDuration / Double(Self.quarterFramesPerFrame)
        let frameStart = nextQuarterFrameTime - Double(nextQuarterFrame % Self.quarterFramesPerFrame) * quarter
        return Double(frameIndex) + (time - frameStart) / rate.frameDuration
    }

    /// Host time the next quarter-frame is due, or nil when stopped.
    var nextEventTime: Double? {
        if let first = pending.first { return first.time }
        return state == .stopped ? nil : nextQuarterFrameTime
    }

    /// Pop every message due at or before `horizon`, in time order.
    mutating func events(until horizon: Double) -> [Event] {
        var out: [Event] = []
        while let first = pending.first, first.time <= horizon {
            out.append(first)
            pending.removeFirst()
        }

        guard let rate, state != .stopped else {
            noteDispatched(out)
            return out
        }

        let quarter = rate.frameDuration / Double(Self.quarterFramesPerFrame)
        while nextQuarterFrameTime <= horizon, state != .stopped {
            updateFreewheel(at: nextQuarterFrameTime, rate: rate)
            guard state != .stopped else { break }

            let groupTimecode = Timecode(frameIndex: groupIndex, rate: rate)
            let data = generator.quarterFrameDataByte(index: nextQuarterFrame, timecode: groupTimecode)
            out.append(Event(time: nextQuarterFrameTime,
                             message: .quarterFrame(index: nextQuarterFrame, data: data),
                             bytes: [MTCGenerator.quarterFrameStatus, data]))

            nextQuarterFrameTime += quarter
            nextQuarterFrame += 1
            if nextQuarterFrame % Self.quarterFramesPerFrame == 0 {
                frameIndex += 1
            }
            if nextQuarterFrame == Self.quarterFramesPerGroup {
                nextQuarterFrame = 0
                groupIndex = frameIndex
            }
        }

        noteDispatched(out)
        return out
    }

    // MARK: - Private

    private mutating func noteDispatched(_ events: [Event]) {
        if let last = events.last {
            lastDispatchedTime = max(lastDispatchedTime, last.time)
        }
    }

    private mutating func updateFreewheel(at time: Double, rate: FrameRate) {
        guard let lastReferenceTime else {
            state = .stopped
            return
        }
        let missing = (time - lastReferenceTime) / rate.frameDuration
        if missing > Double(configuration.freewheelFrames) {
            state = .stopped
            self.lastReferenceTime = nil
        } else if missing > configuration.freewheelReportAfterFrames {
            state = .freewheeling
        } else {
            state = .locked
        }
    }

    /// Re-anchor the stream so that frame `targetIndex` starts at `time`.
    /// Messages already dispatched cannot be recalled, so the new stream begins
    /// at the first frame boundary after the last dispatched message.
    private mutating func jump(to targetIndex: Int, rate newRate: FrameRate, at time: Double) {
        let duration = newRate.frameDuration
        var framesAhead = 0
        if lastDispatchedTime > time {
            framesAhead = Int(((lastDispatchedTime - time) / duration).rounded(.up))
        }
        let startTime = time + Double(framesAhead) * duration
        let startIndex = targetIndex + framesAhead

        rate = newRate
        frameIndex = startIndex
        groupIndex = startIndex
        nextQuarterFrame = 0
        nextQuarterFrameTime = startTime
        lastReferenceTime = time
        state = .locked
        jumpCount += 1

        let announced = Timecode(frameIndex: startIndex, rate: newRate)
        let fullFrameTime = max(lastDispatchedTime, startTime - Self.fullFrameLeadSeconds)
        pending.removeAll()
        pending.append(Event(time: fullFrameTime, message: .fullFrame(announced),
                             bytes: generator.fullFrameMessage(for: announced)))
    }
}
