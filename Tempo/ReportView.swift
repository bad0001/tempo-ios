//
//  ReportView.swift
//  Tempo
//

import SwiftUI
import SwiftData
import TempoCore

/// ReportView @Query cutoff:本周 / 本月报告,最多回看 1 年
private let reportCutoff: Date = Date.now.addingTimeInterval(-365 * 86400)

struct ReportView: View {
    let title: String
    let timeRange: TimeInterval

    @Query(filter: #Predicate<StressEntry> { $0.timestamp > reportCutoff },
           sort: \StressEntry.timestamp, order: .reverse) private var entries: [StressEntry]

    private var rangedEntries: [StressEntry] {
        let cutoff = Date().addingTimeInterval(-timeRange)
        return entries.filter { $0.timestamp >= cutoff }
    }

    private var avgScore: Int {
        let values = rangedEntries.map(\.scoreValue)
        return values.isEmpty ? 0 : values.reduce(0, +) / values.count
    }

    private var maxScore: Int {
        rangedEntries.map(\.scoreValue).max() ?? 0
    }

    private var minScore: Int {
        rangedEntries.map(\.scoreValue).min() ?? 0
    }

    private var avgHRV: Int? {
        let hrvs = rangedEntries.compactMap(\.hrv)
        guard !hrvs.isEmpty else { return nil }
        return Int(hrvs.reduce(0, +) / Double(hrvs.count))
    }

    private var avgBPM: Int {
        let bpms = rangedEntries.map(\.bpm)
        return bpms.isEmpty ? 0 : Int(bpms.reduce(0, +) / Double(bpms.count))
    }

    private var levelDistribution: [(level: StressLevel, count: Int)] {
        let groups = Dictionary(grouping: rangedEntries) { $0.level }
        return StressLevel.allCases.map { level in
            (level, groups[level]?.count ?? 0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("基于过去 \(Int(timeRange / 86400)) 天的 \(rangedEntries.count) 条记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    StatBlock(title: "平均压力", value: "\(avgScore)", color: .pink)
                    StatBlock(title: "最高", value: "\(maxScore)", color: .red)
                    StatBlock(title: "最低", value: "\(minScore)", color: .mint)
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    StatBlock(title: "平均心率", value: "\(avgBPM)", subtitle: "BPM", color: .pink)
                    if let hrv = avgHRV {
                        StatBlock(title: "平均 HRV", value: "\(hrv)", subtitle: "ms", color: .blue)
                    } else {
                        StatBlock(title: "平均 HRV", value: "—", subtitle: nil, color: .secondary)
                    }
                }
                .padding(.horizontal)

                if !rangedEntries.isEmpty {
                    LevelDistributionCard(distribution: levelDistribution)
                        .padding(.horizontal)
                }

                ReportInsight(
                    avgScore: avgScore,
                    count: rangedEntries.count,
                    entries: rangedEntries,
                    periodName: title
                )
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(LocalizedStringKey(title)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatBlock: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title.weight(.light))
                    .foregroundStyle(color)
                    .monospacedDigit()
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LevelDistributionCard: View {
    let distribution: [(level: StressLevel, count: Int)]

    private var total: Int {
        distribution.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("等级分布")
                .font(.subheadline.weight(.medium))

            ForEach(distribution, id: \.level) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: item.level))
                        .frame(width: 10, height: 10)
                    Text(LocalizedStringKey(item.level.tempoDisplayName))
                        .font(.callout)
                    Spacer()
                    Text("\(item.count) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(percentage(item.count))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(color(for: item.level))
                        .frame(width: 50, alignment: .trailing)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func percentage(_ count: Int) -> String {
        guard total > 0 else { return "0%" }
        let p = Int(Double(count) / Double(total) * 100)
        return "\(p)%"
    }

    private func color(for level: StressLevel) -> Color {
        switch level {
        case .calm: .mint
        case .relaxed: .green
        case .mild: .yellow
        case .high: .orange
        case .extreme: .red
        }
    }
}

struct ReportInsight: View {
    let avgScore: Int
    let count: Int
    let entries: [StressEntry]
    let periodName: String

    @State private var aiInsight: String?
    @State private var isGenerating = false

    private var fallbackInsight: String {
        if count == 0 {
            return "暂无数据。试试在 Apple Watch 上启动监测,Tempo 会自动记录你的压力分。"
        }
        if avgScore < 35 {
            return "本期压力很低,继续保持。状态适合处理深度专注的工作。"
        }
        if avgScore < 55 {
            return "本期处于轻松状态。可以考虑挑战一些有难度的任务。"
        }
        if avgScore < 70 {
            return "本期有轻度压力。建议每天做 1-2 次 4-7-8 呼吸,睡前进行盒式呼吸。"
        }
        return "本期压力较高。建议增加休息频率,试试共振呼吸或冥想,必要时减少日程安排。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(
                        colors: [.pink, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .font(.callout)
                Text("AI 洞察")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(aiInsight ?? fallbackInsight)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: count) {
            await loadInsight()
        }
    }

    private func loadInsight() async {
        guard count > 0, aiInsight == nil else { return }
        isGenerating = true
        defer { isGenerating = false }
        let summary = AICoachContextBuilder.summary(from: entries)
        let cleanPeriod = periodName.replacingOccurrences(of: "报告", with: "")
        if let insight = await AICoachService.shared.generateReportInsight(
            period: cleanPeriod,
            contextSummary: summary
        ), !insight.isEmpty {
            aiInsight = insight
        }
    }
}

#Preview {
    NavigationStack {
        ReportView(title: "本周报告", timeRange: 7 * 86400)
    }
}
