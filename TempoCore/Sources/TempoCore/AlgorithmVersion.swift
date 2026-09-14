//
//  AlgorithmVersion.swift
//  TempoCore
//
//  Stress / Strain / Recovery 算法版本号 — 每次大调整都 +1,
//  数据(StressEntry / stress_history 服务端)按版本号存,
//  历史趋势可按版本分线,避免新旧算法混在一张图上。
//

import Foundation

public enum AlgorithmVersion {
    /// v1 = 初版 PersonalBaseline 线性加权(2026-04)
    /// v2 = + BaselineStats z-score + UserProfile-aware + Circadian + HRVPhasic(2026-05 第一周)
    /// v3 = + 体温(Apple Watch Series 8+)+ 睡眠分期加权 Recovery + ECG RMSSD
    ///      + GAD-7/PHQ-9/PSS-10 + per-user ridge regression ML(2026-05 第二周)
    public static let current: Int = 3

    public static func displayName(for version: Int) -> String {
        switch version {
        case 1: "v1 · 基础"
        case 2: "v2 · z-score"
        case 3: "v3 · 多生理"
        default: "v\(version)"
        }
    }
}
