//
//  StressEvaluator.swift
//  TempoCore
//
//  v2 算法主入口。优先级:
//    1. 有 BaselineStats(.isConfident)  → 滑动 z-score(更稳)
//    2. 否则 → 老 PersonalBaseline 线性加权(冷启动 fallback)
//
//  额外维度(可选,数据缺失时 0 影响):
//    - hrvPhasic 急性应激修正 ±10
//    - circadian 节律修正 ±5
//    - activityState 运动 / 睡眠 / 静息差异化基线减分
//

import Foundation

public struct StressEvaluator: Sendable {
    public let baseline: PersonalBaseline

    public init(baseline: PersonalBaseline = .default) {
        self.baseline = baseline
    }

    // MARK: - v2 main entry

    /// v2 评估,所有可选维度都允许 nil → 优雅降级。
    /// - Parameters:
    ///   - heartRate: 当前 HR (bpm)
    ///   - hrv: 当前 HRV SDNN (ms),可选
    ///   - respiratoryRate: 当前呼吸频率 (次/min),可选
    ///   - stats: 28 天滑动 BaselineStats,可选,nil 或低 confidence 时 fallback v1 算法
    ///   - hrvPhasic: 60min vs 14d phasic 偏移,可选
    ///   - activityState: 运动状态,默认 resting
    ///   - profile: 用户画像(年龄等),可选,目前 evaluator 不直接用,留接口给 Strain
    ///   - timestamp: 评估时刻,用于 circadian 修正
    ///   - circadianEnabled: 是否启用节律修正
    public func evaluate(
        heartRate: Double,
        hrv: Double? = nil,
        respiratoryRate: Double? = nil,
        stats: BaselineStats? = nil,
        hrvPhasic: HRVPhasic? = nil,
        activityState: ActivityState = .resting,
        profile: UserProfile? = nil,
        timestamp: Date = .now,
        circadianEnabled: Bool = true
    ) -> StressScore {
        _ = profile  // 预留;profile 目前由 Strain 使用,evaluator 不直接消费

        var score: Double = 50

        // ===== 主分:z-score(可信)或线性 fallback(冷启动) =====
        if let stats, stats.isConfident, heartRate > 0 {
            // v2 z-score 路径
            let zHR = stats.hrZScore(heartRate)
            score += min(40, max(-25, zHR * 7))   // ±1σ ≈ ±7 分,±2σ ≈ ±14 分

            if let hrv {
                // HRV 越低越紧张:取负 z
                let zHRV = stats.hrvZScore(hrv)
                score += min(20, max(-30, -zHRV * 6))
            }

            if let rr = respiratoryRate, rr > 0 {
                let zRR = stats.rrZScore(rr)
                score += min(15, max(-10, zRR * 4))
            }
        } else {
            // v1 fallback — 与历史完全一致,保证冷启动可用
            if heartRate > 0, baseline.restingHeartRate > 0 {
                let hrDelta = heartRate - baseline.restingHeartRate
                score += min(40, max(-25, hrDelta * 0.8))
            }

            if let hrv, baseline.averageHRV > 0 {
                let hrvDelta = baseline.averageHRV - hrv
                score += min(30, max(-20, hrvDelta * 0.5))
            }

            if let rr = respiratoryRate, rr > 0 {
                let rrDelta = rr - 14
                score += min(15, max(-10, rrDelta * 1.5))
            }
        }

        // ===== 加分项:phasic HRV 急性偏移 =====
        if let hrvPhasic {
            score += hrvPhasic.stressAdjustment
        }

        // ===== 加分项:circadian 节律修正 =====
        if circadianEnabled {
            score += CircadianAdjustment.adjustment(for: timestamp)
        }

        // ===== 活动状态差异化基线减分(原 v1 逻辑,保留) =====
        switch activityState {
        case .resting: break
        case .active: score -= 12
        case .exercising: score = max(score - 35, 0)
        case .sleeping: score = max(score - 22, 0)
        }

        return StressScore(value: Int(score.rounded()), timestamp: timestamp)
    }

    // MARK: - v1 backward-compat overload

    /// 老调用方兼容:不传 stats / phasic / profile,内部 fallback v1 算法。
    /// 新代码不要用这个,用上面的完整版。
    @available(*, deprecated, message: "Use evaluate(heartRate:hrv:respiratoryRate:stats:hrvPhasic:activityState:profile:timestamp:circadianEnabled:)")
    public func evaluate(
        heartRate: Double,
        hrv: Double?,
        respiratoryRate: Double?,
        activityState: ActivityState
    ) -> StressScore {
        evaluate(
            heartRate: heartRate,
            hrv: hrv,
            respiratoryRate: respiratoryRate,
            stats: nil,
            hrvPhasic: nil,
            activityState: activityState,
            profile: nil,
            timestamp: .now,
            circadianEnabled: false  // 老接口不引入新行为
        )
    }
}

public struct PersonalBaseline: Codable, Hashable, Sendable {
    public let restingHeartRate: Double
    public let averageHRV: Double
    public let updated: Date

    public init(restingHeartRate: Double, averageHRV: Double, updated: Date = .now) {
        self.restingHeartRate = restingHeartRate
        self.averageHRV = averageHRV
        self.updated = updated
    }

    public static let `default` = PersonalBaseline(
        restingHeartRate: 60,
        averageHRV: 50
    )
}

public enum ActivityState: String, Codable, Sendable, CaseIterable {
    case resting
    case active
    case exercising
    case sleeping

    public var displayName: String {
        switch self {
        case .resting: "静息"
        case .active: "轻度活动"
        case .exercising: "运动中"
        case .sleeping: "睡眠中"
        }
    }
}
