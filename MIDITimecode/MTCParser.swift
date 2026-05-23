import Foundation

struct MTCParser {
    private(set) var hours: UInt8 = 0
    private(set) var minutes: UInt8 = 0
    private(set) var seconds: UInt8 = 0
    private(set) var frames: UInt8 = 0
    private(set) var frameRate: String = ""

    private var mtcHours: UInt8 = 0
    private var mtcMinutes: UInt8 = 0
    private var mtcSeconds: UInt8 = 0
    private var mtcFrames: UInt8 = 0

    var timecode: String {
        String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    /// Process a single MTC quarter-frame data byte.
    /// Returns `true` when all 8 quarter-frames have arrived and a full timecode is assembled.
    mutating func processQuarterFrame(_ dataByte: UInt8) -> Bool {
        let messageType = (dataByte >> 4) & 0x07
        let nibbleValue = dataByte & 0x0F

        switch messageType {
        case 0:
            mtcFrames = (mtcFrames & 0xF0) | nibbleValue
        case 1:
            mtcFrames = (mtcFrames & 0x0F) | (nibbleValue << 4)
        case 2:
            mtcSeconds = (mtcSeconds & 0xF0) | nibbleValue
        case 3:
            mtcSeconds = (mtcSeconds & 0x0F) | (nibbleValue << 4)
        case 4:
            mtcMinutes = (mtcMinutes & 0xF0) | nibbleValue
        case 5:
            mtcMinutes = (mtcMinutes & 0x0F) | (nibbleValue << 4)
        case 6:
            mtcHours = (mtcHours & 0xF0) | nibbleValue
        case 7:
            mtcHours = (mtcHours & 0x0F) | ((nibbleValue & 0x01) << 4)
            updateFrameRate(nibbleValue)

            hours = mtcHours
            minutes = min(mtcMinutes, 59)
            seconds = min(mtcSeconds, 59)
            frames = mtcFrames
            return true
        default:
            break
        }
        return false
    }

    private mutating func updateFrameRate(_ rateNibble: UInt8) {
        let rateType = (rateNibble >> 1) & 0x03
        switch rateType {
        case 0: frameRate = "24 fps"
        case 1: frameRate = "25 fps"
        case 2: frameRate = "29.97 fps (DF)"
        case 3: frameRate = "30 fps"
        default: frameRate = ""
        }
    }
}
