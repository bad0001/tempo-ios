//
//  WristTempStats.swift
//  TempoCore
//
//  Apple Watch Series 8+ / Ultra 提供 appleSleepingWristTemperature
//  (相对基线的体温偏移 °C),不是绝对体温。Apple 自己也是用 5 晚 baseline 后
//  显示「deviation from baseline」。
//
//  我们把它接入 Recovery:体温显著偏高 → 可能感染 / 过劳 → 扣分。
//  Oura 用了相同思路,且对女性周期监测和早期发烧识别非常有效。
//
//  学术依据: Smarr et al. 2020 Sci Rep,周期 / 感染前夕皮温偏高
//

import Foundation

public struct WristTempStats: Codable, Hashable, Sendable {
    /// 昨晚的体温偏差(相对基线,°C)。Apple HK 已经返回 deviation,但我们这里
    /// 再做一次自己的 z-score 用 14d 自己滑动统计 → 更稳。
    public let lastNightDeviationC: Double?
    /// 14 天 baseline 均值(°C 偏移)
    public let baselineMean: Double
    /// 14 天 baseline 标准差(°C)
    public let baselineStddev: Double
    /// 用于算 baseline 的样本数
    public let sampleCount: Int
    public let computedAt: Date

    public init(
        lastNightDeviationC: Double?,
        baselineMean: Double,
        baselineStddev: Double,
        sampleCount: Int,
        computedAt: Date = .now
    ) {
        self.lastNightDeviationC = lastNightDeviationC
        self.baselineMean = baselineMean
        self.baselineStddev = max(0.05, baselineStddev)   // 防除零,体温 stddev 通常 0.1-0.3°C
        self.sampleCount = sampleCount
        self.computedAt = computedAt
    }

    /// z-score:昨晚偏差相对 14d 基线的标准化差异
    public var zScore: Double? {
        guard let last = lastNightDeviationC, sampleCount >= 5 else { return nil }
        return (last - baselineMean) / baselineStddev
    }

    public var isConfident: Bool { sampleCount >= 5 }

    /// 体温显著偏高(z>1.5) → 可能在生病 / 过劳 / 周期等
    public var isElevated: Bool {
        guard let z = zScore else { return false }
        return z > 1.5
    }

    /// 体温显著偏低(z<-1.5)→ 也可能异常(但少见)
    public var isDepressed: Bool {
        guard let z = zScore else { return false }
        return z < -1.5
    }

    /// Recovery 应当扣的分:
    /// - z ∈ [-1, +1]:0(正常)
    /// - |z| ∈ (1, 2]:线性 0..15
    /// - |z| > 2:15
    public var recoveryPenalty: Double {
        guard let z = zScore else { return 0 }
        let absZ = abs(z)
        if absZ <= 1.0 { return 0 }
        if absZ >= 2.0 { return 15 }
        return (absZ - 1.0) * 15
    }

    public static let unknown = WristTempStats(
        lastNightDeviationC: nil,
        baselineMean: 0,
        baselineStddev: 0,
        sampleCount: 0
    )
}
