// Common/Views/CircleBorderWaveView.swift

import SwiftUI

/// Animated fluid border wave rings for the liquid circle.
/// Radiates energetic, organic ripples around the perimeter of the circle when the user is speaking.
struct CircleBorderWaveView: View {
    let diameter: CGFloat
    let isListening: Bool
    var audioLevel: CGFloat = 0.0

    @State private var phase1: CGFloat = 0.0
    @State private var phase2: CGFloat = 0.0
    @State private var phase3: CGFloat = 0.0
    @State private var rotation: Double = 0.0

    private let gradientColors = [
        Color(hex: "0066FF"),
        Color(hex: "38BDF8"),
        Color(hex: "818CF8"),
        Color(hex: "C084FC"),
        Color(hex: "0066FF")
    ]

    var body: some View {
        ZStack(alignment: .center) {
            if isListening {
                // Wave Ripple 3 (Outer aura)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: gradientColors,
                            center: .center,
                            angle: .degrees(rotation + 120)
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(1.0 + (phase3 * 0.42) + (audioLevel * 0.30), anchor: .center)
                    .opacity(Double(1.0 - phase3) * 0.45)
                    .blur(radius: 2)

                // Wave Ripple 2 (Mid pulse)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: gradientColors,
                            center: .center,
                            angle: .degrees(rotation + 60)
                        ),
                        lineWidth: 1.8
                    )
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(1.0 + (phase2 * 0.28) + (audioLevel * 0.22), anchor: .center)
                    .opacity(Double(1.0 - phase2) * 0.65)
                    .blur(radius: 1)

                // Wave Ripple 1 (Immediate border echo)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: gradientColors,
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 2.2
                    )
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(1.0 + (phase1 * 0.16) + (audioLevel * 0.14), anchor: .center)
                    .opacity(Double(1.0 - phase1) * 0.85)

                // Perimeter Border Glow (Hugs the exact circle edge)
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: gradientColors,
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 2.5 + (audioLevel * 2.5)
                    )
                    .frame(width: diameter, height: diameter)
                    .shadow(
                        color: Color(hex: "0066FF").opacity(0.55 + Double(audioLevel * 0.4)),
                        radius: 8 + (audioLevel * 10),
                        x: 0,
                        y: 0
                    )
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .onAppear {
            startAnimations()
        }
        .onChange(of: isListening) { _, listening in
            if listening {
                startAnimations()
            }
        }
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
            rotation = 360.0
        }

        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
            phase1 = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                phase2 = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                phase3 = 1.0
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
