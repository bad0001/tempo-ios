//
//  RecoveryWidget.swift
//  TempoWidgets
//
//  独立的 Recovery / Strain / Sleep / Temp Widget。
//  与 stress widget 一起放主屏:左 stress / 右 recovery。
//

import WidgetKit
import SwiftUI
import TempoCore

// MARK: - Entry

struct RecoveryWidgetEntry: TimelineEntry {
    let date: Date
    let recoveryValue: Int?
    let recoveryLevel: RecoveryLevel?
    let strainValue: Double?
    let strainLevel: StrainLevel?
    let deepSleep: Double?
    let remSleep: Double?
    let totalSleep: Double?
    let wristTempZ: Double?
    let hasElevatedTemp: Bool
    let isFresh: Bool

    static func from(snapshot: WatchSnapshot) -> RecoveryWidgetEntry {
        RecoveryWidgetEntry(
            date: snapshot.updatedAt,
            recoveryValue: snapshot.recoveryValue,
            recoveryLevel: snapshot.recoveryLevel,
            strainValue: snapshot.strainValue,
            strainLevel: snapshot.strainLevel,
            deepSleep: snapshot.deepSleepHours,
            remSleep: snapshot.remSleepHours,
            totalSleep: snapshot.totalAsleepHours,
            wristTempZ: snapshot.wristTempZScore,
            hasElevatedTemp: snapshot.recoveryHasElevatedTemp,
            isFresh: snapshot.isFresh
        )
    }

    static let mock = RecoveryWidgetEntry(
        date: .now,
        recoveryValue: 78,
        recoveryLevel: .good,
        strainValue: 4.2,
        strainLevel: .moderate,
        deepSleep: 1.4,
        remSleep: 1.6,
        totalSleep: 7.5,
        wristTempZ: 0.3,
        hasElevatedTemp: false,
        isFresh: true
    )
}

// MARK: - Provider

struct RecoveryProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryWidgetEntry {
        .mock
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryWidgetEntry) -> Void) {
        completion(loadEntry() ?? .mock)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryWidgetEntry>) -> Void) {
        let entry = loadEntry() ?? .mock
        // Recovery 变化频率低,半小时刷一次够了
        let next = Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> RecoveryWidgetEntry? {
        guard let snap = SharedSnapshotStore.read() else { return nil }
        return .from(snapshot: snap)
    }
}

// MARK: - Entry Router

struct RecoveryWidgetEntryView: View {
    let entry: RecoveryWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        #if !os(watchOS)
        case .systemSmall: SmallRecoveryView(entry: entry)
        case .systemMedium: MediumRecoveryView(entry: entry)
        case .systemLarge: LargeRecoveryView(entry: entry)
        #endif
        case .accessoryCircular: CircularRecoveryView(entry: entry)
        case .accessoryInline: InlineRecoveryView(entry: entry)
        case .accessoryRectangular: RectangularRecoveryView(entry: entry)
        default: CircularRecoveryView(entry: entry)
        }
    }
}

// MARK: - Helpers

func recoveryColor(for level: RecoveryLevel?) -> Color {
    switch level {
    case .poor: .red
    case .fair: .orange
    case .good: .mint
    case .excellent: .green
    case .none: .gray
    }
}

func strainColor(for level: StrainLevel?) -> Color {
    switch level {
    case .light: .green
    case .moderate: .yellow
    case .heavy: .orange
    case .allOut: .red
    case .none: .gray
    }
}

// MARK: - System Family Views

#if !os(watchOS)
struct SmallRecoveryView: View {
    let entry: RecoveryWidgetEntry

    var body: some View {
        VStack(spacing: 4) {
            RecoveryGaugeView(
                value: entry.recoveryValue,
                level: entry.recoveryLevel,
                lineWidth: 10,
                showHint: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 4) {
                if entry.hasElevatedTemp {
                    Image(systemName: "thermometer.high")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
                Text(WidgetLocalization.recoveryLevel(entry.recoveryLevel))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(recoveryColor(for: entry.recoveryLevel))
            }
        }
        .padding(8)
    }
}

struct MediumRecoveryView: View {
    let entry: RecoveryWidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            RecoveryGaugeView(
                value: entry.recoveryValue,
                level: entry.recoveryLevel,
                lineWidth: 11,
                showHint: true
            )
            .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 6) {
                if let strain = entry.strainValue {
                    statLine(
                        icon: "flame.fill",
                        label: String(localized: "负荷"),
                        value: String(format: "%.1f / 10", strain),
                        color: strainColor(for: entry.strainLevel)
                    )
                }
                if let deep = entry.deepSleep, deep > 0 {
                    statLine(
                        icon: "moon.zzz.fill",
                        label: String(localized: "深睡"),
                        value: String(format: "%.1f h", deep),
                        color: .indigo
                    )
                }
                if let rem = entry.remSleep, rem > 0 {
                    statLine(
                        icon: "moon.stars.fill",
                        label: "REM",
                        value: String(format: "%.1f h", rem),
                        color: .purple
                    )
                }
                if let z = entry.wristTempZ, abs(z) > 0.5 {
                    statLine(
                        icon: entry.hasElevatedTemp ? "thermometer.high" : "thermometer.medium",
                        label: String(localized: "体温"),
                        value: String(format: "%+.1f σ", z),
                        color: entry.hasElevatedTemp ? .orange : .green
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    @ViewBuilder
    private func statLine(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption2)
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

struct LargeRecoveryView: View {
    let entry: RecoveryWidgetEntry

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                RecoveryGaugeView(
                    value: entry.recoveryValue,
                    level: entry.recoveryLevel,
                    lineWidth: 13,
                    showHint: true
                )
                .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    bigStatRow(
                        icon: "flame.fill",
                        label: String(localized: "日内负荷"),
                        value: entry.strainValue.map { String(format: "%.1f", $0) } ?? "—",
                        unit: " / 10",
                        levelText: WidgetLocalization.strainLevel(entry.strainLevel),
                        color: strainColor(for: entry.strainLevel)
                    )
                    if let total = entry.totalSleep, total > 0 {
                        bigStatRow(
                            icon: "bed.double.fill",
                            label: String(localized: "睡眠总时长"),
                            value: String(format: "%.1f", total),
                            unit: " h",
                            levelText: String(localized: "深睡 \(formatHours(entry.deepSleep)) · REM \(formatHours(entry.remSleep))"),
                            color: .indigo
                        )
                    }
                    if let z = entry.wristTempZ {
                        bigStatRow(
                            icon: entry.hasElevatedTemp ? "thermometer.high" : "thermometer.medium",
                            label: String(localized: "体温偏差"),
                            value: String(format: "%+.1f", z),
                            unit: " σ",
                            levelText: entry.hasElevatedTemp
                                ? String(localized: "可能在生病 / 过劳")
                                : String(localized: "正常区间"),
                            color: entry.hasElevatedTemp ? .orange : .green
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(String(localized: "Tempo · 最后更新 \(entry.date.formatted(date: .omitted, time: .shortened))"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private func formatHours(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        return String(format: "%.1f h", v)
    }

    @ViewBuilder
    private func bigStatRow(icon: String, label: String, value: String, unit: String, levelText: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.body)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(levelText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
#endif

// MARK: - Accessory Family Views

struct CircularRecoveryView: View {
    let entry: RecoveryWidgetEntry

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(entry.recoveryValue ?? 0) / 100.0)
                .stroke(recoveryColor(for: entry.recoveryLevel), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(entry.recoveryValue ?? 0)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("REC")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InlineRecoveryView: View {
    let entry: RecoveryWidgetEntry

    var body: some View {
        if let v = entry.recoveryValue {
            Text(String(localized: "Tempo · 恢复 \(v) \(WidgetLocalization.recoveryLevel(entry.recoveryLevel))"))
        } else {
            Text("Tempo · 等待数据")
        }
    }
}

struct RectangularRecoveryView: View {
    let entry: RecoveryWidgetEntry

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.tertiary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(entry.recoveryValue ?? 0) / 100.0)
                    .stroke(recoveryColor(for: entry.recoveryLevel), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(entry.recoveryValue ?? 0)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(WidgetLocalization.recoveryLevel(entry.recoveryLevel))
                    .font(.caption.weight(.medium))
                if let strain = entry.strainValue {
                    Text(String(format: String(localized: "负荷 %.1f"), strain))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pieces

struct RecoveryGaugeView: View {
    let value: Int?
    let level: RecoveryLevel?
    let lineWidth: CGFloat
    let showHint: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary.opacity(0.3), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(value ?? 0) / 100.0)
                .stroke(recoveryColor(for: level), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(value.map { "\($0)" } ?? "—")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                if showHint {
                    Text("恢复")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Widget Configuration

struct RecoveryWidget: Widget {
    let kind: String = "RecoveryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecoveryProvider()) { entry in
            RecoveryWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tempo 恢复 + 体能")
        .description("查看恢复 / 日内负荷 / 睡眠分期 / 体温偏差。")
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
    RecoveryWidget()
} timeline: {
    RecoveryWidgetEntry.mock
    RecoveryWidgetEntry(
        date: .now,
        recoveryValue: 42,
        recoveryLevel: .fair,
        strainValue: 7.8,
        strainLevel: .heavy,
        deepSleep: 0.6,
        remSleep: 1.1,
        totalSleep: 5.8,
        wristTempZ: 1.6,
        hasElevatedTemp: true,
        isFresh: true
    )
}
#endif
