//
//  HRVPhasic.swift
//  TempoCore
//
//  Tonic-Phasic HRV 拆解 —
//  - Tonic = 14 天 baseline,反映长期适应水平
//  - Phasic = 最近 1h 相对 tonic 的偏离,反映急性压力 / 急性放松
//
//  Apple HealthKit 不提供 RR interval / RMSSD / LF-HF,所以这是
//  在 SDNN 上能做到的最接近「实时 HRV biofeedback」的指标。
//

import Foundation

public struct HRVPhasic: Codable, Hashable, Sendable {
    /// 最近 60min HRV 均值 (ms)
    public let recent60minMean: Double
    /// 14 天 tonic baseline (ms)
    public let tonicBaseline: Double
    /// recent / tonic — 1.0 = 与基线一致
    public let ratio: Double
    /// 用了多少个最近样本算 phasic
    public let recentSampleCount: Int
    public let computedAt: Date

    public init(
        recent60minMean: Double,
        tonicBaseline: Double,
        recentSampleCount: Int,
        computedAt: Date = .now
    ) {
        self.recent60minMean = recent60minMean
        self.tonicBaseline = tonicBaseline
        self.ratio = tonicBaseline > 0 ? recent60minMean / tonicBaseline : 1.0
        self.recentSampleCount = recentSampleCount
        self.computedAt = computedAt
    }

    /// 急性应激:phasic 较 tonic 下降 30%+,说明短时 HRV 显著下降 = 急性紧张
    public var isAcuteStress: Bool {
        recentSampleCount >= 2 && tonicBaseline > 0 && ratio < 0.7
    }

    /// 急性放松:phasic 较 tonic 上升 30%+,说明短时 HRV 显著上升 = 急性放松(冥想 / 深呼吸生效)
    public var isAcuteCalm: Bool {
        recentSampleCount >= 2 && tonicBaseline > 0 && ratio > 1.3
    }

    /// 信度判断 — 样本数太少不计入
    public var isConfident: Bool {
        recentSampleCount >= 2 && tonicBaseline > 0 && recent60minMean > 0
    }

    /// 应加到 stress score 的修正分(±10 上限,避免抢主算法风头)
    /// 急性应激 → +5 ~ +10,急性放松 → -3 ~ -6
    public var stressAdjustment: Double {
        guard isConfident else { return 0 }
        if isAcuteStress {
            // ratio 0.7 → 0,ratio 0.5 → +10
            let severity = max(0, min(1, (0.7 - ratio) / 0.2))
            return severity * 10
        }
        if isAcuteCalm {
            let severity = max(0, min(1, (ratio - 1.3) / 0.3))
            return -severity * 6
        }
        return 0
    }

    public static let unknown = HRVPhasic(
        recent60minMean: 0,
        tonicBaseline: 0,
        recentSampleCount: 0
    )
}
