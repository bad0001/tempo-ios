//
//  WakeupSettingsView.swift
//  Tempo
//
//  节奏唤醒设置 UI(替代 ComingSoonSheet).
//

import SwiftUI

struct WakeupSettingsView: View {
    @State private var service = WakeupService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    enableCard
                    if service.enabled {
                        timeCard
                        windowCard
                        previewCard
                    }
                    disclaimerCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        Task {
                            await service.reschedule()
                            dismiss()
                        }
                    }
                    .font(.system(size: 14, weight: .heavy))
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
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
                    .frame(width: 56, height: 56)
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("节奏唤醒")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("依据 HRV 调整唤醒文案,温柔起床")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var enableCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用节奏唤醒")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("会安排两条本地通知")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
            Toggle("", isOn: $service.enabled)
                .labelsHidden()
                .tint(Color(hex: "F97316"))
                .onChange(of: service.enabled) { _, _ in
                    Task { await service.reschedule() }
                }
        }
        .tempoCard(radius: 18, padding: 18)
    }

    private var timeCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("闹钟时间")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Text(service.formattedTime)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "F97316"))
                    .monospacedDigit()
            }

            DatePicker(
                "",
                selection: Binding(
                    get: { service.alarmDate },
                    set: {
                        service.alarmDate = $0
                        Task { await service.reschedule() }
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxHeight: 160)
        }
        .tempoCard(radius: 18, padding: 18)
    }

    private var windowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("唤醒窗口")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Text("\(service.windowMinutes) 分钟")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(hex: "F97316"))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60], id: \.self) { mins in
                    let selected = service.windowMinutes == mins
                    Button {
                        service.windowMinutes = mins
                        Task { await service.reschedule() }
                    } label: {
                        Text("\(mins) 分")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(selected ? .white : Color(hex: "F97316"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(selected ? Color(hex: "F97316") : Color(hex: "F97316").opacity(0.12))
                            )
                    }
                    .buttonStyle(.tempoPress)
                }
            }

            Text("Tempo 会在闹钟前约 \(service.windowMinutes / 2) 分钟先发一条温柔预热,主闹钟时再发一条。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tempoCard(radius: 18, padding: 18)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通知预览")
                .font(.system(size: 13, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)

            VStack(spacing: 10) {
                NotificationPreviewRow(time: service.earlyTimeFormatted, title: "晨曦在等你 🌅", message: "依据昨晚 HRV 自适应文案")
                NotificationPreviewRow(time: service.formattedTime, title: "节奏唤醒 ⏰", message: "起床后做组 5-5 呼吸,开启顺畅一天。")
            }
        }
        .tempoCard(radius: 18, padding: 18)
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(TempoTheme.tertiaryText)
            Text("iOS 限制下,节奏唤醒采用本地通知 + HRV 自适应文案的方案。完整睡眠阶段感知需要 Apple Watch 后台,后续版本会接入。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TempoTheme.warningSoft.opacity(0.5))
        )
    }
}

private struct NotificationPreviewRow: View {
    let time: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: "F97316"))
                .monospacedDigit()
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TempoTheme.background)
        )
    }
}
