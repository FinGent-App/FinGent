// Features/Profile/View/ProfileView.swift

import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AppContainer.shared.makeProfileViewModel()
    @State private var isEditingName: Bool = false
    @State private var tempName: String = ""
    @State private var copiedPrompt: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "DFE4EE"), Color(hex: "D7DDE7")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        profileHeader
                        statsGrid
                        siriGuideSection
                        settingsSection
                        dangerZoneSection
                        appFooter
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Tutup") {
                        dismiss()
                    }
                    .foregroundStyle(Color.black.opacity(0.8))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        tempName = viewModel.userName
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .alert("Ubah Nama Investor", isPresented: $isEditingName) {
                TextField("Nama Anda", text: $tempName)
                Button("Simpan") {
                    if !tempName.trimmingCharacters(in: .whitespaces).isEmpty {
                        viewModel.userName = tempName.trimmingCharacters(in: .whitespaces)
                    }
                }
                Button("Batal", role: .cancel) {}
            }
            .alert("Reset Portofolio?", isPresented: $viewModel.isShowingResetAlert) {
                Button("Reset ke Default", role: .destructive) {
                    viewModel.resetToDefaultData()
                }
                Button("Batal", role: .cancel) {}
            } message: {
                Text("Semua data saham saat ini akan direset kembali ke default contoh (BBCA & TLKM).")
            }
            .onAppear {
                viewModel.load()
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan, Color.blue, Color(red: 0.0, green: 0.82, blue: 0.61)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.cyan.opacity(0.35), radius: 12, x: 0, y: 6)

                Text(avatarInitial)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(viewModel.userName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)

                    Button {
                        tempName = viewModel.userName
                        isEditingName = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.black.opacity(0.5))
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.82, blue: 0.61))
                        .frame(width: 6, height: 6)

                    Text("FinGent Verified Investor • Agent Active")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var avatarInitial: String {
        let first = viewModel.userName.first ?? "I"
        return String(first).uppercased()
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 12) {
            statCard(
                title: "Holdings",
                value: "\(viewModel.holdingCount) Saham",
                icon: "chart.pie.fill",
                accent: .cyan
            )

            statCard(
                title: "Portfolio Value",
                value: NumberFormatters.rupiah(viewModel.totalMarketValue),
                icon: "banknote.fill",
                accent: Color(red: 0.0, green: 0.82, blue: 0.61)
            )

            statCard(
                title: "Total Return",
                value: String(format: "%@%.1f%%", viewModel.totalPnL >= 0 ? "+" : "-", abs(viewModel.totalPnLPercent)),
                icon: "chart.line.uptrend.xyaxis",
                accent: viewModel.totalPnL >= 0 ? Color(red: 0.0, green: 0.82, blue: 0.61) : .red
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(accent)
                Spacer()
            }

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: - Siri Guide Section

    private var siriGuideSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.cyan)
                Text("Siri Voice & AppIntents")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)

                Spacer()

                Text("5 Perintah")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.cyan.opacity(0.12)))
            }

            Text("Ucapkan perintah ini ke Siri untuk mengontrol portofolio tanpa membuka aplikasi:")
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.65))

            VStack(spacing: 10) {
                ForEach(viewModel.siriGuides) { item in
                    siriPromptRow(item: item)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func siriPromptRow(item: ProfileViewModel.SiriVoiceGuide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.cyan)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.cyan.opacity(0.12)))

                Text(item.prompt)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)

                Spacer()

                Button {
                    UIPasteboard.general.string = item.prompt.replacingOccurrences(of: "\"", with: "")
                    copiedPrompt = item.prompt
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedPrompt = nil
                    }
                } label: {
                    Image(systemName: copiedPrompt == item.prompt ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(copiedPrompt == item.prompt ? Color(red: 0.0, green: 0.82, blue: 0.61) : Color.black.opacity(0.4))
                }
            }

            Text(item.description)
                .font(.system(size: 11))
                .foregroundStyle(Color.black.opacity(0.6))
                .padding(.leading, 32)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.45))
        )
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI & Intelligence System")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)

            VStack(spacing: 12) {
                settingRow(
                    icon: "brain.head.profile",
                    title: "Foundation Model",
                    subtitle: "Apple Intelligence / DeepSeek V3",
                    badge: "Online"
                )

                settingRow(
                    icon: "wrench.and.screwdriver.fill",
                    title: "Agentic Tool Calling",
                    subtitle: "16 Tools (IHSG, News, Valuation, Portfolio)",
                    badge: "16 Tools"
                )

                Toggle(isOn: $viewModel.isLiveSimulationEnabled) {
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 15))
                            .foregroundStyle(.cyan)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.cyan.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simulasi Harga Realtime")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.black)
                            Text("Update tick harga pasar secara otomatis")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.black.opacity(0.55))
                        }
                    }
                }
                .tint(Color(red: 0.0, green: 0.82, blue: 0.61))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private func settingRow(icon: String, title: String, subtitle: String, badge: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.cyan.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.black.opacity(0.55))
            }

            Spacer()

            Text(badge)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.06)))
                .foregroundStyle(Color(red: 0.0, green: 0.65, blue: 0.5))
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Management")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.7))

            Button {
                viewModel.isShowingResetAlert = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 16))
                    Text("Reset Portofolio ke Default (BBCA & TLKM)")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.red.opacity(0.9))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - App Footer

    private var appFooter: some View {
        VStack(spacing: 4) {
            Text("FinGent v2.0 • Intelligent Stock Agent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))
            Text("Clean MVVM • AppIntents • Siri Agentic AI")
                .font(.system(size: 10))
                .foregroundStyle(Color.black.opacity(0.35))
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Color Extension Helper

private extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
