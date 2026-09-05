import Foundation
import os

/// Runs an `MTCClock` on a dedicated real-time thread and hands each message
/// to a sender ahead of its due time, stamped with the exact host time.
///
/// The thread wakes shortly before each quarter-frame is due, pulls every
/// message due within `lookahead`, and sleeps again with `mach_wait_until`.
/// Reference updates arrive from other threads (the audio tap or the MIDI
/// input callback) and are applied under a lock.
final class MTCStreamScheduler {
    typealias Sender = (_ bytes: [UInt8], _ hostTimeSeconds: Double) -> Void

    /// How far ahead messages are handed to CoreMIDI. One frame keeps timing
    /// tight while leaving enough slack for thread wake-up jitter.
    static let lookaheadFrames = 1.0
    /// Upper bound on one sleep, so stop requests and re-anchors are noticed promptly.
    static let maxSleepSeconds = 0.015
    /// Lookahead used before the rate is known.
    static let defaultLookaheadSeconds = 1.0 / 25.0

    private let clock: OSAllocatedUnfairLock<MTCClock>
    private let send: Sender
    private var thread: Thread?
    private let running = OSAllocatedUnfairLock(initialState: false)
    private let stateObserver: (MTCClock.State) -> Void
    private var lastReportedState: MTCClock.State = .stopped

    init(configuration: MTCClock.Configuration,
         send: @escaping Sender,
         stateChanged: @escaping (MTCClock.State) -> Void) {
        self.clock = OSAllocatedUnfairLock(initialState: MTCClock(configuration: configuration))
        self.send = send
        self.stateObserver = stateChanged
    }

    var state: MTCClock.State {
        clock.withLock { $0.state }
    }

    func start() {
        guard running.withLock({ wasRunning in
            defer { wasRunning = true }
            return !wasRunning
        }) else { return }

        let thread = Thread { [weak self] in
            self?.runLoop()
        }
        thread.name = "MTCStreamScheduler"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        running.withLock { $0 = false }
        thread = nil
        clock.withLock { $0.stop() }
        reportStateIfChanged(.stopped)
    }

    func updateConfiguration(_ configuration: MTCClock.Configuration) {
        clock.withLock { $0.configuration = configuration }
    }

    /// `position` is the frame that begins at host time `time`.
    func reference(_ position: Timecode, at time: Double) {
        clock.withLock { $0.reference(position, at: time) }
    }

    func locate(_ position: Timecode, at time: Double) {
        clock.withLock { $0.locate(position, at: time) }
    }

    // MARK: - Thread

    private func runLoop() {
        RealTimeThread.promoteCurrentThread(periodSeconds: 1.0 / 120.0)

        while running.withLock({ $0 }) {
            let now = HostTime.now()
            let (events, nextDue, state, lookahead) = clock.withLock { clock -> ([MTCClock.Event], Double?, MTCClock.State, Double) in
                let frame = clock.rate?.frameDuration ?? Self.defaultLookaheadSeconds
                let lookahead = frame * Self.lookaheadFrames
                let events = clock.events(until: now + lookahead)
                return (events, clock.nextEventTime, clock.state, lookahead)
            }

            for event in events {
                send(event.bytes, event.time)
            }
            reportStateIfChanged(state)

            var wake = now + Self.maxSleepSeconds
            if let nextDue {
                wake = min(wake, nextDue - lookahead)
            }
            if wake > now {
                mach_wait_until(HostTime.ticks(fromSeconds: wake))
            }
        }
    }

    private func reportStateIfChanged(_ state: MTCClock.State) {
        guard state != lastReportedState else { return }
        lastReportedState = state
        stateObserver(state)
    }
}

/// Helper for giving a thread a time-constraint (real-time) scheduling policy.
enum RealTimeThread {
    private static let logger = Logger(subsystem: "Rob-Sinclair-Inc.MIDITimecode", category: "RealTimeThread")

    /// Ask the kernel to schedule the calling thread with a time-constraint
    /// policy: it needs a short slice of CPU at regular intervals.
    static func promoteCurrentThread(periodSeconds: Double) {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticksPerSecond = 1_000_000_000.0 * Double(timebase.denom) / Double(timebase.numer)
        let period = UInt32(periodSeconds * ticksPerSecond)

        var policy = thread_time_constraint_policy(
            period: period,
            computation: period / 10,
            constraint: period / 2,
            preemptible: 1
        )
        let count = mach_msg_type_number_t(
            MemoryLayout<thread_time_constraint_policy>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &policy) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                thread_policy_set(
                    pthread_mach_thread_np(pthread_self()),
                    thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                    rebound,
                    count
                )
            }
        }
        if result != KERN_SUCCESS {
            logger.warning("Could not set real-time thread policy (kern_return \(result)); falling back to user-interactive QoS")
        }
    }
}
