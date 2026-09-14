//
//  HomeComponents.swift
//  Tempo
//
//  首页卡片与指标组件。
//

import Foundation
import SwiftUI
import TempoCore

struct GreetingHeader: View {
    @Environment(\.locale) private var locale

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter.string(from: Date())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<22: return "晚上好"
        default: return "夜深了"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayString)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kerning(1.2)
                    .foregroundStyle(TempoTheme.tertiaryText)
                Text(LocalizedStringKey(greeting))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
            }
            Spacer()
        }
    }
}

struct StressCommandCenter: View {
    let score: StressScore?
    let heartRate: Double
    let hrv: Double?
    let recovery: Recovery
    let strain: Strain

    @Environment(\.switchToTab) private var switchToTab
    private var stressColor: Color {
        score.map { TempoTheme.stressColor(for: $0.level) } ?? TempoTheme.tertiaryText
    }

    private var statusText: String {
        score?.level.tempoDisplayName
            ?? String(localized: "等待数据", locale: TempoAppLanguage.currentLocale)
    }

    private var guidanceText: String {
        guard let score else { return "佩戴 Apple Watch 后，压力变化会出现在这里。" }
        switch score.level {
        case .calm, .relaxed:
            return "状态平稳，适合处理需要专注的事情。"
        case .mild:
            return "状态有些起伏，先看看今天发生了什么。"
        case .high, .extreme:
            return "压力正在上行，给自己一点缓冲时间。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stressColor)
                    .frame(width: 9, height: 9)
                Text(LocalizedStringKey(statusText))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.secondaryText)
                Spacer()
                Text("当前压力")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }

            HStack(alignment: .center, spacing: 16) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(score.map { "\($0.value)" } ?? "—")
                        .font(.system(size: 88, weight: .black, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("/100")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .padding(.bottom, 11)
                }
                Spacer(minLength: 0)
                stressGauge
            }

            Text(LocalizedStringKey(guidanceText))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                statusMiniMetric("心率", value: heartRate > 0 ? "\(Int(heartRate))" : "—", unit: "bpm", color: Color.pink)
                statusMiniMetric("HRV", value: hrv.map { String(format: "%.0f", $0) } ?? "—", unit: "ms", color: TempoTheme.accent)
                statusMiniMetric("恢复", value: recovery.hasEnoughData ? "\(recovery.value)" : "—", unit: "%", color: TempoTheme.success)
                statusMiniMetric("负荷", value: strain.value > 0 ? String(format: "%.1f", strain.value) : "—", unit: "", color: TempoTheme.warning)
            }

            Button {
                performPrimaryAction()
            } label: {
                actionLabel(icon: primaryActionIcon, title: primaryActionTitle, tint: .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(TempoTheme.accent)
                    )
            }
            .buttonStyle(.tempoPress(.medium))
            .accessibilityLabel(Text(LocalizedStringKey(primaryActionTitle)))
            .accessibilityHint(Text(LocalizedStringKey(primaryActionHint)))
        }
        .tempoCard(radius: 24, padding: 22)
    }

    private var stressGauge: some View {
        ZStack {
            Circle()
                .stroke(stressColor.opacity(0.14), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(score?.value ?? 0) / 100)
                .stroke(stressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.55), value: score?.value)
            Image(systemName: orbIcon)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(stressColor)
        }
        .frame(width: 76, height: 76)
    }

    private var orbIcon: String {
        guard let score else { return "applewatch" }
        switch score.level {
        case .calm, .relaxed: return "figure.mind.and.body"
        case .mild: return "figure.cooldown"
        case .high, .extreme: return "wind"
        }
    }

    private var primaryActionTitle: String {
        score == nil ? "查看趋势" : "查看今天的变化"
    }

    private var primaryActionIcon: String {
        "chart.line.uptrend.xyaxis"
    }

    private var primaryActionHint: String {
        "打开趋势页查看压力变化"
    }

    private func performPrimaryAction() {
        switchToTab(.trends)
    }

    private func statusMiniMetric(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.09))
        )
    }

    private func actionLabel(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .heavy))
        }
        .foregroundStyle(tint)
    }
}

struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String
    let trendPercent: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SoftIconBubble(systemName: icon, color: iconColor, size: 38)
                Spacer()
                if let trendPercent {
                    TrendBadge(percent: trendPercent)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 12, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(TempoTheme.tertiaryText)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 22, padding: 18)
    }
}

struct DualRingsCard: View {
    let recovery: Recovery
    let strain: Strain

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                RingMetric(
                    title: "今日恢复",
                    displayValue: "\(recovery.value)",
                    suffix: "%",
                    progress: CGFloat(recovery.value) / 100,
                    color: TempoTheme.accent,
                    subtitle: recovery.level.tempoDisplayName
                )
                RingMetric(
                    title: "日内负荷",
                    displayValue: String(format: "%.1f", strain.value),
                    suffix: "/10",
                    progress: CGFloat(strain.value) / 10,
                    color: TempoTheme.warning,
                    subtitle: strain.level.tempoDisplayName
                )
            }
            RecoveryDetailsRow(recovery: recovery)
        }
    }
}

/// Recovery 的细节展开:深睡 / REM / 体温偏差 chip。
/// 没数据时不显示该栏,完全可视化「为什么 Recovery 是这个分」。
struct RecoveryDetailsRow: View {
    let recovery: Recovery

    private var chips: [DetailChip] {
        var result: [DetailChip] = []
        if let stages = recovery.sleepStages, stages.hasStageData {
            if stages.deep > 0 {
                result.append(DetailChip(
                    icon: "moon.zzz.fill",
                    color: Color(hex: "6366F1"),
                    label: "深睡",
                    value: String(format: "%.1f h", stages.deep)
                ))
            }
            if stages.rem > 0 {
                result.append(DetailChip(
                    icon: "moon.stars.fill",
                    color: Color(hex: "8B5CF6"),
                    label: "REM",
                    value: String(format: "%.1f h", stages.rem)
                ))
            }
        }
        if let z = recovery.wristTempZScore, abs(z) > 0.5 {
            let signStr = z > 0 ? "+" : ""
            result.append(DetailChip(
                icon: recovery.hasElevatedTemp ? "thermometer.high" : "thermometer.medium",
                color: recovery.hasElevatedTemp ? TempoTheme.warning : TempoTheme.success,
                label: "体温",
                value: "\(signStr)\(String(format: "%.1f", z))σ"
            ))
        }
        return result
    }

    var body: some View {
        if !chips.isEmpty {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    HStack(spacing: 6) {
                        Image(systemName: chip.icon)
                            .font(.system(size: 10, weight: .heavy))
                        Text(LocalizedStringKey(chip.label))
                            .font(.system(size: 10, weight: .heavy))
                            .kerning(0.3)
                        Text(chip.value)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(chip.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(chip.color.opacity(0.12)))
                }
                if recovery.hasElevatedTemp {
                    Text("可能正在生病 / 过劳")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TempoTheme.warning)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct DetailChip: Identifiable {
    let icon: String
    let color: Color
    let label: String
    let value: String
    var id: String { label }
}

struct RingMetric: View {
    let title: String
    let displayValue: String
    let suffix: String
    let progress: CGFloat
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.15), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0, min(1, progress)))
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.6), value: progress)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(displayValue)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(TempoTheme.primaryText)
                            .contentTransition(.numericText())
                        Text(suffix)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 22, padding: 16)
    }
}

struct StateHintCard: View {
    let score: StressScore?

    private var hint: String {
        guard let score else { return "请佩戴 Apple Watch 后查看建议。" }
        switch score.level {
        case .calm: return "你正处于平静状态,继续保持。"
        case .relaxed: return "状态放松,适合专注或冥想。"
        case .mild: return "轻度压力,试试 4-7-8 呼吸放松一下。"
        case .high: return "压力较高,建议休息片刻并进行盒式呼吸。"
        case .extreme: return "压力极高,请立刻停下手中事,做几次深呼吸。"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SoftIconBubble(systemName: "lightbulb.fill", color: TempoTheme.warning, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("小提示")
                    .font(.system(size: 12, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(TempoTheme.tertiaryText)
                Text(LocalizedStringKey(hint))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TempoTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .tempoCard(radius: 22, padding: 16)
    }
}
