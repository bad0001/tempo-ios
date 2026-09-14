//
//  BreathingView.swift
//  Tempo
//
//  呼吸训练入口与呼吸模式选择。
//

import SwiftUI
import TempoCore

struct BreathingView: View {
    @AppStorage("preferredBreathingPatternId") private var preferredPatternId: String = "4-7-8"
    @State private var showPatternSheet = false
    @State private var pulse: Bool = false

    private var selectedPattern: BreathingPattern {
        BreathingPattern.allPresets.first(where: { $0.id == preferredPatternId }) ?? .fourSevenEight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 4) {
                        Text("专注")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .kerning(2)
                            .foregroundStyle(TempoTheme.tertiaryText)
                        HStack(spacing: 4) {
                            Text("呼吸训练")
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(TempoTheme.primaryText)
                            Text("✨")
                                .font(.system(size: 22))
                        }
                    }
                    .padding(.top, 12)

                    breathingOrb
                        .padding(.vertical, 8)

                    Button {
                        showPatternSheet = true
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Text(LocalizedStringKey(selectedPattern.displayName))
                                    .font(.system(size: 20, weight: .heavy))
                                    .foregroundStyle(TempoTheme.primaryText)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(TempoTheme.accent)
                            }
                            Text(LocalizedStringKey(selectedPattern.descriptionText))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TempoTheme.tertiaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .buttonStyle(.tempoPress)

                    NavigationLink {
                        BreathingSessionView(pattern: selectedPattern)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("开始训练")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Capsule().fill(TempoTheme.buttonGradient))
                        .shadow(color: TempoTheme.accent.opacity(0.35), radius: 16, x: 0, y: 10)
                    }
                    .buttonStyle(.tempoPress)

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .sheet(isPresented: $showPatternSheet) {
                BreathingPatternPicker(selectedId: $preferredPatternId)
            }
        }
    }

    private var breathingOrb: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "60A5FA").opacity(0.25), Color(hex: "34D399").opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 30)
                .frame(width: 280, height: 280)
                .scaleEffect(pulse ? 1.06 : 1.0)

            Circle()
                .stroke(Color(hex: "8B5CF6").opacity(0.18), lineWidth: 1)
                .frame(width: 250, height: 250)

            Circle()
                .fill(TempoTheme.orbGradient)
                .frame(width: 200, height: 200)
                .shadow(color: Color(hex: "60A5FA").opacity(0.45), radius: 24, x: 0, y: 12)
                .overlay(
                    Image(systemName: "wind")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white)
                )
                .scaleEffect(pulse ? 1.0 : 0.95)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct BreathingPatternPicker: View {
    @Binding var selectedId: String
    @Environment(\.dismiss) private var dismiss

    private func icon(for id: String) -> String {
        switch id {
        case "coherent": return "arrow.left.and.right"
        case "4-7-8": return "moon.stars.fill"
        case "box": return "square"
        case "resonant": return "waveform.path"
        case "wim-hof": return "snowflake"
        case "buteyko": return "lungs.fill"
        default: return "wind"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(BreathingPattern.allPresets) { pattern in
                        Button {
                            selectedId = pattern.id
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                SoftIconBubble(
                                    systemName: icon(for: pattern.id),
                                    color: TempoTheme.accent,
                                    size: 44
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(LocalizedStringKey(pattern.displayName))
                                            .font(.system(size: 16, weight: .heavy))
                                            .foregroundStyle(TempoTheme.primaryText)
                                        if pattern.isPro {
                                            Text("PRO")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.orange))
                                        }
                                    }
                                    Text(LocalizedStringKey(pattern.descriptionText))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(TempoTheme.tertiaryText)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if pattern.id == selectedId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(TempoTheme.accent)
                                }
                            }
                            .tempoCard(radius: 18, padding: 14)
                        }
                        .buttonStyle(.tempoPress)
                    }
                }
                .padding(20)
            }
            .background(TempoTheme.background)
            .navigationTitle("选择呼吸模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
