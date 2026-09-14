//
//  PreferencesView.swift
//  Tempo
//
//  监测、提醒和音乐偏好。
//

import SwiftUI
import SwiftData
import TempoCore

struct PreferencesView: View {
    @Binding var continuousMonitoring: Bool
    @Binding var smartRemindersEnabled: Bool
    @AppStorage("stress.notificationThreshold") private var stressNotificationThreshold: Double = 80
    @AppStorage("user.hasAppleMusic") private var hasAppleMusic = false
    @AppStorage("user.musicTriggerThreshold") private var musicTriggerThreshold: Double = 70
    @AppStorage("algo.circadianEnabled") private var circadianEnabled: Bool = true
    @AppStorage("algo.usePhasicHRV") private var usePhasicHRV: Bool = true
    @AppStorage("algo.usePersonalModel") private var usePersonalModel: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var preferenceMessage: String?
    @State private var personalModel = PersonalStressModel.shared
    @State private var trainingMessage: String?
    @State private var isTraining: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsSheetHeader(
                        icon: "gearshape.fill",
                        color: TempoTheme.accent,
                        title: "偏好设置",
                        subtitle: "监测、提醒和音乐"
                    )

                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            icon: "applewatch.watchface",
                            iconColor: TempoTheme.accent,
                            title: "持续监测心率",
                            subtitle: continuousMonitoring ? "Apple Watch 后台采集" : "打开 Watch App 时采集",
                            isOn: $continuousMonitoring
                        )
                        .onChange(of: continuousMonitoring) { _, newValue in
                            Task { await PhoneSessionManager.shared.sendContinuousMonitoring(newValue) }
                        }

                        Divider().padding(.leading, 68)

                        SettingsToggleRow(
                            icon: "bell.badge.fill",
                            iconColor: TempoTheme.warning,
                            title: "智能压力提醒",
                            subtitle: smartRemindersEnabled ? "高压时提醒休息" : "不发送本地提醒",
                            isOn: Binding(
                                get: { smartRemindersEnabled },
                                set: { newValue in
                                    Task { await setSmartReminders(newValue) }
                                }
                            )
                        )
                    }
                    .settingsPanel()

                    if let preferenceMessage {
                        SettingsFootnoteCard(
                            icon: preferenceMessage.contains("开启") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            color: preferenceMessage.contains("开启") ? TempoTheme.success : TempoTheme.warning,
                            text: preferenceMessage
                        )
                    }

                    SettingsSliderCard(
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        iconColor: TempoTheme.warning,
                        title: "高压提醒阈值",
                        valueText: "≥ \(Int(stressNotificationThreshold))",
                        value: $stressNotificationThreshold,
                        range: 70...95,
                        step: 5
                    )

                    // 算法偏好(v2 个性化算法 toggle)
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            icon: "sun.haze.fill",
                            iconColor: Color.orange,
                            title: "智能时段修正",
                            subtitle: circadianEnabled ? "按 circadian 节律平衡晨昏分数" : "已关闭,使用绝对值",
                            isOn: $circadianEnabled
                        )

                        Divider().padding(.leading, 68)

                        SettingsToggleRow(
                            icon: "waveform.path",
                            iconColor: Color.purple,
                            title: "Phasic HRV 急性偏移",
                            subtitle: usePhasicHRV ? "捕捉 1h 内 HRV 急性变化" : "不计入急性偏移",
                            isOn: $usePhasicHRV
                        )
                    }
                    .settingsPanel()

                    SettingsFootnoteCard(
                        icon: "function",
                        color: TempoTheme.accent,
                        text: "算法 v\(AlgorithmVersion.current) · 28 天滑动 baseline · 节律 + Phasic 修正。这些 toggle 只影响算法,关闭后回退老逻辑。"
                    )

                    // Per-user ML 个人模型卡
                    personalModelCard


                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            icon: "music.note.list",
                            iconColor: TempoTheme.accent,
                            title: "Apple Music",
                            subtitle: hasAppleMusic ? "首页展开音乐卡" : "使用内置音景",
                            isOn: $hasAppleMusic
                        )

                        Divider().padding(.leading, 68)

                        SettingsInlineSliderRow(
                            icon: "waveform.path",
                            iconColor: Color.pink,
                            title: "音乐触发",
                            valueText: "压力 ≥ \(Int(musicTriggerThreshold))",
                            value: $musicTriggerThreshold,
                            range: 50...90,
                            step: 5
                        )
                    }
                    .settingsPanel()

                    VStack(spacing: 0) {
                        NavigationLink {
                            ReportView(title: "本周报告", timeRange: 7 * 86400)
                        } label: {
                            SettingsNavigationRow(
                                icon: "calendar.badge.clock",
                                iconColor: TempoTheme.success,
                                title: "本周报告",
                                subtitle: "最近 7 天"
                            )
                        }
                        .buttonStyle(.tempoPress)

                        Divider().padding(.leading, 68)

                        NavigationLink {
                            ReportView(title: "本月报告", timeRange: 30 * 86400)
                        } label: {
                            SettingsNavigationRow(
                                icon: "calendar",
                                iconColor: TempoTheme.accent,
                                title: "本月报告",
                                subtitle: "最近 30 天"
                            )
                        }
                        .buttonStyle(.tempoPress)
                    }
                    .settingsPanel()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("偏好设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var personalModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SoftIconBubble(systemName: "brain.fill", color: Color.purple, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("个人压力模型")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(personalModel.isTrained
                        ? "样本 \(personalModel.sampleCount) · 验证 RMSE \(String(format: "%.1f", personalModel.valRMSE))"
                        : "尚未训练 — 在「记录感受」时设置「身体感受」滑块攒数据")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(personalModel.isConfident ? TempoTheme.success : TempoTheme.tertiaryText)
                }
                Spacer()
                if personalModel.isTrained {
                    Toggle("", isOn: $usePersonalModel)
                        .labelsHidden()
                        .tint(Color.purple)
                }
            }

            if let message = trainingMessage {
                Text(LocalizedStringKey(message))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(message.contains("失败") || message.contains("样本不足") ? TempoTheme.danger : TempoTheme.success)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await trainModel() }
                } label: {
                    HStack(spacing: 6) {
                        if isTraining {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11, weight: .heavy))
                        }
                        Text(LocalizedStringKey(personalModel.isTrained ? "重新训练" : "立即训练"))
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.purple))
                }
                .buttonStyle(.tempoPress)
                .disabled(isTraining)

                if personalModel.isTrained {
                    Button {
                        personalModel.reset()
                        trainingMessage = "已清除模型"
                    } label: {
                        Text("清除模型")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(TempoTheme.danger)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().stroke(TempoTheme.danger, lineWidth: 1.5))
                    }
                    .buttonStyle(.tempoPress)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        )
    }

    @MainActor
    private func trainModel() async {
        isTraining = true
        defer { isTraining = false }
        // 让 UI 短暂显示 loading
        try? await Task.sleep(for: .milliseconds(200))
        let result = personalModel.train(context: modelContext)
        trainingMessage = result.message
    }

    @MainActor
    private func setSmartReminders(_ enabled: Bool) async {
        preferenceMessage = nil
        if enabled {
            let granted = await NotificationManager.shared.requestAuthorization()
            smartRemindersEnabled = granted
            preferenceMessage = granted ? "智能压力提醒已开启。" : "系统通知权限未开启,暂时无法发送压力提醒。"
        } else {
            smartRemindersEnabled = false
            NotificationManager.shared.cancelHighStressAlerts()
            preferenceMessage = "智能压力提醒已关闭。"
        }
    }
}
