//
//  BaselineStats.swift
//  TempoCore
//
//  用户最近 28 天 HR / HRV / RR 的滑动均值 & 标准差,
//  供 StressEvaluator 做 z-score 评分(摆脱固定 baseline 的偏倚)。
//

import Foundation

public struct BaselineStats: Codable, Hashable, Sendable {
    public let hrMean: Double
    public let hrStddev: Double
    public let hrvMean: Double
    public let hrvStddev: Double
    public let rrMean: Double
    public let rrStddev: Double
    public let sampleCount: Int
    public let windowDays: Int
    public let computedAt: Date

    public init(
        hrMean: Double,
        hrStddev: Double,
        hrvMean: Double,
        hrvStddev: Double,
        rrMean: Double = 14,
        rrStddev: Double = 2,
        sampleCount: Int,
        windowDays: Int = 28,
        computedAt: Date = .now
    ) {
        // 防止 stddev=0 导致 z-score 除零
        self.hrMean = hrMean
        self.hrStddev = max(2.0, hrStddev)
        self.hrvMean = hrvMean
        self.hrvStddev = max(2.0, hrvStddev)
        self.rrMean = rrMean
        self.rrStddev = max(0.8, rrStddev)
        self.sampleCount = sampleCount
        self.windowDays = windowDays
        self.computedAt = computedAt
    }

    /// 至少 50 样本才认为 baseline 可信 — 否则回退到老算法
    public var isConfident: Bool {
        sampleCount >= 50 && hrMean > 0 && hrvMean > 0
    }

    // MARK: - z-score helpers

    public func hrZScore(_ value: Double) -> Double {
        (value - hrMean) / hrStddev
    }

    public func hrvZScore(_ value: Double) -> Double {
        (value - hrvMean) / hrvStddev
    }

    public func rrZScore(_ value: Double) -> Double {
        (value - rrMean) / rrStddev
    }

    public static let unknown = BaselineStats(
        hrMean: 0,
        hrStddev: 0,
        hrvMean: 0,
        hrvStddev: 0,
        sampleCount: 0
    )
}
