//
//  WatchComplications.swift
//  TempoWatchComplications (watchOS Widget Extension)
//
//  Apple Watch 表盘 complications — stress + recovery + 多指标。
//  数据来源:SharedSnapshotStore(App Group 文件,Phone 写 Watch / Widget 读)。
//
//  跟 iOS TempoWidgets 共享同一份 WatchSnapshot 数据契约,但代码独立
//  (Apple 不允许同一个 widget extension 跨 iOS / watchOS embed)。
//

import WidgetKit
import SwiftUI
import TempoCore

// MARK: - Bundle

@main
struct TempoWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        StressComplication()
        RecoveryComplication()
        TempoIndexComplication()
    }
}

// MARK: - Stress Complication

struct StressComplication: Widget {
    let kind = "StressComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider { snap in
            StressEntry(date: snap.updatedAt, snapshot: snap)
        }) { entry in
            StressComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tempo 压力")
        .description("当前压力分 + 等级 + 体温警示。")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct StressEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot
}

struct StressComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StressEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: circular
        }
    }

    private var stressValue: Int { entry.snapshot.stressValue ?? 0 }
    private var hasValue: Bool { entry.snapshot.stressValue != nil }

    private var color: Color {
        guard let level = entry.snapshot.stressLevel else { return .gray }
        switch level {
        case .calm: return .mint
        case .relaxed: return .green
        case .mild: return .yellow
        case .high: return .orange
        case .extreme: return .red
        }
    }

    private var levelName: String {
        entry.snapshot.stressLevel?.displayName ?? "—"
    }

    // MARK: Circular

    private var circular: some View {
        ZStack {
            Circle().stroke(.tertiary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(stressValue) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(hasValue ? "\(stressValue)" : "—")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("压力")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Rectangular

    private var rectangular: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(.tertiary, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(stressValue) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(hasValue ? "\(stressValue)" : "—")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("压力 · \(levelName)")
                    .font(.system(size: 11, weight: .heavy))
                if entry.snapshot.recoveryHasElevatedTemp {
                    Label("体温偏高", systemImage: "thermometer.high")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.orange)
                } else if let hr = entry.snapshot.latestHR, hr > 0 {
                    Text("\(Int(hr)) bpm")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Inline

    private var inline: some View {
        if hasValue {
            Text("Tempo · 压力 \(stressValue) \(levelName)")
        } else {
            Text("Tempo · 打开 App 同步")
        }
    }

    // MARK: Corner

    private var corner: some View {
        Text(hasValue ? "\(stressValue)" : "—")
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: Double(stressValue), in: 0...100) {
                    Text("压力")
                } currentValueLabel: {
                    Text("\(stressValue)")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(color)
            }
    }
}

// MARK: - Recovery Complication

struct RecoveryComplication: Widget {
    let kind = "RecoveryComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider { snap in
            RecoveryEntry(date: snap.updatedAt, snapshot: snap)
        }) { entry in
            RecoveryComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tempo 恢复")
        .description("当前恢复分 + 负荷 + 体温偏差。")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct RecoveryEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot
}

struct RecoveryComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecoveryEntry

    private var value: Int { entry.snapshot.recoveryValue ?? 0 }
    private var hasValue: Bool { entry.snapshot.recoveryValue != nil }

    private var color: Color {
        switch entry.snapshot.recoveryLevel {
        case .poor: return .red
        case .fair: return .orange
        case .good: return .mint
        case .excellent: return .green
        case .none: return .gray
        }
    }

    private var levelName: String {
        entry.snapshot.recoveryLevel?.displayName ?? "—"
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: circular
        }
    }

    private var circular: some View {
        ZStack {
            Circle().stroke(.tertiary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(value) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(hasValue ? "\(value)" : "—")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("REC")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(.tertiary, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(value) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(hasValue ? "\(value)" : "—")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("恢复 · \(levelName)")
                    .font(.system(size: 11, weight: .heavy))
                if let strain = entry.snapshot.strainValue {
                    Text(String(format: "负荷 %.1f", strain))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var inline: some View {
        if hasValue {
            Text("Tempo · 恢复 \(value) \(levelName)")
        } else {
            Text("Tempo · 打开 App 同步")
        }
    }

    private var corner: some View {
        Text(hasValue ? "\(value)" : "—")
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: Double(value), in: 0...100) {
                    Text("恢复")
                } currentValueLabel: {
                    Text("\(value)")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(color)
            }
    }
}

// MARK: - Combined TempoIndex Complication(压力 + 恢复 + 心率 一站)

struct TempoIndexComplication: Widget {
    let kind = "TempoIndexComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider { snap in
            TempoIndexEntry(date: snap.updatedAt, snapshot: snap)
        }) { entry in
            TempoIndexComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tempo 节奏")
        .description("压力 / 恢复 / 心率 一行看完。")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct TempoIndexEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot
}

struct TempoIndexComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TempoIndexEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("Tempo")
                    .font(.system(size: 11, weight: .heavy))
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                miniStat(icon: "bolt.heart.fill", color: .orange,
                         value: entry.snapshot.stressValue.map { "\($0)" } ?? "—")
                miniStat(icon: "leaf.fill", color: .mint,
                         value: entry.snapshot.recoveryValue.map { "\($0)" } ?? "—")
                miniStat(icon: "heart.fill", color: .pink,
                         value: entry.snapshot.latestHR.map { "\(Int($0))" } ?? "—")
            }
        }
    }

    private func miniStat(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            Text(value).font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
        }
    }

    private var inline: some View {
        let s = entry.snapshot.stressValue.map { "\($0)" } ?? "—"
        let r = entry.snapshot.recoveryValue.map { "\($0)" } ?? "—"
        return Text("Tempo · 压力 \(s) · 恢复 \(r)")
    }
}

// MARK: - Provider(三个 widget 共用)

struct WatchProvider<Entry: TimelineEntry>: TimelineProvider {
    let make: (WatchSnapshot) -> Entry

    func placeholder(in context: Context) -> Entry {
        make(.empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(make(SharedSnapshotStore.read() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = SharedSnapshotStore.read() ?? .empty
        let entry = make(snap)
        // 15min 刷新一次,降低 watchOS budget 压力
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
