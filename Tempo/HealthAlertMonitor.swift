//
//  HealthAlertMonitor.swift
//  Tempo
//
//  评估当前 metric 数据是否触发告警 — 持续时长判定 + cooldown,
//  触发时调 FriendsService.writeHealthAlert(metric, severity),不传数值.
//

import Foundation
import TempoCore

@MainActor
final class HealthAlertMonitor {
    static let shared = HealthAlertMonitor()

    /// metric → 首次进入"超阈值"状态的时间.nil = 当前正常.
    private var violationStart: [HealthAlertMetric: Date] = [:]

    /// metric → 上次成功 trigger alert 的时间.
    private var lastAlertSent: [HealthAlertMetric: Date] = [:]

    /// 同一 metric 重发冷却时间 — 30 分钟内不重复发,避免轰炸朋友
    private let resendCooldown: TimeInterval = 1800

    private init() {}

    /// 评估一个新的 metric 数据点.
    /// - Parameters:
    ///   - metric: alert 类型
    ///   - value: 当前值(原始值 — bpm / % 等)
    ///
    /// 调用时机:每次 HealthKit 拿到新 HR / SpO2 数据时.
    func evaluate(metric: HealthAlertMetric, value: Double) async {
        let settings = AlertSettings.shared
        guard settings.isEnabled(metric) else {
            // 用户没开这个 alert — 重置状态
            violationStart[metric] = nil
            return
        }

        // 心率告警:运动 / 走路时 HR 偏高是正常的,跳过(否则跑步 = 误报)
        // SpO2 告警不跳过(运动也不该 < 92%)
        if metric == .heartRateHigh || metric == .heartRateLow {
            let activity = await MotionActivityDetector.shared.currentActivity()
            if activity == .exercising || activity == .active {
                violationStart[metric] = nil
                return
            }
        }

        let threshold = settings.threshold(for: metric)
        let inViolation = metric.triggersWhenAbove ? value > threshold : value < threshold

        if inViolation {
            if violationStart[metric] == nil {
                violationStart[metric] = Date()
                return
            }
            let sustained = Date().timeIntervalSince(violationStart[metric] ?? Date())
            if sustained < metric.sustainedDuration { return }

            // Cooldown 检查
            if let last = lastAlertSent[metric], Date().timeIntervalSince(last) < resendCooldown {
                return
            }

            let severity = metric.severity(forValue: value, threshold: threshold)
            await FriendsService.shared.writeHealthAlert(metric: metric, severity: severity)
            lastAlertSent[metric] = Date()
        } else {
            // 回到正常区间 — 清掉 violation,如果之前 trigger 过 → clear share
            if violationStart[metric] != nil {
                violationStart[metric] = nil
                if lastAlertSent[metric] != nil {
                    await FriendsService.shared.clearHealthAlert(metric: metric)
                    lastAlertSent[metric] = nil
                }
            }
        }
    }

    /// 一次评估所有启用的 metric — 对外简化入口.
    /// 调用方:每次 stress 数据更新时都调一下.
    func evaluateAll(heartRate: Double?, spo2Percent: Double?) async {
        if let hr = heartRate {
            await evaluate(metric: .heartRateHigh, value: hr)
            await evaluate(metric: .heartRateLow, value: hr)
        }
        if let spo2 = spo2Percent {
            await evaluate(metric: .spo2Low, value: spo2)
        }
    }

    /// 设置变更时,重置所有缓存状态(避免开关 toggle 后状态不一致)
    func resetAll() {
        violationStart.removeAll()
        lastAlertSent.removeAll()
    }
}
