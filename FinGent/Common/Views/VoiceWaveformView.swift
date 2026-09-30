// Common/Views/VoiceWaveformView.swift

import SwiftUI

/// Animated audio waveform indicator showing real-time microphone activity and speech status.
struct VoiceWaveformView: View {
    let isListening: Bool
    var latestWord: String = ""
    var onToggleLanguage: (() -> Void)? = nil
    var languageFlag: String = "🇮🇩"

    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            // Animated waveform bars
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    WaveBar(index: index, isListening: isListening, phase: phase)
                }
            }
            .frame(width: 28, height: 18)

            // Status or latest word
            if isListening {
                if !latestWord.isEmpty {
                    HStack(spacing: 4) {
                        Text("Mendengarkan:")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.6))

                        Text("“\(latestWord)”")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "0066FF"))
                            .lineLimit(1)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    Text("Mendengarkan... Silakan bicara")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
            } else {
                Text("Mikrofon dijeda")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.5))
            }

            Spacer()

            if let onToggleLanguage = onToggleLanguage {
                Button(action: onToggleLanguage) {
                    HStack(spacing: 3) {
                        Text(languageFlag)
                            .font(.system(size: 12))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.4))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ganti bahasa mikrofon")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular.interactive(), in: .capsule)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }
}

private struct WaveBar: View {
    let index: Int
    let isListening: Bool
    let phase: CGFloat

    private var height: CGFloat {
        guard isListening else { return 3 }
        let pattern: [CGFloat] = [6, 14, 18, 11, 7]
        let base = pattern[index % pattern.count]
        let wave = sin(phase * .pi + Double(index) * 0.7)
        return max(3, base + CGFloat(wave) * 4)
    }

    var body: some View {
        Capsule()
            .fill(isListening ? Color(hex: "0066FF") : Color.black.opacity(0.25))
            .frame(width: 2.5, height: height)
            .animation(.easeInOut(duration: 0.25).repeatForever(autoreverses: true), value: phase)
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
