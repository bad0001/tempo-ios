//
//  AlertSettings.swift
//  Tempo
//
//  共振关怀的告警分享 + 自定义共享配置.持久化到 UserDefaults.
//  默认全部 OFF — 用户必须显式 opt-in,符合 Apple App Store 5.1.3 健康数据共享要求.
//

import Foundation
import Observation
import TempoCore

@MainActor
@Observable
final class AlertSettings {
    static let shared = AlertSettings()

    // MARK: - Per-metric enable + threshold

    private struct PerMetricKeys {
        static func enabled(_ m: HealthAlertMetric) -> String { "alert.\(m.rawValue).enabled" }
        static func threshold(_ m: HealthAlertMetric) -> String { "alert.\(m.rawValue).threshold" }
    }

    func isEnabled(_ metric: HealthAlertMetric) -> Bool {
        UserDefaults.standard.bool(forKey: PerMetricKeys.enabled(metric))
    }

    func setEnabled(_ enabled: Bool, for metric: HealthAlertMetric) {
        UserDefaults.standard.set(enabled, forKey: PerMetricKeys.enabled(metric))
        HealthAlertMonitor.shared.resetAll()
        bumpVersion()
    }

    func threshold(for metric: HealthAlertMetric) -> Double {
        let key = PerMetricKeys.threshold(metric)
        if UserDefaults.standard.object(forKey: key) == nil {
            return metric.defaultThreshold
        }
        return UserDefaults.standard.double(forKey: key)
    }

    func setThreshold(_ value: Double, for metric: HealthAlertMetric) {
        UserDefaults.standard.set(value, forKey: PerMetricKeys.threshold(metric))
        HealthAlertMonitor.shared.resetAll()
        bumpVersion()
    }

    /// 任何 alert 是否启用 — 决定 HealthKit observer 是否要启动
    var anyAlertEnabled: Bool {
        HealthAlertMetric.allCases.contains { isEnabled($0) }
    }

    // MARK: - Pause sharing

    private static let pauseKey = "sharing.pauseUntil"

    /// 暂停共享到这个时间为止.nil = 没有暂停.
    var pauseUntil: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: Self.pauseKey)
            guard ts > 0 else { return nil }
            let date = Date(timeIntervalSince1970: ts)
            return date > Date() ? date : nil
        }
        set {
            if let d = newValue {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Self.pauseKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pauseKey)
            }
            bumpVersion()
        }
    }

    /// 是否在暂停状态
    var isPaused: Bool { pauseUntil != nil }

    func pauseSharing(forSeconds seconds: TimeInterval) {
        pauseUntil = Date().addingTimeInterval(seconds)
    }

    func resumeSharing() {
        pauseUntil = nil
    }

    // MARK: - Stress 最低同步阈值

    private static let minStressKey = "sharing.minStressScore"

    /// 只有 stress score 大于这个才同步给好友.0 = 全传(默认).
    var minStressScore: Int {
        get { UserDefaults.standard.integer(forKey: Self.minStressKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.minStressKey)
            bumpVersion()
        }
    }

    // MARK: - Recommended threshold(基于 UserProfile + HealthKit RHR 推算)

    /// 给当前 metric 推荐一个个性化阈值。
    /// - 高心率: max(95, min(140, RHR + 30 - condition adjustments))
    /// - 低心率: max(40, min(60, RHR - 15 - 老年微调))
    /// - SpO2:    age>60 → 90,否则 92
    func recommendedThreshold(for metric: HealthAlertMetric) async -> Double {
        let profile = UserProfileStore.shared.current
        let rhr: Double = (try? await HealthKitService.shared.fetchLatestRestingHeartRate())
            ?? 65

        switch metric {
        case .heartRateHigh:
            var t = rhr + 30
            if profile.conditions.contains("arrhythmia") { t -= 10 }
            if profile.conditions.contains("hypertension") { t -= 5 }
            if profile.isPregnant { t += 20 }
            return max(95, min(140, t))

        case .heartRateLow:
            var t = rhr - 15
            if profile.age > 60 { t -= 5 }
            if profile.conditions.contains("arrhythmia") { t += 5 }   // 心律不齐谨慎放宽下限
            return max(40, min(60, t))

        case .spo2Low:
            return profile.age > 60 ? 90 : 92
        }
    }

    /// 判断当前用户设置的阈值是否与推荐值差距明显(>5 / >2),需要在 UI banner 提醒
    func shouldSuggestRecommended(for metric: HealthAlertMetric) async -> (current: Double, recommended: Double, delta: Double)? {
        let current = threshold(for: metric)
        let recommended = await recommendedThreshold(for: metric)
        let delta = abs(current - recommended)
        let trigger: Double
        switch metric {
        case .heartRateHigh, .heartRateLow: trigger = 5
        case .spo2Low: trigger = 1.5
        }
        guard delta >= trigger else { return nil }
        return (current, recommended, delta)
    }

    /// 应用推荐阈值
    func applyRecommendedThreshold(for metric: HealthAlertMetric) async {
        let recommended = await recommendedThreshold(for: metric)
        setThreshold(recommended, for: metric)
    }

    // MARK: - Observation trigger

    /// 用一个 dummy 字段触发 @Observable 通知 — 上面 UserDefaults 改了不会自动触发
    private(set) var version: Int = 0

    private func bumpVersion() {
        version &+= 1
    }
}
