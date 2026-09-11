// Features/Chat/View/ThreeDotsAnimation.swift

import SwiftUI

struct ThreeDotsAnimation: View {

    @State private var phase = 0
    var color: Color = .black

    private let sizes: [[CGFloat]] = [
        [6, 2, 2],  // State 1
        [4, 6, 2],  // State 2
        [2, 2, 6]   // State 3
    ]

    var body: some View {

        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(
                            width: sizes[phase][index],
                            height: sizes[phase][index]
                        )
                }
                .frame(width: 6, height: 6)
            }
        }
        .frame(height: 6)
        .animation(
            .linear(duration: 0.11),
            value: phase
        )
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(160))
                phase = (phase + 1) % sizes.count
            }
        }
    }
}
