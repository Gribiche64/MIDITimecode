import SwiftUI

struct SeparatorView: View {
    let separatorIndex: Int
    let tubeColor: TubeColor
    let digitHeight: CGFloat

    private var colorSet: (primary: Color, secondary: Color, glow: Color) {
        tubeColor.colors(for: separatorIndex)
    }

    var body: some View {
        let dotDiameter = max(digitHeight * 0.035, 3)
        let gap = digitHeight * 0.12

        VStack(spacing: gap) {
            Circle()
                .fill(colorSet.primary)
                .frame(width: dotDiameter, height: dotDiameter)
                .shadow(color: colorSet.glow, radius: dotDiameter * 0.5)
            Circle()
                .fill(colorSet.primary)
                .frame(width: dotDiameter, height: dotDiameter)
                .shadow(color: colorSet.glow, radius: dotDiameter * 0.5)
        }
        .frame(width: digitHeight * 0.12)
    }
}
