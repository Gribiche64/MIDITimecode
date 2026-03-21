import SwiftUI

struct SeparatorView: View {
    let separatorIndex: Int
    let tubeColor: TubeColor

    private var colorSet: (primary: Color, secondary: Color, glow: Color) {
        tubeColor.colors(for: separatorIndex)
    }

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(colorSet.primary)
                .frame(width: 6, height: 6)
                .shadow(color: colorSet.glow, radius: 4)
            Circle()
                .fill(colorSet.primary)
                .frame(width: 6, height: 6)
                .shadow(color: colorSet.glow, radius: 4)
        }
        .frame(width: 16, height: 72)
    }
}
