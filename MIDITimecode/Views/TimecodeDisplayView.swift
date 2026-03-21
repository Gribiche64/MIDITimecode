import SwiftUI

struct TimecodeDisplayView: View {
    let timecode: String
    let tubeColor: TubeColor

    // Timecode format: HH:MM:SS:FF → 8 digits, 3 separators
    // Positions: D D : D D : D D : D D
    //            0 1 s 2 3 s 4 5 s 6 7

    private var digits: [String] {
        let cleaned = timecode.replacingOccurrences(of: ":", with: "")
        return cleaned.map { String($0) }
    }

    /// Maps a sequential digit position (0-7) to its visual index for color purposes.
    func digitIndex(for position: Int) -> Int {
        position
    }

    /// Maps a separator position (0-2) to an index for color purposes.
    func separatorIndex(for position: Int) -> Int {
        // Place separator indices between their surrounding digit indices
        switch position {
        case 0: return 1  // Between digits 1 and 2
        case 1: return 3  // Between digits 3 and 4
        case 2: return 5  // Between digits 5 and 6
        default: return position
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            let allDigits = digits
            if allDigits.count >= 8 {
                // HH
                ValveDigitView(digit: allDigits[0], digitIndex: digitIndex(for: 0), tubeColor: tubeColor)
                ValveDigitView(digit: allDigits[1], digitIndex: digitIndex(for: 1), tubeColor: tubeColor)
                SeparatorView(separatorIndex: separatorIndex(for: 0), tubeColor: tubeColor)

                // MM
                ValveDigitView(digit: allDigits[2], digitIndex: digitIndex(for: 2), tubeColor: tubeColor)
                ValveDigitView(digit: allDigits[3], digitIndex: digitIndex(for: 3), tubeColor: tubeColor)
                SeparatorView(separatorIndex: separatorIndex(for: 1), tubeColor: tubeColor)

                // SS
                ValveDigitView(digit: allDigits[4], digitIndex: digitIndex(for: 4), tubeColor: tubeColor)
                ValveDigitView(digit: allDigits[5], digitIndex: digitIndex(for: 5), tubeColor: tubeColor)
                SeparatorView(separatorIndex: separatorIndex(for: 2), tubeColor: tubeColor)

                // FF
                ValveDigitView(digit: allDigits[6], digitIndex: digitIndex(for: 6), tubeColor: tubeColor)
                ValveDigitView(digit: allDigits[7], digitIndex: digitIndex(for: 7), tubeColor: tubeColor)
            }
        }
    }
}
