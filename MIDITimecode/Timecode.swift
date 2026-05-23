import Foundation

enum FrameRate: String, CaseIterable, Identifiable, Sendable {
    case fps24 = "24 fps"
    case fps25 = "25 fps"
    case df2997 = "29.97 fps (DF)"
    case fps30 = "30 fps"

    var id: String { rawValue }

    /// MTC rate code encoded in quarter-frame message type 7.
    var mtcRateCode: UInt8 {
        switch self {
        case .fps24: return 0
        case .fps25: return 1
        case .df2997: return 2
        case .fps30: return 3
        }
    }

    /// Maximum valid frame number for this rate.
    var maxFrames: UInt8 {
        switch self {
        case .fps24: return 23
        case .fps25: return 24
        case .fps30, .df2997: return 29
        }
    }

    /// Nominal frames per second (integer).
    var nominalFPS: Int {
        switch self {
        case .fps24: return 24
        case .fps25: return 25
        case .df2997: return 30
        case .fps30: return 30
        }
    }

    /// Duration of one frame in seconds.
    var frameDuration: Double {
        switch self {
        case .fps24: return 1.0 / 24.0
        case .fps25: return 1.0 / 25.0
        case .df2997: return 1001.0 / 30000.0
        case .fps30: return 1.0 / 30.0
        }
    }

    /// Classify a frame rate from a measured frame duration in seconds.
    static func fromFrameDuration(_ duration: Double) -> FrameRate {
        // Expected durations: 24fps=41.67ms, 25fps=40ms, 30fps=33.33ms
        let ms = duration * 1000.0
        if ms > 41.0 { return .fps24 }
        if ms > 38.0 { return .fps25 }
        return .fps30  // 29.97 vs 30 distinguished by drop-frame flag, not timing
    }

    /// Initialise from an MTC rate code (0-3).
    init?(mtcRateCode: UInt8) {
        switch mtcRateCode {
        case 0: self = .fps24
        case 1: self = .fps25
        case 2: self = .df2997
        case 3: self = .fps30
        default: return nil
        }
    }
}

struct Timecode: Equatable, Sendable {
    var hours: UInt8
    var minutes: UInt8
    var seconds: UInt8
    var frames: UInt8
    var rate: FrameRate

    static let zero = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, rate: .fps25)

    var displayString: String {
        String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    /// Clamp all fields to valid ranges.
    var clamped: Timecode {
        Timecode(
            hours: hours,
            minutes: min(minutes, 59),
            seconds: min(seconds, 59),
            frames: min(frames, rate.maxFrames),
            rate: rate
        )
    }
}
