//
//  StressBaselineService.swift
//  Tempo
//
//  扫描本机 SwiftData StressEntry,计算最近 28 天 HR / HRV / RR 的
//  均值&标准差,产出 BaselineStats 供 StressEvaluator z-score 评分。
//
//  防污染:
//   - 剔除 activityStateRaw=="exercising" 的样本(运动时 HR 飙高,污染均值)
//   - 剔除 3σ 外的 outlier
//   - 至少需要 50 个样本才 .isConfident
//

import Foundation
import Observation
import SwiftData
import TempoCore

@MainActor
@Observable
final class StressBaselineService {
    static let shared = StressBaselineService()

    private(set) var cached: BaselineStats = .unknown
    private var cachedAt: Date?
    private let cacheTTL: TimeInterval = 3600   // 1h

    /// 主入口 — Home/History/PhoneSession 等都通过这个拿 stats
    /// - Parameters:
    ///   - container: SwiftData container,可从 modelContext 拿
    ///   - forceRefresh: 跳过缓存,强制重算
    func currentStats(container: ModelContainer?, forceRefresh: Bool = false) async -> BaselineStats {
        if !forceRefresh,
           let at = cachedAt,
           Date().timeIntervalSince(at) < cacheTTL {
            return cached
        }
        guard let container else { return .unknown }
        let stats = computeStats(container: container)
        cached = stats
        cachedAt = Date()
        return stats
    }

    func invalidate() {
        cachedAt = nil
        cached = .unknown
    }

    // MARK: - Compute

    private func computeStats(container: ModelContainer) -> BaselineStats {
        let context = ModelContext(container)
        let cutoff = Date().addingTimeInterval(-28 * 86400)
        var descriptor = FetchDescriptor<StressEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff }
        )
        descriptor.fetchLimit = 50_000

        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else {
            return .unknown
        }

        // 过滤掉运动样本
        let valid = entries.filter { $0.activityStateRaw != ActivityState.exercising.rawValue }
        guard valid.count >= 30 else { return .unknown }

        let hrs = valid.map(\.bpm).filter { $0 > 0 }
        let hrvs = valid.compactMap(\.hrv).filter { $0 > 0 }

        // 1st pass: 计算 mean / stddev
        let (hrMean1, hrSd1) = meanStddev(hrs)
        let (hrvMean1, hrvSd1) = meanStddev(hrvs)

        // 2nd pass: 剔除 3σ outlier
        let hrsClean = hrs.filter { abs($0 - hrMean1) <= 3 * hrSd1 }
        let hrvsClean = hrvs.filter { abs($0 - hrvMean1) <= 3 * hrvSd1 }

        let (hrMean, hrSd) = meanStddev(hrsClean)
        let (hrvMean, hrvSd) = meanStddev(hrvsClean)

        return BaselineStats(
            hrMean: hrMean,
            hrStddev: hrSd,
            hrvMean: hrvMean,
            hrvStddev: hrvSd,
            // RR baseline 14±2 是医学经验值(成人静息呼吸频率)
            rrMean: 14,
            rrStddev: 2,
            sampleCount: valid.count,
            windowDays: 28,
            computedAt: Date()
        )
    }

    private func meanStddev(_ values: [Double]) -> (Double, Double) {
        guard !values.isEmpty else { return (0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, variance.squareRoot())
    }

    private init() {}
}
