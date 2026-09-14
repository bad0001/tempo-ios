//
//  TempoWidgets.swift
//  TempoWidgets
//

import WidgetKit
import SwiftUI
import SwiftData
import TempoCore

// MARK: - Timeline Entry

struct StressWidgetEntry: TimelineEntry {
    let date: Date
    let score: StressScore
    let bpm: Int
    let history: [Int]
    /// v3 来自 snapshot:体温偏高时显示警示标
    let hasElevatedTemp: Bool

    init(date: Date, score: StressScore, bpm: Int, history: [Int], hasElevatedTemp: Bool = false) {
        self.date = date
        self.score = score
        self.bpm = bpm
        self.history = history
        self.hasElevatedTemp = hasElevatedTemp
    }
}

struct StressProvider: TimelineProvider {
    private let container: ModelContainer = TempoSharedStore.makeModelContainer()

    func placeholder(in context: Context) -> StressWidgetEntry {
        Self.mockEntry(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (StressWidgetEntry) -> Void) {
        let entry = readEntry() ?? Self.mockEntry(at: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StressWidgetEntry>) -> Void) {
        let now = Date()
        let entry = readEntry() ?? Self.mockEntry(at: now)
        let next = now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> StressWidgetEntry? {
        // v3:优先读 App Group snapshot 文件(包含完整指标)
        if let snap = SharedSnapshotStore.read(),
           snap.isFresh,
           let value = snap.stressValue,
           let levelRaw = snap.stressLevelRaw,
           let level = StressLevel(rawValue: levelRaw) {
            let score = StressScore(value: value, timestamp: snap.updatedAt)
            _ = level   // value 已包含 level,这里只是验证 raw 合法
            return StressWidgetEntry(
                date: snap.updatedAt,
                score: score,
                bpm: Int(snap.latestHR ?? 0),
                history: readHistory(),
                hasElevatedTemp: snap.recoveryHasElevatedTemp
            )
        }

        // Fallback:老逻辑读 SwiftData
        let context = ModelContext(container)
        let cutoff = Date().addingTimeInterval(-86400)
        let predicate = #Predicate<StressEntry> { $0.timestamp >= cutoff }
        var descriptor = FetchDescriptor<StressEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        guard let entries = try? context.fetch(descriptor),
              !entries.isEmpty,
              let latest = entries.first else {
            return nil
        }

        let now = Date()
        let history: [Int] = (0..<24).map { offset in
            let hourStart = now.addingTimeInterval(-Double(24 - offset) * 3600)
            let hourEnd = now.addingTimeInterval(-Double(23 - offset) * 3600)
            let inHour = entries.filter { $0.timestamp >= hourStart && $0.timestamp < hourEnd }
            if inHour.isEmpty { return 50 }
            return inHour.map(\.scoreValue).reduce(0, +) / inHour.count
        }

        return StressWidgetEntry(
            date: latest.timestamp,
            score: StressScore(value: latest.scoreValue),
            bpm: Int(latest.bpm),
            history: history
        )
    }

    /// 历史小柱 24h(从 SwiftData,与 snapshot 配合)
    private func readHistory() -> [Int] {
        let context = ModelContext(container)
        let cutoff = Date().addingTimeInterval(-86400)
        let predicate = #Predicate<StressEntry> { $0.timestamp >= cutoff }
        var descriptor = FetchDescriptor<StressEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        let entries = (try? context.fetch(descriptor)) ?? []
        let now = Date()
        return (0..<24).map { offset in
            let hourStart = now.addingTimeInterval(-Double(24 - offset) * 3600)
            let hourEnd = now.addingTimeInterval(-Double(23 - offset) * 3600)
            let inHour = entries.filter { $0.timestamp >= hourStart && $0.timestamp < hourEnd }
            if inHour.isEmpty { return 50 }
            return inHour.map(\.scoreValue).reduce(0, +) / inHour.count
        }
    }

    private static func mockEntry(at date: Date) -> StressWidgetEntry {
        let baseline = circadianBaseline(forHour: Calendar.current.component(.hour, from: date))
        let value = max(0, min(100, baseline + Int.random(in: -5...5)))
        let bpm = 60 + (value / 4)
        return StressWidgetEntry(
            date: date,
            score: StressScore(value: value),
            bpm: bpm,
            history: mockHistory(for: date)
        )
    }

    private static func mockHistory(for date: Date) -> [Int] {
        let cal = Calendar.current
        return (0..<24).map { offset in
            let hourDate = cal.date(byAdding: .hour, value: offset - 23, to: date) ?? date
            let hour = cal.component(.hour, from: hourDate)
            return circadianBaseline(forHour: hour) + Int.random(in: -8...8)
        }
    }

    private static func circadianBaseline(forHour hour: Int) -> Int {
        switch hour {
        case 0..<6: 28
        case 6..<8: 38
        case 8..<11: 55
        case 11..<14: 60
        case 14..<18: 70
        case 18..<21: 55
        case 21..<24: 38
        default: 32
        }
    }
}

// MARK: - Entry Router

struct TempoWidgetsEntryView: View {
    var entry: StressWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        #if !os(watchOS)
        case .systemSmall:
            SmallStressView(entry: entry)
        case .systemMedium:
            MediumStressView(entry: entry)
        case .systemLarge:
            LargeStressView(entry: entry)
        #endif
        case .accessoryCircular:
            CircularStressView(entry: entry)
        case .accessoryInline:
            InlineStressView(entry: entry)
        case .accessoryRectangular:
            RectangularStressView(entry: entry)
        default:
            CircularStressView(entry: entry)
        }
    }
}

// MARK: - System Family Views

#if !os(watchOS)
struct SmallStressView: View {
    let entry: StressWidgetEntry

    var body: some View {
        VStack(spacing: 4) {
            StressGaugeView(score: entry.score, lineWidth: 10, showHint: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 4) {
                if entry.hasElevatedTemp {
                    Image(systemName: "thermometer.high")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
                Text(WidgetLocalization.stressLevel(entry.score.level))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(stressColor(for: entry.score.level))
            }
        }
        .padding(8)
    }
}

struct MediumStressView: View {
    let entry: StressWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            StressGaugeView(score: entry.score, lineWidth: 12, showHint: true)
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.caption)
                    Text("\(entry.bpm) BPM")
                        .font(.subheadline.weight(.medium))
                }
                MiniChartView(values: entry.history)
                    .frame(height: 36)
                Text(WidgetLocalization.stressLevel(entry.score.level))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }
}

struct LargeStressView: View {
    let entry: StressWidgetEntry

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                StressGaugeView(score: entry.score, lineWidth: 14, showHint: true)
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 10) {
                    statRow(icon: "heart.fill", label: String(localized: "心率"), value: "\(entry.bpm) BPM", color: .pink)
                    statRow(icon: "waveform.path", label: String(localized: "等级"), value: WidgetLocalization.stressLevel(entry.score.level), color: stressColor(for: entry.score.level))
                    statRow(icon: "clock", label: String(localized: "更新"), value: entry.date.formatted(date: .omitted, time: .shortened), color: .secondary)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("过去 24 小时")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                MiniChartView(values: entry.history)
                    .frame(height: 50)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func statRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
                .frame(width: 18)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
        }
    }
}
#endif

// MARK: - Accessory Family Views

struct CircularStressView: View {
    let entry: StressWidgetEntry

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(entry.score.value) / 100.0)
                .stroke(stressColor(for: entry.score.level), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(entry.score.value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
    }
}

struct InlineStressView: View {
    let entry: StressWidgetEntry

    var body: some View {
        Text("Tempo · \(entry.score.value) \(WidgetLocalization.stressLevel(entry.score.level))")
    }
}

struct RectangularStressView: View {
    let entry: StressWidgetEntry

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.tertiary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(entry.score.value) / 100.0)
                    .stroke(stressColor(for: entry.score.level), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(entry.score.value)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(WidgetLocalization.stressLevel(entry.score.level))
                    .font(.caption.weight(.medium))
                Text("\(entry.bpm) BPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pieces

struct StressGaugeView: View {
    let score: StressScore
    let lineWidth: CGFloat
    let showHint: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary.opacity(0.3), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(score.value) / 100.0)
                .stroke(stressColor(for: score.level), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(score.value)")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                if showHint {
                    Text("压力")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct MiniChartView: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 100, 1)
            let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))

            Path { p in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height * (1 - CGFloat(v) / CGFloat(maxV))
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(LinearGradient(
                colors: [.mint, .yellow, .pink],
                startPoint: .leading,
                endPoint: .trailing
            ), lineWidth: 2)
        }
    }
}

func stressColor(for level: StressLevel) -> Color {
    switch level {
    case .calm: .mint
    case .relaxed: .green
    case .mild: .yellow
    case .high: .orange
    case .extreme: .red
    }
}

// MARK: - Widget Configuration

struct TempoWidgets: Widget {
    let kind: String = "TempoWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StressProvider()) { entry in
            TempoWidgetsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tempo 压力监测")
        .description("查看实时压力分、心率和过去 24 小时趋势。")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryInline, .accessoryRectangular]
        #else
        return [
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryInline, .accessoryRectangular
        ]
        #endif
    }
}

#if !os(watchOS)
#Preview(as: .systemMedium) {
    TempoWidgets()
} timeline: {
    StressWidgetEntry(
        date: .now,
        score: StressScore(value: 35),
        bpm: 68,
        history: (0..<24).map { _ in Int.random(in: 30...75) }
    )
    StressWidgetEntry(
        date: .now,
        score: StressScore(value: 78),
        bpm: 92,
        history: (0..<24).map { _ in Int.random(in: 30...85) }
    )
}
#endif
