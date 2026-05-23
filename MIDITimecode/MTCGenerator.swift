import Foundation

struct MTCGenerator {
    /// Generate the data byte for a specific quarter-frame message (0-7).
    func quarterFrameDataByte(index: Int, timecode: Timecode) -> UInt8 {
        let messageType = UInt8(index & 0x07)
        let nibble: UInt8

        switch messageType {
        case 0: nibble = timecode.frames & 0x0F
        case 1: nibble = (timecode.frames >> 4) & 0x0F
        case 2: nibble = timecode.seconds & 0x0F
        case 3: nibble = (timecode.seconds >> 4) & 0x0F
        case 4: nibble = timecode.minutes & 0x0F
        case 5: nibble = (timecode.minutes >> 4) & 0x0F
        case 6: nibble = timecode.hours & 0x0F
        case 7:
            let rateCode = timecode.rate.mtcRateCode
            nibble = (rateCode << 1) | ((timecode.hours >> 4) & 0x01)
        default: nibble = 0
        }

        return (messageType << 4) | nibble
    }

    /// Generate all 8 quarter-frame data bytes for a given timecode.
    func allQuarterFrameDataBytes(for timecode: Timecode) -> [UInt8] {
        (0..<8).map { quarterFrameDataByte(index: $0, timecode: timecode) }
    }

    /// Generate a full MIDI quarter-frame message [0xF1, dataByte] for a given index.
    func quarterFrameMessage(index: Int, timecode: Timecode) -> [UInt8] {
        [0xF1, quarterFrameDataByte(index: index, timecode: timecode)]
    }
}
