import SwiftUI

struct ValveDigitView: View {
    let digit: String
    let digitIndex: Int
    let tubeColor: TubeColor

    private var colorSet: (primary: Color, secondary: Color, glow: Color) {
        tubeColor.colors(for: digitIndex)
    }

    var body: some View {
        ZStack {
            // Tube body
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.15),
                            Color(white: 0.08),
                            Color(white: 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(white: 0.25), lineWidth: 1)
                )

            // Glow bloom behind the digit
            Text(digit)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(colorSet.glow)
                .blur(radius: 12)

            // Secondary halo
            Text(digit)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(colorSet.secondary)
                .blur(radius: 4)

            // Primary digit
            Text(digit)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(colorSet.primary)
                .shadow(color: colorSet.glow, radius: 8)
        }
        .frame(width: 44, height: 72)
    }
}
