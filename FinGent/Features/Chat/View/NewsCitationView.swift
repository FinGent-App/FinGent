// Features/Chat/View/NewsCitationView.swift

import SwiftUI

struct NewsCitationView: View {
    let citation: NewsCitation
    var onSelect: (URL) -> Void = { _ in }

    private var hasValidWebURL: Bool {
        let str = citation.url.absoluteString
        return str.hasPrefix("http://") || str.hasPrefix("https://")
    }

    var body: some View {
        Button {
            if hasValidWebURL {
                onSelect(citation.url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Source Icon with tint
                Image(systemName: citation.source.iconSystemName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(citation.source.accentColor)
                    .frame(width: 26, height: 26)
                    .background(citation.source.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))

                // Metadata: Publisher/Badge, Time, Title
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(citation.badgeLabel ?? citation.source.displayName)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(citation.source.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(citation.source.accentColor.opacity(0.15), in: Capsule())

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.black.opacity(0.3))

                        Text(citation.publishedAt.timeAgoDisplay())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.5))
                    }

                    Text(citation.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                // Open Link Indicator
                if hasValidWebURL {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.4))
                        .padding(.top, 2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(citation.source.accentColor.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasValidWebURL)
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
