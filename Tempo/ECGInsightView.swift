//
//  ECGInsightView.swift
//  Tempo
//
//  展示 Apple Watch ECG 解析出的 RMSSD / SDNN / pNN50 指标。
//  Apple HealthKit 主流 SDNN 是 5-10min 滑动均值,精度有限;
//  Apple Watch ECG App 手动录的 30s ECG 给了我们「真 RMSSD」。
//

import SwiftUI
import TempoCore

struct ECGInsightView: View {
    @State private var metrics: [ECGAnalysisResult] = []
    @State private var dataState: TempoLoadState = .idle
    @Environment(\.dismiss) private var dismiss

    private var latest: ECGAnalysisResult? { metrics.first }

    private var rmssdBaseline: Double {
        // 用最近 5 次均值作为 baseline
        let recent = metrics.prefix(5).map(\.metrics.rmssd).filter { $0 > 0 }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0, +) / Double(recent.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsSheetHeader(
                        icon: "waveform.path.ecg",
                        color: Color(hex: "EC4899"),
                        title: "ECG 高分辨率 HRV",
                        subtitle: "由你 Apple Watch 录制的 30s ECG 解析"
                    )

                    TempoDataStateView(
                        state: dataState,
                        loadingTitle: "正在解析最近 ECG",
                        emptyTitle: "还没有 ECG 数据",
                        emptyDetail: "在 Apple Watch 上打开 ECG App 录制 30 秒，Tempo 会自动读取并计算 RMSSD。",
                        cachedTitle: "正在显示上次 ECG 结果",
                        cachedDetailOverride: "新的 ECG 暂时没有读取成功，当前分析继续保留。",
                        onRetry: { Task { await loadECGs() } }
                    )

                    if !metrics.isEmpty {
                        latestCard
                        historyList
                        SettingsFootnoteCard(
                            icon: "info.circle.fill",
                            color: TempoTheme.accent,
                            text: "Apple HealthKit 主流只暴露 SDNN(5-10min 均值)。Apple Watch ECG App 手动录的 30s 数据,Tempo 用 Pan-Tompkins 简化算法检测 R 波,提取 RR 间期,算出 RMSSD/SDNN/pNN50 — 这是 Whoop / Oura 用的「真 HRV」指标。"
                        )
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .refreshable { await loadECGs() }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("ECG 数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await loadECGs() }
        }
    }

    private var latestCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let latest {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近一次")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(TempoTheme.tertiaryText)
                        Text(formatDate(latest.metrics.recordedAt))
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                    }
                    Spacer()
                    Text("\(latest.metrics.beatCount) 拍")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(TempoTheme.tertiaryText.opacity(0.1)))
                }

                let m = latest.metrics
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metricBlock(label: "RMSSD", value: String(format: "%.0f", m.rmssd), unit: "ms",
                                color: rmssdColor(m.rmssd),
                                hint: rmssdHint(m.rmssd))
                    metricBlock(label: "SDNN", value: String(format: "%.0f", m.sdnn), unit: "ms",
                                color: Color(hex: "6366F1"),
                                hint: "短时整体变异")
                    metricBlock(label: "pNN50", value: String(format: "%.1f", m.pnn50), unit: "%",
                                color: Color(hex: "8B5CF6"),
                                hint: "迷走神经活跃度")
                    metricBlock(label: "心率", value: String(format: "%.0f", m.avgHeartRate), unit: "bpm",
                                color: Color.pink,
                                hint: "ECG 平均")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 18, padding: 18)
    }

    private func metricBlock(label: String, value: String, unit: String, color: Color, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Text(hint)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近记录")
                .font(.system(size: 13, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)

            VStack(spacing: 0) {
                ForEach(metrics.prefix(8)) { r in
                    historyRow(r)
                    if r != metrics.prefix(8).last {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .settingsPanel()
        }
    }

    private func historyRow(_ r: ECGAnalysisResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color(hex: "EC4899"))
                .frame(width: 22)
            Text(formatDate(r.metrics.recordedAt))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Spacer()
            Text("RMSSD \(String(format: "%.0f", r.metrics.rmssd))ms")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(rmssdColor(r.metrics.rmssd))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func rmssdColor(_ value: Double) -> Color {
        switch value {
        case ..<15: TempoTheme.danger
        case 15..<25: TempoTheme.warning
        case 25..<50: TempoTheme.accent
        default: TempoTheme.success
        }
    }

    private func rmssdHint(_ value: Double) -> String {
        switch value {
        case ..<15: "偏低,迷走神经活动弱"
        case 15..<25: "略低"
        case 25..<50: "正常"
        default: "良好"
        }
    }

    private func formatDate(_ d: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = TempoAppLanguage.currentLocale
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: d)
    }

    private func loadECGs() async {
        dataState = .loading
        let ecgs = await HealthKitService.shared.fetchRecentECG(daysBack: 90, maxCount: 15)
        guard !ecgs.isEmpty else {
            metrics = []
            dataState = .empty
            return
        }

        var results: [ECGAnalysisResult] = []
        for ecg in ecgs {
            let voltages = await HealthKitService.shared.fetchECGVoltage(ecg)
            let m = ECGAnalyzer.analyze(ecg: ecg, voltages: voltages)
            if m.beatCount > 0 {
                results.append(ECGAnalysisResult(metrics: m))
            }
        }
        metrics = results
        dataState = results.isEmpty ? .empty : .ready(.now)
    }
}

struct ECGAnalysisResult: Identifiable, Hashable {
    let metrics: ECGMetrics
    var id: Date { metrics.recordedAt }
}
