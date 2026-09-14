//
//  TodayMindfulCache.swift
//  Tempo
//
//  「我今天做过呼吸 / 冥想没?」的中央缓存。
//  之前是 placeholder 直接查 UserDefaults 单时间戳,现在补真实 HK 查询:
//   - UserDefaults `lastMindfulCompletedAt`:快路径,BreathingSession / MeditationSession
//     完成时主动写,几乎所有「今天做过」case 都靠它命中
//   - HK fallback:用户可能从 Apple Mindfulness / 第三方 App 写入 mindfulSession,
//     UserDefaults 不会有记录 — 这时 fallback 查 HK 今天的 sessions 数
//

import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class TodayMindfulCache {
    static let shared = TodayMindfulCache()

    /// 用户今天是否做过呼吸 / 冥想(任何来源)
    private(set) var didLogToday: Bool = false
    /// 今天 mindful 总分钟数(用于 AI Coach 等场景)
    private(set) var todayMinutes: Int = 0
    private(set) var lastRefreshed: Date = .distantPast

    private let healthStore = HKHealthStore()
    private let refreshInterval: TimeInterval = 600   // 10min 内不重复查

    private init() {}

    /// 主入口 — view .task 中调用或 session 完成后调用
    func refresh(force: Bool = false) async {
        if !force, Date().timeIntervalSince(lastRefreshed) < refreshInterval { return }

        // 1) 快路径:UserDefaults 时间戳
        let last = UserDefaults.standard.double(forKey: "lastMindfulCompletedAt")
        let cal = Calendar.current
        if last > 0, cal.isDateInToday(Date(timeIntervalSince1970: last)) {
            didLogToday = true
            // 这条快路径不知道总分钟数,留给 HK 查询填
        }

        // 2) HK fallback / 补 minutes
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            lastRefreshed = Date()
            return
        }
        let startOfDay = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(q)
        }

        let totalSec = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        todayMinutes = Int((totalSec / 60).rounded())
        if totalSec > 0 {
            didLogToday = true
        }
        lastRefreshed = Date()
    }

    /// Session 完成时主动调,强制刷新 + 标记今天有
    func markCompletedNow(minutes: Int) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastMindfulCompletedAt")
        didLogToday = true
        todayMinutes += max(0, minutes)
        lastRefreshed = Date()
    }
}
