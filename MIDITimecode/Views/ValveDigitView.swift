import SwiftUI

struct ValveDigitView: View {
    let digit: String
    let digitIndex: Int
    let tubeColor: TubeColor

    private var colorSet: (primary: Color, secondary: Color, glow: Color) {
        tubeColor.colors(for: digitIndex)
    }

    var body: some View {
        GeometryReader { geo in
            let fontSize = geo.size.height * 0.65

            ZStack {
                // Tube body
                RoundedRectangle(cornerRadius: geo.size.width * 0.12)
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
                        RoundedRectangle(cornerRadius: geo.size.width * 0.12)
                            .stroke(Color(white: 0.25), lineWidth: 1)
                    )

                // Glow bloom behind the digit
                Text(digit)
                    .font(.system(size: fontSize, weight: .light, design: .monospaced))
                    .foregroundStyle(colorSet.glow)
                    .blur(radius: fontSize * 0.2)

                // Secondary halo
                Text(digit)
                    .font(.system(size: fontSize, weight: .light, design: .monospaced))
                    .foregroundStyle(colorSet.secondary)
                    .blur(radius: fontSize * 0.06)

                // Primary digit
                Text(digit)
                    .font(.system(size: fontSize, weight: .light, design: .monospaced))
                    .foregroundStyle(colorSet.primary)
                    .shadow(color: colorSet.glow, radius: fontSize * 0.12)
            }
        }
        .aspectRatio(0.62, contentMode: .fit)
    }
}
