//
//  HistoryView.swift
//  Tempo
//

import Foundation
import SwiftUI
import Charts
import SwiftData
import TempoCore
#if canImport(UIKit)
import UIKit
#endif

/// HistoryView @Query cutoff:1 year picker 最多回看 1 年
private let historyCutoff: Date = Date.now.addingTimeInterval(-365 * 86400)

struct HistoryView: View {
    @State private var range: TimeRange = .day
    @State private var realData: [StressDataPoint]?
    @State private var sleepHRV: Double?
    @State private var sleepHRVBaseline: Double?
    @State private var recovery: Recovery = .unknown
    @State private var strain: Strain = .none
    @State private var tempoIndex: TempoIndex = .unknown
    @State private var hrvHistory: [HealthMetricHistoryPoint] = []
    @State private var restingHeartRateHistory: [HealthMetricHistoryPoint] = []
    @State private var sleepHistory: [DailySleepData] = []
    @State private var friendsService = FriendsService.shared
    @State private var selectedShareFriendID: String?
    @State private var isSharingTrend = false
    @State private var trendShareStatus: String?
    @State private var showECG: Bool = false
    @State private var showMentalHealth: Bool = false
    @State private var selectedEpisode: StressEpisode?
    @State private var dataState: TempoLoadState = .idle
    @State private var showsAdvancedAnalysis = false
    @Query(filter: #Predicate<StressEntry> { $0.timestamp > historyCutoff },
           sort: \StressEntry.timestamp, order: .reverse) private var stressEntries: [StressEntry]

    enum TimeRange: String, CaseIterable, Identifiable {
        case day = "24 小时"
        case week = "7 天"
        case month = "30 天"
        case year = "1 年"

        var id: String { rawValue }

        var pointCount: Int {
            switch self {
            case .day: 48
            case .week: 168
            case .month: 30
            case .year: 52
            }
        }

        var stride: TimeInterval {
            switch self {
            case .day: 1800
            case .week: 3600
            case .month: 86400
            case .year: 604800
            }
        }
    }

    private var dataPoints: [StressDataPoint] {
        if let swift = swiftDataPoints { return swift }
        if let real = realData, !real.isEmpty { return real }
        return []
    }

    private var cutoffDate: Date {
        Date().addingTimeInterval(-Double(range.pointCount) * range.stride)
    }

    private var rangedEntries: [StressEntry] {
        stressEntries.filter { $0.timestamp >= cutoffDate }
    }

    private var swiftDataPoints: [StressDataPoint]? {
        let filtered = rangedEntries
        guard !filtered.isEmpty else { return nil }
        return filtered.map {
            StressDataPoint(date: $0.timestamp, score: $0.scoreValue)
        }.sorted { $0.date < $1.date }
    }

    private var isShowingMock: Bool {
        swiftDataPoints == nil && (realData?.isEmpty ?? true)
    }

    private var dataSourceLabel: String {
        if swiftDataPoints != nil { return "真实记录" }
        if realData?.isEmpty == false { return "HealthKit 估算" }
        return "等待数据"
    }

    private var dataSourceDetail: String {
        if swiftDataPoints != nil {
            return "来自 Apple Watch 实时心率写入的本机压力记录。"
        }
        if realData?.isEmpty == false {
            return "本机还没有压力记录,当前由 HealthKit 心率历史临时估算。"
        }
        return "佩戴 Apple Watch 后，这里会显示真实压力记录。"
    }

    private var stats: (avg: Int, min: Int, max: Int) {
        let values = dataPoints.map(\.score)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / values.count
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        return (avg, minV, maxV)
    }

    private var professionalSummary: StressProfessionalSummary {
        let interval = estimatedPointInterval
        let highMinutes = Int((Double(dataPoints.filter { $0.score >= 70 }.count) * interval / 60).rounded())
        let load = dataPoints.reduce(0.0) { partial, point in
            partial + max(Double(point.score - 50), 0) * interval / 3600
        }
        let latestHRV = hrvTrendPoints.last?.value ?? sleepHRV
        let latestRHR = restingHeartRateHistory.last?.value
        let hrvDeviation: Int?
        if let latestHRV, let baseline = sleepHRVBaseline, baseline > 0 {
            hrvDeviation = Int(((latestHRV - baseline) / baseline * 100).rounded())
        } else {
            hrvDeviation = nil
        }
        return StressProfessionalSummary(
            average: stats.avg,
            peak: stats.max,
            low: stats.min,
            highStressMinutes: max(0, highMinutes),
            stressLoad: Int(load.rounded()),
            dataConfidence: dataConfidence,
            hrvDeviationPercent: hrvDeviation,
            latestHRV: latestHRV,
            latestRestingHeartRate: latestRHR
        )
    }

    private var estimatedPointInterval: TimeInterval {
        let sorted = dataPoints.sorted { $0.date < $1.date }
        guard sorted.count > 1 else { return range.stride }
        let intervals = zip(sorted, sorted.dropFirst())
            .map { $1.date.timeIntervalSince($0.date) }
            .filter { $0 > 0 && $0 < 12 * 3600 }
            .sorted()
        guard !intervals.isEmpty else { return range.stride }
        return min(intervals[intervals.count / 2], range.stride)
    }

    private var dataConfidence: Int {
        guard !isShowingMock else { return 0 }
        let expected = max(range.pointCount, 1)
        let density = min(1.0, Double(dataPoints.count) / Double(expected))
        let sourceBonus = swiftDataPoints != nil ? 18.0 : 8.0
        return max(20, min(100, Int((density * 82.0 + sourceBonus).rounded())))
    }

    private var peakLabel: String {
        guard let peak = dataPoints.max(by: { $0.score < $1.score }) else {
            return "暂无峰值数据"
        }
        let formatter = DateFormatter()
        formatter.locale = TempoAppLanguage.currentLocale
        switch range {
        case .day: formatter.dateFormat = "HH:mm"
        case .week: formatter.dateFormat = "EEEE HH 时"
        case .month: formatter.dateFormat = "M 月 d 日"
        case .year: formatter.dateFormat = "yyyy 年 M 月"
        }
        return "峰值出现在 \(formatter.string(from: peak.date))"
    }

    private var uniqueDays: Int {
        let calendar = Calendar.current
        let days = Set(stressEntries.map { calendar.startOfDay(for: $0.timestamp) })
        return days.count
    }

    private var dailyAvgTrend: Double? {
        // 今日均值 vs 过去 7 天均值
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart

        let today = stressEntries.filter { $0.timestamp >= todayStart }
        let prior = stressEntries.filter { $0.timestamp >= weekAgo && $0.timestamp < todayStart }

        guard !today.isEmpty, !prior.isEmpty else { return nil }
        let todayAvg = Double(today.map(\.scoreValue).reduce(0, +)) / Double(today.count)
        let priorAvg = Double(prior.map(\.scoreValue).reduce(0, +)) / Double(prior.count)
        guard priorAvg > 0 else { return nil }
        return (todayAvg - priorAvg) / priorAvg * 100
    }

    private var sleepHRVTrend: Double? {
        guard let hrv = sleepHRV, let base = sleepHRVBaseline, base > 0 else { return nil }
        return (hrv - base) / base * 100
    }

    private var stressBarBuckets: [StressBarBucket] {
        aggregateStressBuckets(from: dataPoints)
    }

    private var stressHeatmapCells: [StressHeatmapCell] {
        aggregateHeatmapCells(from: dataPoints)
    }

    private var stressRhythmCells: [StressRhythmCell] {
        aggregateRhythmCells(from: dataPoints)
    }

    private var highStressEpisodes: [StressEpisode] {
        makeHighStressEpisodes(from: dataPoints)
    }

    private var vitalsRelationship: VitalsStressRelationship {
        guard !isShowingMock else { return .empty }
        let calendar = Calendar.current
        let stressDaily = Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: dataPoints) {
                calendar.startOfDay(for: $0.date)
            }.map { day, points in
                (day, Double(points.map(\.score).reduce(0, +)) / Double(max(points.count, 1)))
            }
        )
        let hrvDaily = Dictionary(uniqueKeysWithValues: dailyAverageHistory(from: hrvTrendPoints).map {
            (calendar.startOfDay(for: $0.date), $0.value)
        })
        let rhrDaily = Dictionary(uniqueKeysWithValues: dailyAverageHistory(from: restingHeartRateHistory).map {
            (calendar.startOfDay(for: $0.date), $0.value)
        })

        let hrvPairs = stressDaily.keys.sorted().compactMap { day -> (Double, Double)? in
            guard let stress = stressDaily[day], let hrv = hrvDaily[day] else { return nil }
            return (stress, hrv)
        }
        let rhrPairs = stressDaily.keys.sorted().compactMap { day -> (Double, Double)? in
            guard let stress = stressDaily[day], let rhr = rhrDaily[day] else { return nil }
            return (stress, rhr)
        }
        return VitalsStressRelationship(
            hrvCorrelation: pearsonCorrelation(hrvPairs),
            rhrCorrelation: pearsonCorrelation(rhrPairs),
            hrvSampleDays: hrvPairs.count,
            rhrSampleDays: rhrPairs.count
        )
    }

    private var hrvTrendPoints: [HealthMetricHistoryPoint] {
        if !hrvHistory.isEmpty { return hrvHistory }
        return dailyAverageHistory(
            from: rangedEntries.compactMap { entry in
                entry.hrv.map { HealthMetricHistoryPoint(date: entry.timestamp, value: $0) }
            }
        )
    }

    private var levelDistribution: [StressLevelDistributionItem] {
        let levels = dataPoints.map { StressLevel(score: $0.score) }
        let total = max(levels.count, 1)
        let grouped = Dictionary(grouping: levels) { $0 }
        return StressLevel.allCases.map { level in
            let count = grouped[level]?.count ?? 0
            return StressLevelDistributionItem(
                level: level,
                count: count,
                percent: Double(count) / Double(total)
            )
        }
    }

    private var trendHRVText: String {
        if let trend = sleepHRVTrend {
            return trend >= 0 ? "睡眠 HRV 比基线高 \(Int(abs(trend)))%" : "睡眠 HRV 比基线低 \(Int(abs(trend)))%"
        } else if let latestHRV = hrvTrendPoints.last?.value {
            return "最近 HRV 约 \(Int(latestHRV))ms"
        }
        return "HRV 暂无足够数据"
    }

    private var dominantStressLevel: String {
        levelDistribution.max(by: { $0.count < $1.count })?.level.tempoDisplayName
            ?? String(localized: "未知", locale: TempoAppLanguage.currentLocale)
    }

    private var trendSharePayload: [String: String] {
        let distributionPayload = trendDistributionPayload
        return [
            "range": range.rawValue,
            "average": "\(professionalSummary.average)",
            "peak": "\(professionalSummary.peak)",
            "highStressMinutes": "\(professionalSummary.highStressMinutes)",
            "stressLoad": "\(professionalSummary.stressLoad)",
            "confidence": "\(professionalSummary.dataConfidence)",
            "dominant": dominantStressLevel,
            "hrvText": trendHRVText,
            "peakLabel": peakLabel,
            "episodeCount": "\(highStressEpisodes.count)",
            "calmPercent": "\(distributionPayload.calm)",
            "mildPercent": "\(distributionPayload.mild)",
            "highPercent": "\(distributionPayload.high)",
            "trendPercent": dailyAvgTrend.map { "\(Int($0.rounded()))" } ?? "",
        ]
    }

    private var trendDistributionPayload: (calm: Int, mild: Int, high: Int) {
        let calm = levelDistribution
            .filter { $0.level == .calm || $0.level == .relaxed }
            .reduce(0.0) { $0 + $1.percent }
        let mild = levelDistribution
            .filter { $0.level == .mild }
            .reduce(0.0) { $0 + $1.percent }
        let high = max(0, 1 - calm - mild)
        return (
            Int((calm * 100).rounded()),
            Int((mild * 100).rounded()),
            Int((high * 100).rounded())
        )
    }

    private var selectedShareFriend: Friend? {
        guard let selectedShareFriendID else { return friendsService.friends.first }
        return friendsService.friends.first { $0.id == selectedShareFriendID } ?? friendsService.friends.first
    }

    private var canShareTrendSummary: Bool {
        !isShowingMock && selectedShareFriend != nil && !dataPoints.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("趋势")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                    .padding(.top, 4)

                    // Range Picker
                    Picker("范围", selection: $range) {
                        ForEach(TimeRange.allCases) { r in
                            Text(LocalizedStringKey(r.rawValue)).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)

                    TempoDataStateView(
                        state: dataState,
                        loadingTitle: "正在整理这段趋势",
                        emptyTitle: "这段时间还没有真实记录",
                        emptyDetail: "佩戴 Apple Watch 并保持健康数据授权，记录会自动出现在这里。",
                        cachedTitle: "部分指标沿用上次结果",
                        cachedDetailOverride: "本机健康记录暂时读取不完整，已保留当前可用图表。",
                        onRetry: { Task { await reloadTrendData() } }
                    )

                    if !isShowingMock {
                        HistorySourceCard(
                            label: dataSourceLabel,
                            detail: dataSourceDetail,
                            isMock: false
                        )

                        StressLoadOverviewCard(
                            summary: professionalSummary,
                            sourceLabel: dataSourceLabel
                        )

                        ProfessionalStressChartCard(
                            points: dataPoints,
                            buckets: stressBarBuckets,
                            rangeLabel: range.rawValue
                        )

                        VitalsBaselineCard(
                            hrvPoints: hrvTrendPoints,
                            rhrPoints: restingHeartRateHistory,
                            hrvBaseline: sleepHRVBaseline
                        )

                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showsAdvancedAnalysis.toggle()
                            }
                        } label: {
                            HStack {
                                Text("深入分析")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(TempoTheme.primaryText)
                                Spacer()
                                Text(LocalizedStringKey(showsAdvancedAnalysis ? "收起" : "查看"))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(TempoTheme.secondaryText)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(TempoTheme.tertiaryText)
                                    .rotationEffect(.degrees(showsAdvancedAnalysis ? 180 : 0))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white)
                            )
                        }
                        .buttonStyle(.tempoPress)

                        if showsAdvancedAnalysis {
                            HighStressEpisodesCard(
                                episodes: highStressEpisodes,
                                onSelect: { selectedEpisode = $0 }
                            )
                            VitalsStressRelationshipCard(relationship: vitalsRelationship)
                            StressRhythmHeatmapCard(cells: stressRhythmCells)
                            HistoryLevelDistributionCard(distribution: levelDistribution)
                        }

                        TrendSummaryShareCard(
                            friends: friendsService.friends,
                            selectedFriendID: $selectedShareFriendID,
                            rangeLabel: range.rawValue,
                            summary: professionalSummary,
                            dominantLevel: dominantStressLevel,
                            hrvText: trendHRVText,
                            distribution: levelDistribution,
                            episodeCount: highStressEpisodes.count,
                            canShare: canShareTrendSummary,
                            isSharing: isSharingTrend,
                            statusText: trendShareStatus,
                            onSend: { Task { await sendTrendSummaryToFriend() } },
                            onOpenSettings: {
                                NotificationCenter.default.post(name: .tempoOpenResonantSettings, object: nil, userInfo: [:])
                            }
                        )

                        Text("更多分析")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)

                        NavigationLink {
                            SleepInsightView()
                        } label: {
                            FactorRow(
                                icon: "moon.zzz.fill",
                                color: TempoTheme.accentLight,
                                title: "睡眠与压力",
                                subtitle: "查看睡眠与压力的变化",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.tempoPress)

                        Button {
                            showECG = true
                        } label: {
                            FactorRow(
                                icon: "waveform.path.ecg",
                                color: Color(hex: "EC4899"),
                                title: "ECG 与 HRV",
                                subtitle: "查看高分辨率心率变异性",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.tempoPress)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
        }
        .sheet(isPresented: $showECG) { ECGInsightView() }
        .sheet(isPresented: $showMentalHealth) { MentalHealthHubView() }
        .sheet(item: $selectedEpisode) { episode in
            NavigationStack {
                StressEpisodeDetailView(context: episodeDetailContext(for: episode))
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task(id: range) {
            await reloadTrendData()
        }
        .task {
            // sleep HRV 不依赖 range
            await loadSleepHRV()
        }
        .task {
            await loadTempoIndex()
        }
        .task {
            await loadFriendsForSharing()
        }
    }

    private func reloadTrendData() async {
        dataState = .loading
        trendShareStatus = nil
        var firstError: Error?

        do {
            try await loadRealData()
        } catch {
            firstError = error
        }
        do {
            try await loadVitalsHistory()
        } catch {
            firstError = firstError ?? error
        }

        let hasRealContent = swiftDataPoints != nil || (realData?.isEmpty == false)
        let hasVitals = !hrvHistory.isEmpty || !restingHeartRateHistory.isEmpty || !sleepHistory.isEmpty
        if let firstError {
            if hasRealContent || hasVitals {
                dataState = .cached(nil)
            } else if TempoErrorCopy.representsNoData(firstError) {
                dataState = .empty
            } else {
                dataState = .failed(TempoErrorCopy.message(for: firstError))
            }
        } else {
            dataState = hasRealContent || hasVitals ? .ready(.now) : .empty
        }
    }

    private func loadRealData() async throws {
        let total = Double(range.pointCount) * range.stride
        let readings = try await HealthKitService.shared.fetchRecentHeartRates(
            within: total,
            limit: range.pointCount * 4
        )
        guard !readings.isEmpty else {
            realData = []
            return
        }
        // 批量评分 — 取一次 baseline+stats+profile,对每个 reading 用 evaluator
        // 用 reading.timestamp 让 circadian 修正按真实时点生效
        let baseline = (try? await HealthKitService.shared.fetchPersonalBaseline()) ?? .default
        let stats = await StressBaselineService.shared.currentStats(container: nil)
        let profile = UserProfileStore.shared.current
        let circadianEnabled = PreferencesStore.shared.circadianEnabled
        let evaluator = StressEvaluator(baseline: baseline)
        let points: [StressDataPoint] = readings.map { reading in
            let score = evaluator.evaluate(
                heartRate: reading.bpm,
                hrv: nil,
                respiratoryRate: nil,
                stats: stats,
                hrvPhasic: nil,
                activityState: .resting,
                profile: profile,
                timestamp: reading.timestamp,
                circadianEnabled: circadianEnabled
            )
            return StressDataPoint(date: reading.timestamp, score: score.value)
        }.sorted { $0.date < $1.date }
        realData = points
    }

    private func loadVitalsHistory() async throws {
        let days = vitalsDaysBack(for: range)
        async let hrv = HealthKitService.shared.fetchDailyHRVHistory(daysBack: days)
        async let restingHR = HealthKitService.shared.fetchDailyRestingHeartRateHistory(daysBack: days)
        async let sleep = HealthKitService.shared.fetchSleepHistory(daysBack: days)
        let result = try await (hrv, restingHR, sleep)
        hrvHistory = result.0
        restingHeartRateHistory = result.1
        sleepHistory = result.2
    }

    private func loadSleepHRV() async {
        sleepHRV = try? await HealthKitService.shared.fetchOvernightHRV()
        let baseline = (try? await HealthKitService.shared.fetchPersonalBaseline()) ?? .default
        sleepHRVBaseline = baseline.averageHRV
    }

    private func loadTempoIndex() async {
        let r = await HealthKitService.shared.computeRecovery()
        let s = await HealthKitService.shared.computePersonalizedStrain()
        let hr = (try? await HealthKitService.shared.fetchLatestHeartRate()) ?? 0
        let hrv = try? await HealthKitService.shared.fetchLatestHRV()
        // 用今日所有 entry 的最近一条作为 stress;若无则跑一次 helper
        let stress: StressScore
        if let latest = stressEntries.first {
            stress = StressScore(value: latest.scoreValue, timestamp: latest.timestamp)
        } else {
            let evaluated = await HealthKitService.shared.evaluateCurrentStress(hr: hr, hrv: hrv)
            stress = evaluated.score
        }

        recovery = r
        strain = s
        tempoIndex = TempoIndex.compute(recovery: r, stress: stress, strain: s)
    }

    private func loadFriendsForSharing() async {
        await friendsService.refreshFriends()
        if selectedShareFriendID == nil {
            selectedShareFriendID = friendsService.friends.first?.id
        }
    }

    private func sendTrendSummaryToFriend() async {
        guard !isSharingTrend, canShareTrendSummary, let friend = selectedShareFriend else { return }
        isSharingTrend = true
        trendShareStatus = nil
        defer { isSharingTrend = false }

        do {
            try await friendsService.sendTrendSummary(to: friend, payload: trendSharePayload)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            trendShareStatus = "已发送给 \(friend.displayName)"
        } catch {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            trendShareStatus = "发送失败:\(error.localizedDescription)"
        }
    }

    private func vitalsDaysBack(for range: TimeRange) -> Int {
        switch range {
        case .day: 7
        case .week: 14
        case .month: 45
        case .year: 365
        }
    }

    private func aggregateStressBuckets(from points: [StressDataPoint]) -> [StressBarBucket] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { point in
            bucketStart(for: point.date, calendar: calendar)
        }
        return grouped.map { date, bucketPoints in
            let avg = bucketPoints.map(\.score).reduce(0, +) / max(bucketPoints.count, 1)
            return StressBarBucket(
                id: "\(Int(date.timeIntervalSince1970))",
                label: bucketLabel(for: date),
                date: date,
                average: avg
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func aggregateHeatmapCells(from points: [StressDataPoint]) -> [StressHeatmapCell] {
        let buckets = aggregateStressBuckets(from: points)
        let limited: [StressBarBucket]
        switch range {
        case .day:
            limited = Array(buckets.suffix(24))
        case .week:
            limited = Array(buckets.suffix(14))
        case .month:
            limited = Array(buckets.suffix(35))
        case .year:
            limited = Array(buckets.suffix(12))
        }
        return limited.map {
            StressHeatmapCell(
                id: $0.id,
                label: $0.label,
                average: $0.average,
                count: 1
            )
        }
    }

    private func aggregateRhythmCells(from points: [StressDataPoint]) -> [StressRhythmCell] {
        let calendar = Calendar.current
        let weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"]
        let timeLabels = ["0-4", "4-8", "8-12", "12-16", "16-20", "20-24"]
        let grouped = Dictionary(grouping: points) { point -> String in
            let weekday = calendar.component(.weekday, from: point.date) - 1
            let hour = calendar.component(.hour, from: point.date)
            let band = min(5, max(0, hour / 4))
            return "\(weekday).\(band)"
        }
        var cells: [StressRhythmCell] = []
        for band in 0..<6 {
            for weekday in 0..<7 {
                let values = grouped["\(weekday).\(band)"] ?? []
                let average: Int?
                if values.isEmpty {
                    average = nil
                } else {
                    average = values.map(\.score).reduce(0, +) / values.count
                }
                cells.append(StressRhythmCell(
                    weekdayIndex: weekday,
                    timeBandIndex: band,
                    weekdayLabel: weekdayLabels[weekday],
                    timeLabel: timeLabels[band],
                    average: average,
                    count: values.count
                ))
            }
        }
        return cells
    }

    private func makeHighStressEpisodes(from points: [StressDataPoint]) -> [StressEpisode] {
        let sorted = points.sorted { $0.date < $1.date }
        let interval = estimatedPointInterval
        let maxGap = max(interval * 2.5, 45 * 60)
        var episodes: [StressEpisode] = []
        var current: [StressDataPoint] = []

        func flushCurrent() {
            guard !current.isEmpty else { return }
            let values = current.map(\.score)
            let start = current.first?.date ?? Date()
            let end = (current.last?.date ?? start).addingTimeInterval(interval)
            let duration = max(Int(end.timeIntervalSince(start) / 60), Int(interval / 60))
            let average = values.reduce(0, +) / max(values.count, 1)
            let peak = values.max() ?? average
            episodes.append(StressEpisode(
                id: "\(Int(start.timeIntervalSince1970)).\(peak)",
                start: start,
                end: end,
                peak: peak,
                average: average,
                durationMinutes: duration
            ))
            current.removeAll()
        }

        for point in sorted {
            guard point.score >= 70 else {
                flushCurrent()
                continue
            }
            if let last = current.last, point.date.timeIntervalSince(last.date) > maxGap {
                flushCurrent()
            }
            current.append(point)
        }
        flushCurrent()
        return episodes
            .filter { $0.durationMinutes >= max(5, Int(interval / 60)) }
            .sorted {
                if $0.peak == $1.peak { return $0.durationMinutes > $1.durationMinutes }
                return $0.peak > $1.peak
            }
    }

    private func bucketStart(for date: Date, calendar: Calendar) -> Date {
        switch range {
        case .day:
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: comps) ?? date
        case .week, .month:
            return calendar.startOfDay(for: date)
        case .year:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? date
        }
    }

    private func bucketLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = TempoAppLanguage.currentLocale
        switch range {
        case .day:
            formatter.dateFormat = "H时"
        case .week:
            formatter.dateFormat = "E"
        case .month:
            formatter.dateFormat = "M/d"
        case .year:
            formatter.dateFormat = "M月"
        }
        return formatter.string(from: date)
    }

    private func dailyAverageHistory(from points: [HealthMetricHistoryPoint]) -> [HealthMetricHistoryPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
        return grouped.compactMap { date, values in
            guard !values.isEmpty else { return nil }
            let avg = values.map(\.value).reduce(0, +) / Double(values.count)
            return HealthMetricHistoryPoint(date: date, value: avg)
        }
        .sorted { $0.date < $1.date }
    }

    private func pearsonCorrelation(_ pairs: [(Double, Double)]) -> Double? {
        guard pairs.count >= 3 else { return nil }
        let xMean = pairs.map(\.0).reduce(0, +) / Double(pairs.count)
        let yMean = pairs.map(\.1).reduce(0, +) / Double(pairs.count)
        let numerator = pairs.reduce(0.0) { partial, pair in
            partial + (pair.0 - xMean) * (pair.1 - yMean)
        }
        let xEnergy = pairs.reduce(0.0) { $0 + pow($1.0 - xMean, 2) }
        let yEnergy = pairs.reduce(0.0) { $0 + pow($1.1 - yMean, 2) }
        let denominator = sqrt(xEnergy * yEnergy)
        guard denominator > 0 else { return nil }
        return max(-1, min(1, numerator / denominator))
    }

    private func episodeDetailContext(for episode: StressEpisode) -> StressEpisodeDetailContext {
        let calendar = Calendar.current
        let windowStart = episode.start.addingTimeInterval(-90 * 60)
        let windowEnd = episode.end.addingTimeInterval(90 * 60)
        let beforeStart = episode.start.addingTimeInterval(-60 * 60)
        let afterEnd = episode.end.addingTimeInterval(60 * 60)
        let sortedPoints = dataPoints.sorted { $0.date < $1.date }
        let windowPoints = sortedPoints.filter { $0.date >= windowStart && $0.date <= windowEnd }
        let beforePoints = sortedPoints.filter { $0.date >= beforeStart && $0.date < episode.start }
        let afterPoints = sortedPoints.filter { $0.date > episode.end && $0.date <= afterEnd }

        let dayHRV = dailyAverageHistory(from: hrvTrendPoints).first {
            calendar.isDate($0.date, inSameDayAs: episode.start)
        }?.value
        let dayRHR = dailyAverageHistory(from: restingHeartRateHistory).first {
            calendar.isDate($0.date, inSameDayAs: episode.start)
        }?.value
        let priorSleep = sleepHistory.last {
            let sleepDay = calendar.startOfDay(for: $0.date)
            return sleepDay <= calendar.startOfDay(for: episode.start)
        }

        let episodeEntries = rangedEntries.filter {
            $0.timestamp >= episode.start && $0.timestamp <= episode.end
        }

        return StressEpisodeDetailContext(
            episode: episode,
            windowPoints: windowPoints,
            beforeAverage: averageScore(beforePoints),
            afterAverage: averageScore(afterPoints),
            dailyHRV: dayHRV,
            hrvBaseline: sleepHRVBaseline,
            dailyRestingHeartRate: dayRHR,
            sleepHours: priorSleep?.totalHours,
            deepSleepHours: priorSleep?.deepHours,
            remSleepHours: priorSleep?.remHours,
            activityLabel: dominantActivityLabel(in: episodeEntries),
            sourceLabel: dataSourceLabel,
            dataConfidence: dataConfidence
        )
    }

    private func averageScore(_ points: [StressDataPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.map(\.score).reduce(0, +) / points.count
    }

    private func dominantActivityLabel(in entries: [StressEntry]) -> String {
        let states = entries.compactMap(\.activityState)
        guard !states.isEmpty else { return "活动状态未记录" }
        let grouped = Dictionary(grouping: states, by: { $0 })
        return grouped.max { $0.value.count < $1.value.count }?.key.displayName ?? "活动状态未记录"
    }
}

// MARK: - Mock Data

struct StressDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Int
}

enum MockStressData {
    static func generate(range: HistoryView.TimeRange) -> [StressDataPoint] {
        let now = Date()
        let count = range.pointCount
        let stride = range.stride
        var generator = SystemRandomNumberGenerator()

        return (0..<count).map { i in
            let date = now.addingTimeInterval(-Double(count - i) * stride)
            let hourOfDay = Calendar.current.component(.hour, from: date)
            let baseline = circadianBaseline(forHour: hourOfDay)
            let noise = Int.random(in: -8...8, using: &generator)
            let score = max(0, min(100, baseline + noise))
            return StressDataPoint(date: date, score: score)
        }
    }

    private static func circadianBaseline(forHour hour: Int) -> Int {
        switch hour {
        case 0..<6: 28
        case 6..<8: 38
        case 8..<11: 55
        case 11..<14: 60
        case 14..<18: 72
        case 18..<21: 55
        case 21..<24: 38
        default: 32
        }
    }
}

// MARK: - Trends Subviews

struct BigChartCard: View {
    let dataPoints: [StressDataPoint]
    let peakLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("压力曲线")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(LocalizedStringKey(peakLabel))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer()
                Text("详情")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TempoTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(TempoTheme.accentSoft))
            }

            chart
                .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 22, padding: 18)
    }

    private var chart: some View {
        Chart(dataPoints) { point in
            AreaMark(
                x: .value("时间", point.date),
                y: .value("压力", point.score)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [TempoTheme.accent.opacity(0.30), TempoTheme.accent.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("时间", point.date),
                y: .value("压力", point.score)
            )
            .foregroundStyle(TempoTheme.accent)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.2))
                AxisValueLabel()
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(TempoTheme.tertiaryText.opacity(0.15))
                AxisValueLabel()
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
        }
    }
}

struct StatRoundedCard: View {
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
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(LocalizedStringKey(unit))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 22, padding: 18)
    }
}

struct FactorRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 14) {
            SoftIconBubble(systemName: icon, color: color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }
}

struct MockHintCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(TempoTheme.accent)
                .font(.system(size: 16))
            Text("当前显示模拟数据。配对 Apple Watch 后会自动替换为真实历史。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .tempoCard(radius: 16, padding: 14)
    }
}

#Preview {
    HistoryView()
}
