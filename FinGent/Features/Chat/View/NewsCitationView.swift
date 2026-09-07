// Features/Chat/View/NewsCitationView.swift

import SwiftUI

struct NewsCitationView: View {
    let citation: NewsCitation
    var onSelect: (URL) -> Void = { _ in }

    var body: some View {
        Button {
            onSelect(citation.url)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Source Icon with tint
                Image(systemName: citation.source.iconSystemName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(citation.source.accentColor)
                    .frame(width: 26, height: 26)
                    .background(citation.source.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))

                // Metadata: Publisher, Time, Title
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(citation.source.displayName)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))

                        Text(citation.publishedAt.timeAgoDisplay())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(citation.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                // Open Link Indicator
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 2)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date TimeAgo Helper

extension Date {
    func timeAgoDisplay() -> String {
        let secondsAgo = Int(Date().timeIntervalSince(self))
        if secondsAgo < 60 {
            return "Baru saja"
        } else if secondsAgo < 3600 {
            let minutes = secondsAgo / 60
            return "\(minutes)m yang lalu"
        } else if secondsAgo < 86400 {
            let hours = secondsAgo / 3600
            return "\(hours)h yang lalu"
        } else {
            let days = secondsAgo / 86400
            return "\(days)d yang lalu"
        }
    }
}

// MARK: - NewsSourceType Color Extension

extension NewsSourceType {
    var accentColor: Color {
        let scanner = Scanner(string: accentHex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
