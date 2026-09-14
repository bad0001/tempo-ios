//
//  HistoryComponents.swift
//  Tempo
//
//  Chart and sharing components for HistoryView.
//

import SwiftUI
import Charts
import TempoCore

struct StressBarBucket: Identifiable, Hashable {
    let id: String
    let label: String
    let date: Date
    let average: Int
}

struct StressHeatmapCell: Identifiable, Hashable {
    let id: String
    let label: String
    let average: Int
    let count: Int
}

struct StressLevelDistributionItem: Identifiable, Hashable {
    let level: StressLevel
    let count: Int
    let percent: Double

    var id: StressLevel { level }
}

struct StressProfessionalSummary: Hashable {
    let average: Int
    let peak: Int
    let low: Int
    let highStressMinutes: Int
    let stressLoad: Int
    let dataConfidence: Int
    let hrvDeviationPercent: Int?
    let latestHRV: Double?
    let latestRestingHeartRate: Double?
}

struct VitalsStressRelationship: Hashable {
    let hrvCorrelation: Double?
    let rhrCorrelation: Double?
    let hrvSampleDays: Int
    let rhrSampleDays: Int

    static let empty = VitalsStressRelationship(
        hrvCorrelation: nil,
        rhrCorrelation: nil,
        hrvSampleDays: 0,
        rhrSampleDays: 0
    )
}

struct StressEpisode: Identifiable, Hashable {
    let id: String
    let start: Date
    let end: Date
    let peak: Int
    let average: Int
    let durationMinutes: Int

    var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.locale = TempoAppLanguage.currentLocale
        formatter.dateFormat = "M/d HH:mm"
        let sameDay = Calendar.current.isDate(start, inSameDayAs: end)
        if sameDay {
            let endFormatter = DateFormatter()
            endFormatter.locale = TempoAppLanguage.currentLocale
            endFormatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: start))-\(endFormatter.string(from: end))"
        }
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}

struct StressEpisodeDetailContext {
    let episode: StressEpisode
    let windowPoints: [StressDataPoint]
    let beforeAverage: Int?
    let afterAverage: Int?
    let dailyHRV: Double?
    let hrvBaseline: Double?
    let dailyRestingHeartRate: Double?
    let sleepHours: Double?
    let deepSleepHours: Double?
    let remSleepHours: Double?
    let activityLabel: String
    let sourceLabel: String
    let dataConfidence: Int
}

struct StressRhythmCell: Identifiable, Hashable {
    let weekdayIndex: Int
    let timeBandIndex: Int
    let weekdayLabel: String
    let timeLabel: String
    let average: Int?
    let count: Int

    var id: String { "\(weekdayIndex).\(timeBandIndex)" }
}

struct HistorySourceCard: View {
    let label: String
    let detail: String
    let isMock: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: isMock ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isMock ? TempoTheme.warning : TempoTheme.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(label))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.secondaryText)
                Text(LocalizedStringKey(detail))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

struct StressLoadOverviewCard: View {
    let summary: StressProfessionalSummary
    let sourceLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("本期摘要")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Text(LocalizedStringKey(sourceLabel))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TempoTheme.secondaryText)
            }

            HStack(spacing: 0) {
                summaryMetric(title: "平均压力", value: "\(summary.average)", unit: "/100", color: color(for: summary.average))
                Divider().frame(height: 42)
                summaryMetric(title: "高压时长", value: "\(summary.highStressMinutes)", unit: "分钟", color: TempoTheme.danger)
                Divider().frame(height: 42)
                summaryMetric(title: "可信度", value: "\(summary.dataConfidence)", unit: "%", color: summary.dataConfidence >= 70 ? TempoTheme.success : TempoTheme.warning)
            }

            HStack {
                Text("峰值 \(summary.peak)/100")
                Spacer()
                Text("压力负荷 \(summary.stressLoad)")
                Spacer()
                Text(summary.hrvDeviationPercent.map { "HRV \($0 > 0 ? "+" : "")\($0)%" } ?? "HRV —")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(TempoTheme.secondaryText)
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private func summaryMetric(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                Text(LocalizedStringKey(unit))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadColor: Color {
        switch summary.stressLoad {
        case ..<40: return TempoTheme.success
        case 40..<100: return TempoTheme.warning
        default: return TempoTheme.danger
        }
    }

    private var hrvDeviationText: String {
        guard let value = summary.hrvDeviationPercent else { return "—" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private var hrvDeviationColor: Color {
        guard let value = summary.hrvDeviationPercent else { return TempoTheme.tertiaryText }
        return value >= 0 ? TempoTheme.success : TempoTheme.danger
    }

    private var confidenceBadge: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("可信度")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            Text("\(summary.dataConfidence)%")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(summary.dataConfidence >= 70 ? TempoTheme.success : TempoTheme.warning)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "F8FAFC"))
        )
    }

    private func insightTile(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                Text(LocalizedStringKey(unit))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "F8FAFC"))
        )
    }
}

struct ProfessionalStressChartCard: View {
    let points: [StressDataPoint]
    let buckets: [StressBarBucket]
    let rangeLabel: String
    @State private var selectedDate: Date?

    private var selectedPoint: StressDataPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("压力曲线")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Text(rangeLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TempoTheme.secondaryText)
            }

            if points.isEmpty && buckets.isEmpty {
                emptyText("暂无压力趋势")
            } else {
                selectedReadout

                Chart {
                    RectangleMark(
                        xStart: .value("低压起点", points.first?.date ?? Date()),
                        xEnd: .value("低压终点", points.last?.date ?? Date()),
                        yStart: .value("低压", 0),
                        yEnd: .value("轻压", 50)
                    )
                    .foregroundStyle(TempoTheme.success.opacity(0.07))

                    RectangleMark(
                        xStart: .value("中压起点", points.first?.date ?? Date()),
                        xEnd: .value("中压终点", points.last?.date ?? Date()),
                        yStart: .value("中压", 50),
                        yEnd: .value("高压", 70)
                    )
                    .foregroundStyle(TempoTheme.warning.opacity(0.08))

                    RectangleMark(
                        xStart: .value("高压起点", points.first?.date ?? Date()),
                        xEnd: .value("高压终点", points.last?.date ?? Date()),
                        yStart: .value("高压", 70),
                        yEnd: .value("极高", 100)
                    )
                    .foregroundStyle(TempoTheme.danger.opacity(0.07))

                    ForEach(points) { point in
                        LineMark(
                            x: .value("时间", point.date),
                            y: .value("压力", point.score)
                        )
                        .foregroundStyle(TempoTheme.primaryText.opacity(0.82))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.3, lineCap: .round))
                    }

                    ForEach(buckets) { bucket in
                        BarMark(
                            x: .value("聚合", bucket.date),
                            y: .value("平均压力", bucket.average),
                            width: .ratio(0.34)
                        )
                        .foregroundStyle(color(for: bucket.average).opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    RuleMark(y: .value("高压线", 70))
                        .foregroundStyle(TempoTheme.danger.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("高压 70")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(TempoTheme.danger)
                        }
                    RuleMark(y: .value("中压线", 50))
                        .foregroundStyle(TempoTheme.warning.opacity(0.38))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))

                    if let selectedPoint {
                        RuleMark(x: .value("选中时间", selectedPoint.date))
                            .foregroundStyle(TempoTheme.accent.opacity(0.38))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(
                            x: .value("选中时间", selectedPoint.date),
                            y: .value("选中压力", selectedPoint.score)
                        )
                        .foregroundStyle(color(for: selectedPoint.score))
                        .symbolSize(56)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.12))
                        AxisValueLabel()
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 70, 100]) { _ in
                        AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.14))
                        AxisValueLabel()
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                .frame(height: 230)
                .chartXSelection(value: $selectedDate)
                .accessibilityLabel("可交互压力趋势图")
                .accessibilityHint("在图表上左右拖动查看具体时间和压力值")
            }

            Text("绿色：恢复  ·  橙色：压力  ·  红色：高压")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TempoTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tempoCard(radius: 22, padding: 16)
        .onChange(of: rangeLabel) { _, _ in selectedDate = nil }
    }

    private var selectedReadout: some View {
        HStack(spacing: 10) {
            if let selectedPoint {
                Circle()
                    .fill(color(for: selectedPoint.score))
                    .frame(width: 9, height: 9)
                Text(selectionTimeText(selectedPoint.date))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(TempoTheme.secondaryText)
                Spacer(minLength: 0)
                Text("\(selectedPoint.score)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(color(for: selectedPoint.score))
                Text("/100")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(TempoTheme.tertiaryText)
            } else {
                Text("拖动图表查看具体时点")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hex: "F8FAFC"))
        )
    }

    private func selectionTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = TempoAppLanguage.currentLocale
        formatter.dateFormat = rangeLabel == "24 小时" ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }
}

struct VitalsBaselineCard: View {
    let hrvPoints: [HealthMetricHistoryPoint]
    let rhrPoints: [HealthMetricHistoryPoint]
    let hrvBaseline: Double?

    private var rhrBaseline: Double? {
        guard !rhrPoints.isEmpty else { return nil }
        return rhrPoints.map(\.value).reduce(0, +) / Double(rhrPoints.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "heart.text.square.fill",
                color: Color.pink,
                title: "生命体征基线",
                subtitle: "HRV 与静息心率分开量尺,避免双轴误读"
            )

            if hrvPoints.isEmpty && rhrPoints.isEmpty {
                emptyText("暂无 HRV 或静息心率历史。授权 HealthKit 后会自动出现。")
            } else {
                metricPanel(
                    title: "心率变异性 HRV",
                    unit: "ms",
                    color: TempoTheme.accent,
                    points: hrvPoints,
                    baseline: hrvBaseline
                )

                Divider().overlay(TempoTheme.tertiaryText.opacity(0.12))

                metricPanel(
                    title: "静息心率 RHR",
                    unit: "bpm",
                    color: Color.pink,
                    points: rhrPoints,
                    baseline: rhrBaseline
                )
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    @ViewBuilder
    private func metricPanel(
        title: String,
        unit: String,
        color: Color,
        points: [HealthMetricHistoryPoint],
        baseline: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(TempoTheme.secondaryText)
                    Text("独立量尺 · 虚线为个人基线")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer(minLength: 0)
                Text(latestValue(points))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                Text(LocalizedStringKey(unit))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(TempoTheme.tertiaryText)
                if let delta = deltaPercent(points: points, baseline: baseline) {
                    Text(delta > 0 ? "+\(delta)%" : "\(delta)%")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.11)))
                }
            }

            if points.isEmpty {
                emptyText("暂无\(title)数据")
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    }
                    if let baseline {
                        RuleMark(y: .value("个人基线", baseline))
                            .foregroundStyle(color.opacity(0.34))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    if let latest = points.last {
                        PointMark(
                            x: .value("最近日期", latest.date),
                            y: .value("最近值", latest.value)
                        )
                        .foregroundStyle(color)
                        .symbolSize(44)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.10))
                        AxisValueLabel()
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.12))
                        AxisValueLabel()
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                .frame(height: 126)
            }
        }
    }

    private func latestValue(_ points: [HealthMetricHistoryPoint]) -> String {
        guard let value = points.last?.value else { return "—" }
        return String(format: "%.0f", value)
    }

    private func deltaPercent(points: [HealthMetricHistoryPoint], baseline: Double?) -> Int? {
        guard let latest = points.last?.value, let baseline, baseline > 0 else { return nil }
        return Int(((latest - baseline) / baseline * 100).rounded())
    }
}

struct VitalsStressRelationshipCard: View {
    let relationship: VitalsStressRelationship

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "point.3.connected.trianglepath.dotted",
                color: Color(hex: "0E7490"),
                title: "压力与生命体征关联",
                subtitle: "按天配对 · r 越接近 ±1,方向一致性越强"
            )

            relationshipTile(
                title: "HRV × 压力",
                subtitle: "常见方向:压力上升时 HRV 下降",
                symbol: "waveform.path.ecg",
                color: TempoTheme.accent,
                correlation: relationship.hrvCorrelation,
                sampleDays: relationship.hrvSampleDays,
                expectedSign: -1
            )

            relationshipTile(
                title: "静息心率 × 压力",
                subtitle: "常见方向:压力上升时静息心率升高",
                symbol: "heart.fill",
                color: Color.pink,
                correlation: relationship.rhrCorrelation,
                sampleDays: relationship.rhrSampleDays,
                expectedSign: 1
            )

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                Text("统计关联不代表因果；至少 3 个同日样本才计算。睡眠、运动、饮酒和测量时段都可能影响结果。")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private func relationshipTile(
        title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        correlation: Double?,
        sampleDays: Int,
        expectedSign: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                SoftIconBubble(systemName: symbol, color: color, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(correlation.map { String(format: "r = %.2f", $0) } ?? "r = —")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(correlation.map { relationshipColor($0, expectedSign: expectedSign) } ?? TempoTheme.tertiaryText)
                    Text("(sampleDays) 个同日样本")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }

            correlationScale(correlation: correlation, color: color)

            Text(LocalizedStringKey(relationshipText(correlation, expectedSign: expectedSign)))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "F8FAFC"))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title),\(correlation.map { String(format: "相关系数 %.2f", $0) } ?? "样本不足"),\(sampleDays) 个同日样本")
    }

    private func correlationScale(correlation: Double?, color: Color) -> some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width, 1)
            let normalized = correlation.map { min(1, max(-1, $0)) } ?? 0
            let x = trackWidth * CGFloat((normalized + 1) / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [TempoTheme.accent.opacity(0.22), Color.white, Color.pink.opacity(0.22)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)

                Rectangle()
                    .fill(TempoTheme.tertiaryText.opacity(0.36))
                    .frame(width: 1, height: 14)
                    .offset(x: trackWidth / 2)

                if correlation != nil {
                    Circle()
                        .fill(color)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: color.opacity(0.24), radius: 4, y: 2)
                        .offset(x: min(max(0, x - 6.5), trackWidth - 13))
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                Text("−1")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .offset(y: 10)
            }
            .overlay(alignment: .bottom) {
                Text("0")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .offset(y: 10)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("+1")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .offset(y: 10)
            }
        }
        .frame(height: 22)
    }

    private func relationshipText(_ correlation: Double?, expectedSign: Double) -> String {
        guard let correlation else { return "还需至少 3 个同日样本,暂不判断方向。" }
        let magnitude = abs(correlation)
        let strength: String
        switch magnitude {
        case ..<0.25: strength = "目前关联较弱"
        case ..<0.55: strength = "存在中等方向一致性"
        default: strength = "方向一致性较强"
        }
        guard magnitude >= 0.25 else { return strength + "。" }
        let matchesExpected = correlation * expectedSign > 0
        return matchesExpected
            ? strength + ",并且符合当前常见方向。"
            : strength + ",但方向与当前常见模式不同,建议继续积累数据。"
    }

    private func relationshipColor(_ correlation: Double, expectedSign: Double) -> Color {
        guard abs(correlation) >= 0.25 else { return TempoTheme.tertiaryText }
        return correlation * expectedSign > 0 ? TempoTheme.success : TempoTheme.warning
    }
}

struct StressRhythmHeatmapCard: View {
    let cells: [StressRhythmCell]

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    private var weekdayLabels: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var rowLabels: [String] {
        ["0-4", "4-8", "8-12", "12-16", "16-20", "20-24"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "calendar.day.timeline.leading",
                color: TempoTheme.success,
                title: "压力节律热力图",
                subtitle: "看清一周里哪些时段最容易堆压"
            )

            if cells.allSatisfy({ $0.average == nil }) {
                emptyText("暂无足够节律数据")
            } else {
                HStack(spacing: 5) {
                    Text("")
                        .frame(width: 42)
                    ForEach(weekdayLabels, id: \.self) { label in
                        Text(LocalizedStringKey(label))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(TempoTheme.tertiaryText)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Array(rowLabels.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 5) {
                        Text(LocalizedStringKey(label))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(TempoTheme.tertiaryText)
                            .frame(width: 42, alignment: .leading)
                        LazyVGrid(columns: columns, spacing: 5) {
                            ForEach(cells.filter { $0.timeBandIndex == index }) { cell in
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(cell.average.map { color(for: $0).opacity(heatmapOpacity(for: $0)) } ?? TempoTheme.tertiaryText.opacity(0.08))
                                    .frame(height: 24)
                                    .overlay {
                                        if let avg = cell.average, cell.count >= 2 {
                                            Text("\(avg)")
                                                .font(.system(size: 8, weight: .black, design: .rounded))
                                                .foregroundStyle(avg >= 62 ? .white : TempoTheme.secondaryText)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }
}

struct HighStressEpisodesCard: View {
    let episodes: [StressEpisode]
    let onSelect: (StressEpisode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "waveform.path.ecg.rectangle.fill",
                color: TempoTheme.danger,
                title: "高压片段",
                subtitle: "连续超过 70 的时间段,比单点峰值更重要"
            )

            if episodes.isEmpty {
                emptyText("这段时间没有明显连续高压片段")
            } else {
                VStack(spacing: 10) {
                    ForEach(episodes.prefix(4)) { episode in
                        Button {
                            onSelect(episode)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(spacing: 3) {
                                    Text("\(episode.peak)")
                                        .font(.system(size: 18, weight: .black, design: .rounded))
                                        .foregroundStyle(color(for: episode.peak))
                                    Text("峰值")
                                        .font(.system(size: 8, weight: .heavy))
                                        .foregroundStyle(TempoTheme.tertiaryText)
                                }
                                .frame(width: 42)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(episode.timeRangeText)
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(TempoTheme.primaryText)
                                    Text("持续 \(episode.durationMinutes) 分钟 · 平均 \(episode.average)/100")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(TempoTheme.secondaryText)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(TempoTheme.tertiaryText)
                            }
                            .contentShape(Rectangle())
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(hex: "F8FAFC"))
                            )
                        }
                        .buttonStyle(.tempoPress(.light))
                        .accessibilityLabel("\(episode.timeRangeText),峰值 \(episode.peak),持续 \(episode.durationMinutes) 分钟")
                        .accessibilityHint("打开高压片段详情")
                    }
                }
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }
}

struct StressEpisodeDetailView: View {
    let context: StressEpisodeDetailContext

    private var recoveryDelta: Int? {
        guard let before = context.beforeAverage, let after = context.afterAverage else { return nil }
        return after - before
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                eventWindowCard
                beforeAfterCard
                dailyContextCard
                interpretationCard
                disclaimer
                Spacer(minLength: 34)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .background(TempoTheme.background.ignoresSafeArea())
        .navigationTitle("高压片段")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.episode.timeRangeText)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("一次连续高压过程")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                Text("可信度 \(context.dataConfidence)%")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }

            HStack(spacing: 8) {
                heroMetric(title: "峰值", value: "\(context.episode.peak)", unit: "/100")
                heroMetric(title: "平均", value: "\(context.episode.average)", unit: "/100")
                heroMetric(title: "持续", value: "\(context.episode.durationMinutes)", unit: "min")
            }

            Label("\(context.sourceLabel) · \(context.activityLabel)", systemImage: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "EF4444"), Color(hex: "F97316")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: TempoTheme.danger.opacity(0.20), radius: 18, y: 9)
        )
    }

    private func heroMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                Text(LocalizedStringKey(unit))
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.72)
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.13)))
    }

    private var eventWindowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "waveform.path.ecg",
                color: TempoTheme.danger,
                title: "事件窗口",
                subtitle: "片段前后各约 90 分钟,红色区域为连续高压"
            )

            if context.windowPoints.isEmpty {
                emptyText("暂无可绘制的事件窗口数据")
            } else {
                Chart {
                    RectangleMark(
                        xStart: .value("开始", context.episode.start),
                        xEnd: .value("结束", context.episode.end),
                        yStart: .value("下限", 0),
                        yEnd: .value("上限", 100)
                    )
                    .foregroundStyle(TempoTheme.danger.opacity(0.09))

                    ForEach(context.windowPoints) { point in
                        LineMark(
                            x: .value("时间", point.date),
                            y: .value("压力", point.score)
                        )
                        .foregroundStyle(color(for: point.score))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    }

                    RuleMark(y: .value("高压阈值", 70))
                        .foregroundStyle(TempoTheme.danger.opacity(0.52))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("高压 70")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(TempoTheme.danger)
                        }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.10))
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 70, 100]) { _ in
                        AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.12))
                        AxisValueLabel()
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                .frame(height: 210)
                .accessibilityLabel("高压片段前后压力曲线")
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private var beforeAfterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "arrow.left.and.right.circle.fill",
                color: TempoTheme.warning,
                title: "前后变化",
                subtitle: "各取片段前后最多 60 分钟的可用记录"
            )

            HStack(spacing: 10) {
                comparisonMetric(title: "之前", value: context.beforeAverage, color: TempoTheme.warning)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TempoTheme.tertiaryText)
                comparisonMetric(title: "之后", value: context.afterAverage, color: recoveryColor)
            }

            Text(LocalizedStringKey(recoveryText))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private func comparisonMetric(title: String, value: Int?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            Text(value.map { "\($0)" } ?? "—")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(value == nil ? TempoTheme.tertiaryText : color)
            Text("平均压力")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(hex: "F8FAFC")))
    }

    private var recoveryColor: Color {
        guard let recoveryDelta else { return TempoTheme.tertiaryText }
        return recoveryDelta <= -8 ? TempoTheme.success : recoveryDelta >= 8 ? TempoTheme.danger : TempoTheme.warning
    }

    private var recoveryText: String {
        guard let delta = recoveryDelta else { return "前后数据不足,暂时只展示片段本身。" }
        if delta <= -8 { return "片段后平均压力下降 \(abs(delta)) 分,已经出现明显回落。" }
        if delta >= 8 { return "片段后平均压力仍上升 \(delta) 分,高压可能还在延续。" }
        return "片段前后变化 \(delta >= 0 ? "+" : "")\(delta) 分,目前基本持平。"
    }

    private var dailyContextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "square.grid.2x2.fill",
                color: TempoTheme.accent,
                title: "同日身体背景",
                subtitle: "这些指标用于补充上下文,不单独解释压力原因"
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
                spacing: 9
            ) {
                contextMetric(
                    title: "HRV",
                    value: context.dailyHRV.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "ms",
                    detail: hrvDetail,
                    color: TempoTheme.accent
                )
                contextMetric(
                    title: "静息心率",
                    value: context.dailyRestingHeartRate.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "bpm",
                    detail: "当天 HealthKit 日值",
                    color: Color.pink
                )
                contextMetric(
                    title: "昨夜睡眠",
                    value: context.sleepHours.map { String(format: "%.1f", $0) } ?? "—",
                    unit: "h",
                    detail: sleepDetail,
                    color: Color.indigo
                )
                contextMetric(
                    title: "活动状态",
                    value: context.activityLabel,
                    unit: "",
                    detail: "片段内记录的主要状态",
                    color: TempoTheme.success
                )
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private func contextMetric(title: String, value: String, unit: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: value.count > 6 ? 15 : 22, weight: .black, design: .rounded))
                    .foregroundStyle(value == "—" ? TempoTheme.tertiaryText : color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                if !unit.isEmpty {
                    Text(LocalizedStringKey(unit))
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
            Text(LocalizedStringKey(detail))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(TempoTheme.tertiaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "F8FAFC")))
    }

    private var hrvDetail: String {
        guard let value = context.dailyHRV, let baseline = context.hrvBaseline, baseline > 0 else {
            return "当天 HealthKit 日值"
        }
        let delta = Int(((value - baseline) / baseline * 100).rounded())
        return "较个人基线 \(delta >= 0 ? "+" : "")\(delta)%"
    }

    private var sleepDetail: String {
        guard let deep = context.deepSleepHours, let rem = context.remSleepHours else {
            return "暂无睡眠分期"
        }
        return String(format: "深睡 %.1fh · REM %.1fh", deep, rem)
    }

    private var interpretationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(
                icon: "text.magnifyingglass",
                color: TempoTheme.success,
                title: "这段记录说明什么",
                subtitle: "只总结已观测到的变化"
            )

            ForEach(interpretations, id: \.self) { text in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(TempoTheme.success)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    Text(LocalizedStringKey(text))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private var interpretations: [String] {
        var result = [
            "压力连续高于 70 约 \(context.episode.durationMinutes) 分钟,峰值为 \(context.episode.peak)。",
            recoveryText,
        ]
        if let hrv = context.dailyHRV, let baseline = context.hrvBaseline, baseline > 0 {
            let delta = Int(((hrv - baseline) / baseline * 100).rounded())
            result.append("当天 HRV 较个人基线 \(delta >= 0 ? "+" : "")\(delta)%,这是背景信号,不是单独原因。")
        }
        if let sleep = context.sleepHours {
            result.append(String(format: "前一晚记录睡眠 %.1f 小时,可与后续相似片段一起比较。", sleep))
        }
        return result
    }

    private var disclaimer: some View {
        Label(
            "Tempo 展示的是健康趋势和统计上下文,不用于疾病诊断。单次高压片段也可能受到运动、咖啡因或测量密度影响。",
            systemImage: "shield.lefthalf.filled"
        )
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(TempoTheme.tertiaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }
}

struct StressBarChartCard: View {
    let buckets: [StressBarBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "chart.bar.fill",
                color: TempoTheme.warning,
                title: "压力柱状图",
                subtitle: "看压力在哪些时间段堆高"
            )

            if buckets.isEmpty {
                emptyText("暂无可聚合的压力记录")
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("时间", bucket.label),
                        y: .value("压力", bucket.average)
                    )
                    .foregroundStyle(color(for: bucket.average).gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel()
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { _ in
                        AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.14))
                        AxisValueLabel()
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                .frame(height: 148)
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }
}

struct StressHeatmapCard: View {
    let cells: [StressHeatmapCell]
    let rangeLabel: String

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "square.grid.3x3.fill",
                color: TempoTheme.accent,
                title: "压力热力图",
                subtitle: "\(rangeLabel) 的高低压密度"
            )

            if cells.isEmpty {
                emptyText("暂无热力图数据")
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(cells) { cell in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(color(for: cell.average).opacity(heatmapOpacity(for: cell.average)))
                                .frame(height: 30)
                                .overlay(
                                    Text("\(cell.average)")
                                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                                        .foregroundStyle(cell.average >= 62 ? .white : TempoTheme.secondaryText)
                                        .minimumScaleFactor(0.75)
                                )
                            Text(LocalizedStringKey(cell.label))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(TempoTheme.tertiaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                    }
                }
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }
}

struct VitalsTrendCard: View {
    let hrvPoints: [HealthMetricHistoryPoint]
    let rhrPoints: [HealthMetricHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "heart.text.square.fill",
                color: Color.pink,
                title: "HRV / 静息心率",
                subtitle: "恢复和压力背景线"
            )

            if hrvPoints.isEmpty && rhrPoints.isEmpty {
                emptyText("暂无 HRV 或静息心率历史。授权 HealthKit 后会自动出现。")
            } else {
                Chart {
                    ForEach(hrvPoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("HRV", point.value),
                            series: .value("指标", "HRV")
                        )
                        .foregroundStyle(TempoTheme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    }
                    ForEach(rhrPoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("静息心率", point.value),
                            series: .value("指标", "静息心率")
                        )
                        .foregroundStyle(Color.pink)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [4, 4]))
                    }
                }
                .chartForegroundStyleScale([
                    "HRV": TempoTheme.accent,
                    "静息心率": Color.pink,
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 158)

                HStack(spacing: 10) {
                    trendMiniStat(title: "HRV", value: latestValue(hrvPoints), unit: "ms", color: TempoTheme.accent)
                    trendMiniStat(title: "静息心率", value: latestValue(rhrPoints), unit: "bpm", color: Color.pink)
                }
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private func latestValue(_ points: [HealthMetricHistoryPoint]) -> String {
        guard let value = points.last?.value else { return "—" }
        return String(format: "%.0f", value)
    }

    private func trendMiniStat(title: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(TempoTheme.primaryText)
            Text(LocalizedStringKey(unit))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "F8FAFC"))
        )
    }
}

struct HistoryLevelDistributionCard: View {
    let distribution: [StressLevelDistributionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "circle.hexagongrid.fill",
                color: TempoTheme.success,
                title: "压力水平分布",
                subtitle: "平静、放松、轻度、高压占比"
            )

            if distribution.allSatisfy({ $0.count == 0 }) {
                emptyText("暂无等级分布")
            } else {
                VStack(spacing: 9) {
                    ForEach(distribution) { item in
                        HStack(spacing: 10) {
                            Text(LocalizedStringKey(item.level.tempoDisplayName))
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(TempoTheme.secondaryText)
                                .frame(width: 40, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(TempoTheme.tertiaryText.opacity(0.10))
                                    Capsule()
                                        .fill(color(for: item.level))
                                        .frame(width: max(6, proxy.size.width * item.percent))
                                }
                            }
                            .frame(height: 10)
                            Text("\(Int(item.percent * 100))%")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(color(for: item.level))
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }
}

struct TrendSummaryShareCard: View {
    let friends: [Friend]
    @Binding var selectedFriendID: String?
    let rangeLabel: String
    let summary: StressProfessionalSummary
    let dominantLevel: String
    let hrvText: String
    let distribution: [StressLevelDistributionItem]
    let episodeCount: Int
    let canShare: Bool
    let isSharing: Bool
    let statusText: String?
    let onSend: () -> Void
    let onOpenSettings: () -> Void
    @State private var previewAppeared = false

    private var selectedFriend: Friend? {
        guard let selectedFriendID else { return friends.first }
        return friends.first { $0.id == selectedFriendID } ?? friends.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "heart.text.square.fill",
                color: Color.pink,
                title: "分享给密友",
                subtitle: "只发送这段摘要,不发送逐点记录"
            )

            trendPreview

            if friends.isEmpty {
                Button(action: onOpenSettings) {
                    Label("先添加密友", systemImage: "person.badge.plus.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.tempoPress)
            } else {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(friends) { friend in
                            Button(friend.displayName) {
                                selectedFriendID = friend.id
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(selectedFriend?.displayName ?? "选择密友")
                                .font(.system(size: 13, weight: .heavy))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(TempoTheme.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: "F8FAFC"))
                        )
                    }
                    .buttonStyle(.tempoPress)

                    Button(action: onSend) {
                        Group {
                            if isSharing {
                                ProgressView().tint(.white)
                            } else {
                                Text("确认发送")
                                    .font(.system(size: 13, weight: .heavy))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canShare ? Color.pink : TempoTheme.tertiaryText)
                        )
                    }
                    .buttonStyle(.tempoPress)
                    .disabled(!canShare || isSharing)
                }
            }

            if let statusText {
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusText.contains("失败") ? TempoTheme.danger : TempoTheme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private var trendPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TEMPO STRESS REPORT")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .kerning(1.1)
                        .foregroundStyle(Color.pink)
                    Text("\(rangeLabel)压力摘要")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                }
                Spacer()
                Text("可信度 \(summary.dataConfidence)%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(summary.dataConfidence >= 70 ? TempoTheme.success : TempoTheme.warning)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.8)))
            }

            HStack(spacing: 8) {
                previewMetric("平均", "\(summary.average)", "/100")
                previewMetric("峰值", "\(summary.peak)", "/100")
                previewMetric("高压", "\(summary.highStressMinutes)", "min")
                previewMetric("负荷", "\(summary.stressLoad)", "")
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(TempoTheme.tertiaryText.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [TempoTheme.success, TempoTheme.warning, TempoTheme.danger],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: previewAppeared ? width * CGFloat(min(max(summary.average, 0), 100)) / 100 : 0)
                    Capsule()
                        .fill(TempoTheme.primaryText)
                        .frame(width: 3, height: 14)
                        .offset(x: max(0, width * CGFloat(min(max(summary.peak, 0), 100)) / 100 - 1.5))
                }
            }
            .frame(height: 9)

            distributionBar

            HStack(alignment: .top, spacing: 8) {
                Label(dominantLevel, systemImage: "waveform.path.ecg")
                Spacer(minLength: 8)
                Text("高压片段 \(episodeCount)")
                Spacer(minLength: 8)
                Text(hrvText)
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(TempoTheme.secondaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.08), TempoTheme.accent.opacity(0.05), .white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.pink.opacity(0.12), lineWidth: 0.8)
                )
        )
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                previewAppeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rangeLabel)压力摘要,平均 \(summary.average),峰值 \(summary.peak),高压 \(summary.highStressMinutes) 分钟,压力负荷 \(summary.stressLoad)")
    }

    private var distributionBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                let visibleItems = distribution.filter { $0.percent > 0 }
                let spacing = CGFloat(max(visibleItems.count - 1, 0)) * 2
                let availableWidth = max(proxy.size.width - spacing, 1)

                HStack(spacing: 2) {
                    ForEach(visibleItems) { item in
                        Capsule()
                            .fill(color(for: item.level))
                            .frame(width: max(3, availableWidth * CGFloat(item.percent)))
                    }
                }
            }
            .frame(height: 7)
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                ForEach(distribution.filter { $0.percent > 0.01 }) { item in
                    HStack(spacing: 3) {
                        Circle().fill(color(for: item.level)).frame(width: 5, height: 5)
                        Text("\(item.level.tempoDisplayName) \(Int((item.percent * 100).rounded()))%")
                    }
                }
            }
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(TempoTheme.tertiaryText)
        }
    }

    private func previewMetric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                if !unit.isEmpty {
                    Text(LocalizedStringKey(unit))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.72)))
    }
}

private func cardHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        SoftIconBubble(systemName: icon, color: color, size: 38)
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Text(LocalizedStringKey(subtitle))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TempoTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
    }
}

private func emptyText(_ text: String) -> some View {
    Text(LocalizedStringKey(text))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(TempoTheme.tertiaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
}

private func color(for score: Int) -> Color {
    switch StressLevel(score: score) {
    case .calm: return TempoTheme.success
    case .relaxed: return Color(hex: "22C55E")
    case .mild: return TempoTheme.warning
    case .high: return Color(hex: "F97316")
    case .extreme: return TempoTheme.danger
    }
}

private func heatmapOpacity(for score: Int) -> Double {
    max(0.18, min(1.0, Double(score) / 92.0))
}

private func color(for level: StressLevel) -> Color {
    switch level {
    case .calm: return TempoTheme.success
    case .relaxed: return Color(hex: "22C55E")
    case .mild: return TempoTheme.warning
    case .high: return Color(hex: "F97316")
    case .extreme: return TempoTheme.danger
    }
}
