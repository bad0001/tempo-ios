//
//  HomeView.swift
//  Tempo
//
//  首页主流程:压力总览、密友提醒、今日行动和 HealthKit 刷新。
//

import Foundation
import SwiftUI
import SwiftData
import TempoCore

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var hrState = PhoneSessionManager.shared.state
    @State private var baseline: PersonalBaseline = .default
    @State private var latestHRV: Double?
    @State private var hkLatestHeartRate: Double?
    @State private var hkRestingHeartRate: Double?
    @State private var overnightHRV: Double?
    @State private var recovery: Recovery = .unknown
    @State private var strain: Strain = .none
    @State private var liveStressScore: StressScore?
    @State private var dataState: TempoLoadState = .idle
    @AppStorage("user.musicTriggerThreshold") private var musicTriggerThreshold: Double = 70

    /// Watch App 实时推送优先,否则 fallback 到 HealthKit 任意源最近心率。
    private var effectiveHeartRate: Double {
        if hrState.bpm > 0 { return hrState.bpm }
        return hkLatestHeartRate ?? 0
    }

    /// v2 算法在 loadHKData 里异步算好,view 直接读
    private var stressScore: StressScore? {
        liveStressScore
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    GreetingHeader()
                        .padding(.top, 4)

                    TempoDataStateView(
                        state: dataState,
                        loadingTitle: "正在读取本机健康记录",
                        emptyTitle: "还没有可计算的健康数据",
                        emptyDetail: "确认已允许 Tempo 读取 Apple 健康，并佩戴 Apple Watch 产生心率或 HRV 数据。",
                        cachedTitle: "正在显示本机保存的健康摘要",
                        cachedDetailOverride: "新的健康数据暂时不可用，当前数值来自上次成功读取。",
                        showsEmpty: false,
                        onRetry: { Task { await loadHKData() } }
                    )

                    StressCommandCenter(
                        score: stressScore,
                        heartRate: effectiveHeartRate,
                        hrv: latestHRV,
                        recovery: recovery,
                        strain: strain
                    )

                    PendingFriendRequestBanner()

                    ResonantBuddiesBar()

                    HomeBaselineStrip(
                        restingHeartRate: hkRestingHeartRate,
                        overnightHRV: overnightHRV
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        NowPlayingHeroCard(
                            heartRate: effectiveHeartRate,
                            isElevated: (stressScore?.value).map { Double($0) >= musicTriggerThreshold } ?? false,
                            currentStress: stressScore?.value
                        )

                        MoodCard()
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .refreshable {
                await loadHKData()
            }
        }
        .task {
            await loadHKData()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await loadHKData()
            }
        }
    }

    private func loadHKData() async {
        let alreadyHasContent = effectiveHeartRate > 0
            || latestHRV != nil
            || hkRestingHeartRate != nil
            || overnightHRV != nil
            || liveStressScore != nil
        var usedCachedSnapshot = false
        if dataState == .idle, let cached = HomeHealthSnapshotCache.read() {
            applyCachedSnapshot(cached)
            dataState = .cached(cached.updatedAt)
            usedCachedSnapshot = true
        }
        if !usedCachedSnapshot && !alreadyHasContent {
            dataState = .loading
        }

        var completedQueries = 0
        var firstError: Error?

        do {
            baseline = try await HealthKitService.shared.fetchPersonalBaseline()
            completedQueries += 1
        } catch {
            firstError = firstError ?? error
        }
        do {
            latestHRV = try await HealthKitService.shared.fetchLatestHRV()
            completedQueries += 1
        } catch {
            firstError = firstError ?? error
        }
        do {
            hkLatestHeartRate = try await HealthKitService.shared.fetchLatestHeartRate()
            completedQueries += 1
        } catch {
            firstError = firstError ?? error
        }
        do {
            hkRestingHeartRate = try await HealthKitService.shared.fetchLatestRestingHeartRate()
            completedQueries += 1
        } catch {
            firstError = firstError ?? error
        }
        do {
            overnightHRV = try await HealthKitService.shared.fetchOvernightHRV()
            completedQueries += 1
        } catch {
            firstError = firstError ?? error
        }

        let r = await HealthKitService.shared.computeRecovery()
        let s = await HealthKitService.shared.computePersonalizedStrain()
        recovery = r
        strain = s

        // 写入 UserDefaults 给节奏唤醒文案用。
        if let latestHRV {
            UserDefaults.standard.set(latestHRV, forKey: "latest.overnightHRV")
        }
        UserDefaults.standard.set(baseline.averageHRV, forKey: "baseline.averageHRV")

        // v2 helper:统一注入 baseline + stats + phasic + circadian + activity
        let shareHeartRate = hrState.bpm > 0 ? hrState.bpm : (hkLatestHeartRate ?? 0)
        if shareHeartRate > 0 || latestHRV != nil {
            let evaluated = await HealthKitService.shared.evaluateCurrentStress(
                hr: shareHeartRate,
                hrv: latestHRV,
                container: modelContext.container
            )
            liveStressScore = evaluated.score
            await FriendsService.shared.updateMyStress(
                score: evaluated.value,
                level: evaluated.level.rawValue
            )
        } else if let latestEntry = latestStoredStressEntry() {
            liveStressScore = StressScore(value: latestEntry.scoreValue, timestamp: latestEntry.timestamp)
            await FriendsService.shared.updateMyStress(score: latestEntry.scoreValue, level: latestEntry.levelRaw)
        } else {
            liveStressScore = nil
        }

        let hasHealthContent = effectiveHeartRate > 0
            || latestHRV != nil
            || hkRestingHeartRate != nil
            || overnightHRV != nil
            || liveStressScore != nil
        if let firstError {
            if hasHealthContent {
                dataState = .cached(HomeHealthSnapshotCache.read()?.updatedAt)
            } else if TempoErrorCopy.representsNoData(firstError) {
                dataState = .empty
            } else {
                dataState = .failed(TempoErrorCopy.message(
                    for: firstError,
                    fallback: "请检查 Apple 健康读取权限后重试。"
                ))
            }
        } else if completedQueries > 0 {
            let now = Date()
            dataState = hasHealthContent ? .ready(now) : .empty
            if hasHealthContent {
                HomeHealthSnapshotCache.write(
                    HomeHealthSnapshotCache(
                        latestHRV: latestHRV,
                        latestHeartRate: hkLatestHeartRate,
                        restingHeartRate: hkRestingHeartRate,
                        overnightHRV: overnightHRV,
                        stressValue: liveStressScore?.value,
                        stressTimestamp: liveStressScore?.timestamp,
                        updatedAt: now
                    )
                )
            }
        } else if hasHealthContent {
            dataState = .cached(HomeHealthSnapshotCache.read()?.updatedAt)
        } else {
            dataState = .failed(
                "请检查 Apple 健康读取权限后重试。"
            )
        }

        // 关系数据失败不影响本机健康卡，单独由共振页展示离线状态。
        await FriendsService.shared.refreshFriends()
        await FriendsService.shared.loadEncourages()
        await FriendsService.shared.loadResonantEvents()

        // Phone → Watch:健康指标与最新未读关怀一起推，避免手表拿到半成品快照。
        pushWatchSnapshot()
    }

    private func applyCachedSnapshot(_ cached: HomeHealthSnapshotCache) {
        latestHRV = cached.latestHRV
        hkLatestHeartRate = cached.latestHeartRate
        hkRestingHeartRate = cached.restingHeartRate
        overnightHRV = cached.overnightHRV
        if let value = cached.stressValue {
            liveStressScore = StressScore(value: value, timestamp: cached.stressTimestamp ?? cached.updatedAt)
        }
    }

    /// 把当前所有派生指标打包推到 Watch。
    /// 不一定每次都推(WC 有节流),用 updateApplicationContext 后到覆盖先到。
    private func pushWatchSnapshot() {
        let snapshot = WatchSnapshot(
            stressValue: liveStressScore?.value,
            stressLevelRaw: liveStressScore?.level.rawValue,
            recoveryValue: recovery.hasEnoughData ? recovery.value : nil,
            recoveryLevelRaw: recovery.hasEnoughData ? recovery.level.rawValue : nil,
            recoveryHasElevatedTemp: recovery.hasElevatedTemp,
            strainValue: strain.value > 0 ? strain.value : nil,
            strainLevelRaw: strain.value > 0 ? strain.level.rawValue : nil,
            latestHR: effectiveHeartRate > 0 ? effectiveHeartRate : nil,
            latestHRV: latestHRV,
            restingHR: hkRestingHeartRate,
            deepSleepHours: recovery.sleepStages?.deep,
            remSleepHours: recovery.sleepStages?.rem,
            totalAsleepHours: recovery.sleepStages?.totalAsleepHours,
            wristTempZScore: recovery.wristTempZScore,
            careSignal: FriendsService.shared.latestUnreadWatchCareSignal,
            algorithmVersion: AlgorithmVersion.current,
            updatedAt: .now
        )
        PhoneSessionManager.shared.pushSnapshotToWatch(snapshot)
    }

    private func latestStoredStressEntry() -> StressEntry? {
        var descriptor = FetchDescriptor<StressEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

}

private struct HomeHealthSnapshotCache: Codable {
    let latestHRV: Double?
    let latestHeartRate: Double?
    let restingHeartRate: Double?
    let overnightHRV: Double?
    let stressValue: Int?
    let stressTimestamp: Date?
    let updatedAt: Date

    private static let key = "home.healthSnapshot.v1"

    static func read() -> HomeHealthSnapshotCache? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HomeHealthSnapshotCache.self, from: data)
    }

    static func write(_ snapshot: HomeHealthSnapshotCache) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct HomeBaselineStrip: View {
    let restingHeartRate: Double?
    let overnightHRV: Double?

    @Environment(\.switchToTab) private var switchToTab
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            switchToTab(.trends)
        } label: {
            HStack(spacing: 14) {
                SoftIconBubble(systemName: "heart.text.square.fill", color: TempoTheme.accent, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("今日身体基线")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("静息心率和夜间 HRV,详细变化去趋势页看")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 4)

                baselineValue(
                    value: restingHeartRate.map { "\(Int($0))" } ?? "—",
                    unit: "bpm",
                    color: Color.pink
                )
                baselineValue(
                    value: overnightHRV.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "ms",
                    color: TempoTheme.success
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .tempoCard(radius: 18, padding: 14)
        }
        .buttonStyle(.tempoPress)
        .accessibilityLabel("今日身体基线,静息心率 \(restingHeartRate.map { "\(Int($0))" } ?? unavailableText),夜间 HRV \(overnightHRV.map { String(format: "%.0f", $0) } ?? unavailableText)")
        .accessibilityHint("打开趋势页查看详细变化")
    }

    private func baselineValue(value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .frame(minWidth: 34, alignment: .trailing)
    }

    private var unavailableText: String {
        locale.tempoUsesEnglish ? "not available" : "暂无"
    }
}
