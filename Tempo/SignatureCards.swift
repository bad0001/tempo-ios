//
//  SignatureCards.swift
//  Tempo
//
//  差异化招牌入口卡 — 共振空间、节奏唤醒。
//

import SwiftUI

// MARK: - Resonant Space

struct ResonantSpaceCard: View {
    @State private var showHub = false

    var body: some View {
        Button {
            showHub = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "8B5CF6"), Color(hex: "EC4899")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("共振空间")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                        Text("Tempo 独占")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "8B5CF6").opacity(0.15)))
                    }
                    Text("关怀 · 冥想 · 呼吸邀请")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "8B5CF6"))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "EEF2FF"), Color(hex: "FCE7F3")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(hex: "8B5CF6").opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.tempoPress)
        .sheet(isPresented: $showHub) {
            ResonantSpaceHubView()
        }
    }
}

// MARK: - Tempo Wakeup (节奏唤醒)

struct TempoWakeupCard: View {
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "F59E0B"), Color(hex: "F97316")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("节奏唤醒")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                        Text("Tempo 独占")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: "F97316"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "F97316").opacity(0.15)))
                    }
                    Text("依据 HRV 在最浅睡眠点叫醒你")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(hex: "F97316").opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 4)
            )
        }
        .buttonStyle(.tempoPress)
        .sheet(isPresented: $showSettings) {
            WakeupSettingsView()
        }
    }
}
