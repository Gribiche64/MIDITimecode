import Foundation

/// Frame-index arithmetic for `Timecode`, including 29.97 drop-frame counting.
///
/// A frame index is the number of frames since 00:00:00:00 at the given rate.
/// For drop-frame, frames 00 and 01 do not exist at the start of any minute
/// except minutes 0, 10, 20, 30, 40 and 50, so the index accounts for the
/// dropped numbers and the conversion back restores them.
extension FrameRate {
    /// Frame numbers skipped at the start of a non-tenth minute in drop-frame.
    static let dropFrameSkip = 2

    /// Frames in one nominal minute (before any drop-frame adjustment).
    var framesPerNominalMinute: Int { nominalFPS * 60 }

    /// Frames in one real ten-minute block.
    var framesPerTenMinutes: Int {
        if self == .df2997 {
            return framesPerNominalMinute * 10 - Self.dropFrameSkip * 9
        }
        return framesPerNominalMinute * 10
    }

    /// Frames in a 24-hour day at this rate.
    var framesPerDay: Int { framesPerTenMinutes * 6 * 24 }
}

extension Timecode {
    /// Absolute frame index since 00:00:00:00, drop-frame aware.
    var frameIndex: Int {
        let totalMinutes = Int(hours) * 60 + Int(minutes)
        var index = (totalMinutes * 60 + Int(seconds)) * rate.nominalFPS + Int(frames)
        if rate == .df2997 {
            index -= FrameRate.dropFrameSkip * (totalMinutes - totalMinutes / 10)
        }
        return index
    }

    /// Timecode for an absolute frame index, wrapping at 24 hours.
    init(frameIndex: Int, rate: FrameRate) {
        let day = rate.framesPerDay
        let wrapped = ((frameIndex % day) + day) % day
        let fps = rate.nominalFPS

        let totalMinutes: Int
        let frameInMinute: Int
        if rate == .df2997 {
            let tenMinuteBlocks = wrapped / rate.framesPerTenMinutes
            let inBlock = wrapped % rate.framesPerTenMinutes
            let firstMinute = rate.framesPerNominalMinute
            let laterMinute = firstMinute - FrameRate.dropFrameSkip
            if inBlock < firstMinute {
                totalMinutes = tenMinuteBlocks * 10
                frameInMinute = inBlock
            } else {
                let rest = inBlock - firstMinute
                totalMinutes = tenMinuteBlocks * 10 + 1 + rest / laterMinute
                frameInMinute = rest % laterMinute + FrameRate.dropFrameSkip
            }
        } else {
            totalMinutes = wrapped / rate.framesPerNominalMinute
            frameInMinute = wrapped % rate.framesPerNominalMinute
        }

        self.init(
            hours: UInt8(totalMinutes / 60),
            minutes: UInt8(totalMinutes % 60),
            seconds: UInt8(frameInMinute / fps),
            frames: UInt8(frameInMinute % fps),
            rate: rate
        )
    }

    /// The timecode `count` frames later (or earlier, if negative).
    func advanced(by count: Int) -> Timecode {
        Timecode(frameIndex: frameIndex + count, rate: rate)
    }
}
