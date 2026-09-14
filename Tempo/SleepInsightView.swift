//
//  SleepInsightView.swift
//  Tempo
//

import SwiftUI
import SwiftData
import Charts
import TempoCore

/// SleepInsightView @Query cutoff:30 天散点图 + buffer = 45d
private let sleepInsightCutoff: Date = Date.now.addingTimeInterval(-45 * 86400)

struct SleepInsightView: View {
    @Query(filter: #Predicate<StressEntry> { $0.timestamp > sleepInsightCutoff },
           sort: \StressEntry.timestamp, order: .reverse) private var entries: [StressEntry]
    @State private var sleepHistory: [DailySleepData] = []
    @State private var dataState: TempoLoadState = .idle

    private var lastNight: DailySleepData? {
        sleepHistory.last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TempoDataStateView(
                    state: dataState,
                    loadingTitle: "正在读取睡眠数据",
                    emptyTitle: "暂无睡眠数据",
                    emptyDetail: "Tempo 通过 Apple 健康读取睡眠分期；佩戴 Apple Watch 入睡几晚后会自动出现。",
                    cachedTitle: "正在显示上次睡眠结果",
                    cachedDetailOverride: "新的睡眠记录暂时读取失败，当前图表继续保留。",
                    onRetry: { Task { await loadData() } }
                )
                .padding(.horizontal)

                if !sleepHistory.isEmpty {
                    if let last = lastNight {
                        LastNightCard(data: last)
                            .padding(.horizontal)
                    }
                    CorrelationChartCard(sleepData: sleepHistory, stressEntries: entries)
                        .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("睡眠 × 压力")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadData() }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        dataState = .loading
        do {
            let loaded = try await HealthKitService.shared.fetchSleepHistory(daysBack: 30)
            sleepHistory = loaded
            dataState = loaded.isEmpty ? .empty : .ready(.now)
        } catch {
            if sleepHistory.isEmpty {
                dataState = TempoErrorCopy.representsNoData(error)
                    ? .empty
                    : .failed(TempoErrorCopy.message(for: error))
            } else {
                dataState = .cached(nil)
            }
        }
    }
}

struct EmptySleepView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 48))
                .foregroundStyle(.indigo.opacity(0.7))
            Text("暂无睡眠数据")
                .font(.headline)
            Text("Tempo 通过 Apple Health 读取你的睡眠分期。\n戴 Apple Watch 入睡几晚后会自动出现。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct LastNightCard: View {
    let data: DailySleepData

    private var hoursText: String {
        let h = Int(data.totalHours)
        let m = Int((data.totalHours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("昨晚")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(hoursText)
                    .font(.title.weight(.light))
                    .monospacedDigit()
                Text("总时长")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                let total = max(data.totalHours, 0.01)
                let deepW = CGFloat(data.deepHours / total) * geo.size.width
                let coreW = CGFloat(data.coreHours / total) * geo.size.width
                let remW = CGFloat(data.remHours / total) * geo.size.width

                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.indigo)
                        .frame(width: deepW)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: coreW)
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: remW)
                    Spacer(minLength: 0)
                }
                .frame(height: 10)
                .clipShape(Capsule())
            }
            .frame(height: 10)

            HStack(spacing: 14) {
                LegendItem(color: .indigo, label: "深睡", value: String(format: "%.1fh", data.deepHours))
                LegendItem(color: .blue, label: "浅睡", value: String(format: "%.1fh", data.coreHours))
                LegendItem(color: .cyan, label: "REM", value: String(format: "%.1fh", data.remHours))
                Spacer()
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(LocalizedStringKey(label))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
        }
    }
}

struct CorrelationChartCard: View {
    let sleepData: [DailySleepData]
    let stressEntries: [StressEntry]

    private var dataPoints: [SleepStressPoint] {
        let cal = Calendar.current
        return sleepData.compactMap { sleep -> SleepStressPoint? in
            let nextDay = sleep.date
            let dayEnd = cal.date(byAdding: .day, value: 1, to: nextDay) ?? nextDay
            let stressValues = stressEntries
                .filter { $0.timestamp >= nextDay && $0.timestamp < dayEnd }
                .map(\.scoreValue)
            guard !stressValues.isEmpty else { return nil }
            let avg = stressValues.reduce(0, +) / stressValues.count
            return SleepStressPoint(
                date: sleep.date,
                sleepHours: sleep.totalHours,
                avgStress: avg
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("过去 30 天 · 睡眠 vs 压力")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if dataPoints.isEmpty {
                Text("数据不足,需要至少 3 天有睡眠 + 监测记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(dataPoints) { point in
                    PointMark(
                        x: .value("睡眠", point.sleepHours),
                        y: .value("压力", point.avgStress)
                    )
                    .foregroundStyle(colorFor(score: point.avgStress))
                    .symbolSize(90)
                }
                .chartXScale(domain: 0...12)
                .chartYScale(domain: 0...100)
                .chartXAxisLabel("睡眠时长 (小时)")
                .chartYAxisLabel("当日平均压力")
                .frame(height: 220)
            }

            Text(LocalizedStringKey(insight))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func colorFor(score: Int) -> Color {
        switch score {
        case ...30: .mint
        case 31...50: .green
        case 51...70: .yellow
        case 71...85: .orange
        default: .red
        }
    }

    private var insight: String {
        guard !dataPoints.isEmpty else { return "" }
        let avgSleep = dataPoints.map(\.sleepHours).reduce(0, +) / Double(dataPoints.count)

        let shortSleep = dataPoints.filter { $0.sleepHours < avgSleep }
        let longSleep = dataPoints.filter { $0.sleepHours >= avgSleep }

        guard !shortSleep.isEmpty, !longSleep.isEmpty else {
            return "继续记录,30 天后能看到更准确的关联。"
        }
        let shortAvg = shortSleep.map(\.avgStress).reduce(0, +) / shortSleep.count
        let longAvg = longSleep.map(\.avgStress).reduce(0, +) / longSleep.count
        let diff = shortAvg - longAvg

        if diff > 8 {
            return "睡得少的日子压力平均高 \(diff) 分。建议保证 7+ 小时睡眠。"
        } else if diff < -8 {
            return "睡眠时长与压力关联不大 — 可能其他因素(如工作 / 运动)影响更大。"
        } else {
            return "睡眠时长与压力关联较弱,记录更多天后会更准确。"
        }
    }
}

struct SleepStressPoint: Identifiable {
    let id = UUID()
    let date: Date
    let sleepHours: Double
    let avgStress: Int
}

#Preview {
    NavigationStack {
        SleepInsightView()
    }
}
