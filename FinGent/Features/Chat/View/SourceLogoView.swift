// Features/Chat/View/SourceLogoView.swift

import SwiftUI
import UIKit

struct SourceLogoView: View {
    let source: NewsSourceType
    var size: CGFloat = 22

    var body: some View {
        if let uiImage = UIImage(named: source.assetImageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            // Fallback branded circular badge with initial
            ZStack {
                Circle()
                    .fill(source.accentColor)

                Text(source.shortBadge)
                    .font(.system(size: size * (source.shortBadge.count > 2 ? 0.32 : 0.44), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}
