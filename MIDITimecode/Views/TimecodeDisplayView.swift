import SwiftUI

struct TimecodeDisplayView: View {
    let timecode: String
    let tubeColor: TubeColor

    private var digits: [String] {
        let cleaned = timecode.replacingOccurrences(of: ":", with: "")
        return cleaned.map { String($0) }
    }

    func digitIndex(for position: Int) -> Int {
        position
    }

    func separatorIndex(for position: Int) -> Int {
        switch position {
        case 0: return 1
        case 1: return 3
        case 2: return 5
        default: return position
        }
    }

    var body: some View {
        GeometryReader { geo in
            let allDigits = digits
            if allDigits.count >= 8 {
                HStack(spacing: 4) {
                    ValveDigitView(digit: allDigits[0], digitIndex: digitIndex(for: 0), tubeColor: tubeColor)
                    ValveDigitView(digit: allDigits[1], digitIndex: digitIndex(for: 1), tubeColor: tubeColor)
                    SeparatorView(separatorIndex: separatorIndex(for: 0), tubeColor: tubeColor, digitHeight: geo.size.height)

                    ValveDigitView(digit: allDigits[2], digitIndex: digitIndex(for: 2), tubeColor: tubeColor)
                    ValveDigitView(digit: allDigits[3], digitIndex: digitIndex(for: 3), tubeColor: tubeColor)
                    SeparatorView(separatorIndex: separatorIndex(for: 1), tubeColor: tubeColor, digitHeight: geo.size.height)

                    ValveDigitView(digit: allDigits[4], digitIndex: digitIndex(for: 4), tubeColor: tubeColor)
                    ValveDigitView(digit: allDigits[5], digitIndex: digitIndex(for: 5), tubeColor: tubeColor)
                    SeparatorView(separatorIndex: separatorIndex(for: 2), tubeColor: tubeColor, digitHeight: geo.size.height)

                    ValveDigitView(digit: allDigits[6], digitIndex: digitIndex(for: 6), tubeColor: tubeColor)
                    ValveDigitView(digit: allDigits[7], digitIndex: digitIndex(for: 7), tubeColor: tubeColor)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}
