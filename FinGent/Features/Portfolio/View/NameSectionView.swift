// Features/Portfolio/View/NameSectionView.swift

import SwiftUI

struct NameSectionView: View {
    @Binding var nameText: String
    let onNameChanged: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nama Kamu")
                .font(.headline)
                .foregroundStyle(.white)

            inputField

            if !nameText.isEmpty {
                Text("Siri akan menyapa: \"Hey \(nameText)!\"")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .transition(.opacity)
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1) }
        }
        .animation(.easeInOut(duration: 0.2), value: !nameText.isEmpty)
    }

    private var inputField: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.cyan)

            TextField("Masukkan nama kamu", text: $nameText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .onChange(of: nameText) { _, newValue in
                    onNameChanged(newValue)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.08))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1) }
        }
    }
}
