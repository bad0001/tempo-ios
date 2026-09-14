//
//  SleepStageHours.swift
//  TempoCore
//
//  按睡眠分期拆分的小时数 — 用于 Recovery 加权评分。
//
//  学术目标(成人 7-9h 总睡):
//   - Deep:1.5-2h(身体恢复:GH 分泌、组织修复)
//   - REM:1.5-2h(认知 / 情绪恢复)
//   - Core / Light:3-5h
//
//  Walker 2017 "Why We Sleep" — Deep 主管身体恢复,REM 主管认知恢复。
//

import Foundation

public struct SleepStageHours: Codable, Hashable, Sendable {
    public let deep: Double
    public let rem: Double
    public let core: Double
    public let awake: Double
    public let unspecified: Double

    public init(deep: Double, rem: Double, core: Double, awake: Double, unspecified: Double) {
        self.deep = max(0, deep)
        self.rem = max(0, rem)
        self.core = max(0, core)
        self.awake = max(0, awake)
        self.unspecified = max(0, unspecified)
    }

    /// 真实 asleep 时长(不含 awake)
    public var totalAsleepHours: Double {
        deep + rem + core + unspecified
    }

    /// 加权睡眠时长 — deep 与 REM 价值高,core 次之,unspecified 最低
    public var weightedHours: Double {
        deep * 1.5 + rem * 1.3 + core * 1.0 + unspecified * 0.7
    }

    /// 0-100 sleep score,综合 deep + REM 目标 + 总时长
    public var sleepScore: Double {
        // 三个子分:deep 目标 1.5h,rem 目标 1.5h,total 目标 8h
        let deepScore = min(100, deep / 1.5 * 100)
        let remScore = min(100, rem / 1.5 * 100)
        let durationScore = min(100, totalAsleepHours / 8 * 100)
        return 0.35 * deepScore + 0.25 * remScore + 0.4 * durationScore
    }

    public var hasStageData: Bool {
        deep > 0 || rem > 0 || core > 0
    }

    public static let unknown = SleepStageHours(deep: 0, rem: 0, core: 0, awake: 0, unspecified: 0)
}
