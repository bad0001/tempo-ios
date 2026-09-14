//
//  OnboardingView.swift
//  Tempo
//
//  4 屏引导:欢迎 → 三大独占 → HealthKit 授权 → 免责 + 目标。
//  替代单纯的 DisclaimerView,提升首日留存。
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    @AppStorage("primaryGoal") private var primaryGoal: String = "calm"
    @State private var currentPage: Int = 0
    @State private var hkAuthRequesting = false
    @State private var hkAuthGranted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()

            // 装饰光晕
            BackgroundAura()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // 顶部进度 + Skip
                HStack {
                    PageDots(current: currentPage, total: 4)
                    Spacer()
                    if currentPage < 3 {
                        Button {
                            withAnimation { currentPage = 3 }
                        } label: {
                            Text("跳过")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(TempoTheme.tertiaryText)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // Pages
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    healthKitPage.tag(2)
                    finalPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // 底部按钮
                bottomButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Page 1: 欢迎

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(TempoTheme.accent.opacity(0.18))
                    .frame(width: 220, height: 220)
                    .blur(radius: 30)
                Circle()
                    .stroke(TempoTheme.accent.opacity(0.20), lineWidth: 1)
                    .frame(width: 200, height: 200)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TempoTheme.accent, TempoTheme.accentLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .shadow(color: TempoTheme.accent.opacity(0.4), radius: 20, y: 10)
                Image(systemName: "waveform.path")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 12) {
                Text("你好,我是 Tempo")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("你的身体节奏伙伴")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
            }

            Text("Tempo 用 Apple Watch 监测你的心率、HRV 和压力,在合适的时机推荐节奏匹配的音乐、引导呼吸 — 让身体保持顺畅韵律。")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 2: 三大独占

    private var featuresPage: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Tempo 独占三件事")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("其他压力 App 都做不了")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
            }

            VStack(spacing: 14) {
                FeatureRow(
                    icon: "music.note",
                    title: "节奏匹配音乐",
                    subtitle: "实时心率 → 自动推荐 BPM 适合的歌",
                    gradient: [TempoTheme.accent, TempoTheme.accentLight]
                )
                FeatureRow(
                    icon: "person.2.wave.2.fill",
                    title: "密友共振关怀",
                    subtitle: "互看压力摘要,一键发心跳和鼓励",
                    gradient: [Color(hex: "8B5CF6"), Color(hex: "EC4899")]
                )
                FeatureRow(
                    icon: "sunrise.fill",
                    title: "节奏唤醒",
                    subtitle: "依据 HRV 在浅睡时段叫醒你",
                    gradient: [Color(hex: "F59E0B"), Color(hex: "F97316")]
                )
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 3: HealthKit 授权

    private var healthKitPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.18))
                    .frame(width: 160, height: 160)
                    .blur(radius: 24)
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.pink, Color(hex: "F97316")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 10) {
                Text("授权读取健康数据")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("原始健康记录留在设备,联网摘要由你控制")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TempoTheme.success)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(["心率与 HRV", "睡眠时长 & 阶段", "步数 / 训练 / 卡路里", "呼吸频率 & SpO2", "正念 Session(写入)"], id: \.self) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(TempoTheme.success)
                        Text(LocalizedStringKey(item))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TempoTheme.primaryText)
                        Spacer()
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 16, y: 4)
            )
            .padding(.horizontal, 24)

            if hkAuthGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(TempoTheme.success)
                    Text("已授权,可以继续")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.success)
                }
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 4: 免责 + 目标

    private var finalPage: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text("最后一步")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("选个目标,Tempo 帮你达成")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
            }

            VStack(spacing: 10) {
                GoalChip(id: "calm", label: "保持平静", icon: "leaf.fill", color: TempoTheme.success, selected: $primaryGoal)
                GoalChip(id: "destress", label: "缓解压力", icon: "wind", color: TempoTheme.accent, selected: $primaryGoal)
                GoalChip(id: "hrv", label: "提升 HRV", icon: "waveform.path.ecg", color: Color(hex: "F97316"), selected: $primaryGoal)
                GoalChip(id: "sleep", label: "改善睡眠", icon: "moon.fill", color: Color(hex: "8B5CF6"), selected: $primaryGoal)
            }
            .padding(.horizontal, 24)

            // 医疗免责
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.tertiaryText)
                Text("Tempo 不是医疗设备,不能替代专业医疗建议。如有不适请咨询医生。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {
        Button {
            handleNext()
        } label: {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(buttonTitle))
                    .font(.system(size: 17, weight: .bold))
                if currentPage < 3 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Capsule().fill(TempoTheme.buttonGradient))
            .shadow(color: TempoTheme.accent.opacity(0.3), radius: 14, y: 8)
        }
        .buttonStyle(.tempoPress)
        .disabled(hkAuthRequesting)
    }

    private var buttonTitle: String {
        switch currentPage {
        case 0: return "好,开始"
        case 1: return "我喜欢,下一步"
        case 2: return hkAuthGranted ? "已授权,继续" : (hkAuthRequesting ? "授权中..." : "授权 HealthKit")
        case 3: return "完成,开始体验"
        default: return "下一步"
        }
    }

    private func handleNext() {
        switch currentPage {
        case 0, 1:
            withAnimation { currentPage += 1 }
        case 2:
            if hkAuthGranted {
                withAnimation { currentPage = 3 }
            } else {
                Task { await requestHK() }
            }
        case 3:
            onboardingCompleted = true
            disclaimerAccepted = true
            dismiss()
        default: break
        }
    }

    private func requestHK() async {
        hkAuthRequesting = true
        let granted = (try? await HealthKitService.shared.requestAuthorization()) ?? false
        hkAuthGranted = granted
        hkAuthRequesting = false
        if granted {
            withAnimation { currentPage = 3 }
        }
    }
}

// MARK: - Pieces

private struct PageDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? TempoTheme.accent : TempoTheme.tertiaryText.opacity(0.25))
                    .frame(width: i == current ? 22 : 6, height: 6)
                    .animation(.easeInOut, value: current)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        )
    }
}

private struct GoalChip: View {
    let id: String
    let label: String
    let icon: String
    let color: Color
    @Binding var selected: String

    var body: some View {
        Button {
            selected = id
        } label: {
            HStack(spacing: 12) {
                SoftIconBubble(systemName: icon, color: color, size: 38)
                Text(LocalizedStringKey(label))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                if selected == id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(color)
                } else {
                    Circle()
                        .stroke(TempoTheme.tertiaryText.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selected == id ? color : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
            )
        }
        .buttonStyle(.tempoPress)
    }
}

#Preview {
    OnboardingView()
}
