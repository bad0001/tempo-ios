//
//  HealthKitService+Algorithm.swift
//  Tempo
//
//  v2 算法 helper:把所有 5 处 evaluator 调用统一到 evaluateCurrentStress,
//  自动注入 baseline / stats / phasic / profile / activity / circadian。
//
//  以后改算法只动这一个 entry。
//

import Foundation
import HealthKit
import SwiftData
import TempoCore

@MainActor
extension HealthKitService {

    // MARK: - Master helper — v2 stress evaluator

    /// 用最新参数算一次 stress。
    /// - Parameters:
    ///   - hr: 心率 bpm,0 表示未知(会用 baseline.restingHeartRate 兜底)
    ///   - hrv: HRV SDNN ms,可选
    ///   - rr: 呼吸频率,可选
    ///   - at: 评估时间,默认 now
    ///   - container: SwiftData container — 取 28d BaselineStats 需要,可空(空 → fallback v1)
    func evaluateCurrentStress(
        hr: Double,
        hrv: Double?,
        rr: Double? = nil,
        at: Date = .now,
        container: ModelContainer? = nil
    ) async -> EvaluatedStress {
        // 并行抓所有维度,缺一不可用 fallback
        async let baselineTask = (try? await fetchPersonalBaseline()) ?? .default
        async let statsTask = StressBaselineService.shared.currentStats(container: container)
        async let phasicTask = fetchPhasicHRV()
        async let activityTask = MotionActivityDetector.shared.currentActivity()
        async let rrTask: Double? = (rr == nil) ? (try? fetchLatestRespiratoryRate()) : rr

        let baseline = await baselineTask
        let stats = await statsTask
        let phasic = await phasicTask
        let activity = await activityTask
        let respiratory = await rrTask
        let profile = UserProfileStore.shared.current
        let circadianEnabled = PreferencesStore.shared.circadianEnabled

        let effectiveHR: Double = hr > 0 ? hr : baseline.restingHeartRate
        let effectiveHRV: Double? = hrv ?? baseline.averageHRV

        let evaluator = StressEvaluator(baseline: baseline)
        let baseScore = evaluator.evaluate(
            heartRate: effectiveHR,
            hrv: effectiveHRV,
            respiratoryRate: respiratory,
            stats: stats,
            hrvPhasic: PreferencesStore.shared.usePhasicHRV ? phasic : nil,
            activityState: activity,
            profile: profile,
            timestamp: at,
            circadianEnabled: circadianEnabled
        )

        // Per-user ML 个性化覆盖(如果用户训练过且置信):
        // 用 ridge regression 预测 stress,与 evaluator base 加权混合(70% ML / 30% base)。
        // 不是 100% ML 是为了避免冷启动后的 outlier 过冲。
        var finalScore = baseScore
        var usedML = false
        let model = PersonalStressModel.shared
        if PreferencesStore.shared.usePersonalModel,
           model.isConfident {
            let features = PersonalStressModel.buildFeatures(
                hr: effectiveHR,
                hrv: effectiveHRV ?? 50,
                rr: respiratory ?? 14,
                at: at,
                age: profile.age
            )
            if let mlValue = model.predict(features: features) {
                let mixed = mlValue * 0.7 + Double(baseScore.value) * 0.3
                finalScore = StressScore(value: Int(mixed.rounded()), timestamp: at)
                usedML = true
            }
        }

        return EvaluatedStress(
            score: finalScore,
            activityState: activity,
            algorithmVersion: usedML ? AlgorithmVersion.current + 100 : AlgorithmVersion.current,
            usedZScoreBaseline: stats.isConfident
        )
    }

    /// Strain 也走个性化(取 UserProfile 用真实 age 算 Tanaka maxHR)
    func computePersonalizedStrain() async -> Strain {
        async let readings = fetchTodayHeartRates()
        async let baseline = fetchPersonalBaseline()
        let profile = UserProfileStore.shared.current

        let readingsValue: [HeartRateReading]
        do { readingsValue = try await readings } catch { readingsValue = [] }

        let baselineValue: PersonalBaseline
        do { baselineValue = try await baseline } catch { baselineValue = .default }

        return Strain(
            readings: readingsValue,
            restingHeartRate: baselineValue.restingHeartRate,
            profile: profile
        )
    }

    // MARK: - Sleep state

    /// 当前是否在睡眠中:查 HealthKit 最近 60min 是否有 asleep* 样本
    func isCurrentlyAsleep() async -> Bool {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return false }
        let cutoff = Date().addingTimeInterval(-60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 5,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ]
                let inSleep = (samples as? [HKCategorySample] ?? []).contains { sample in
                    asleepValues.contains(sample.value) && sample.endDate >= Date().addingTimeInterval(-10 * 60)
                }
                cont.resume(returning: inSleep)
            }
            HKHealthStore().execute(query)
        }
    }

    // MARK: - Phasic HRV

    /// 计算最近 60min HRV 均值 + 14d tonic baseline → HRVPhasic
    func fetchPhasicHRV() async -> HRVPhasic? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }

        // 最近 60min HRV 均值
        let recent: (mean: Double, count: Int) = await {
            let predicate = HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(-3600),
                end: Date()
            )
            return await withCheckedContinuation { cont in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, _ in
                    let unit = HKUnit.secondUnit(with: .milli)
                    let values: [Double] = (samples as? [HKQuantitySample] ?? []).map {
                        $0.quantity.doubleValue(for: unit)
                    }
                    guard !values.isEmpty else {
                        cont.resume(returning: (0, 0))
                        return
                    }
                    let mean = values.reduce(0, +) / Double(values.count)
                    cont.resume(returning: (mean, values.count))
                }
                HKHealthStore().execute(query)
            }
        }()

        guard recent.count >= 2 else { return nil }

        // 14d tonic baseline
        let tonic: Double = await {
            let predicate = HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(-14 * 86400),
                end: Date()
            )
            return await withCheckedContinuation { cont in
                let query = HKStatisticsQuery(
                    quantityType: type,
                    quantitySamplePredicate: predicate,
                    options: .discreteAverage
                ) { _, statistics, _ in
                    let value = statistics?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)) ?? 0
                    cont.resume(returning: value)
                }
                HKHealthStore().execute(query)
            }
        }()

        guard tonic > 0 else { return nil }

        return HRVPhasic(
            recent60minMean: recent.mean,
            tonicBaseline: tonic,
            recentSampleCount: recent.count
        )
    }

    // MARK: - ML snapshot

    /// MoodLogView 提交时一次性抓「当下客观特征」存 MoodEntry
    func snapshotForML() async -> MoodFeatureSnapshot {
        async let hr = (try? fetchLatestHeartRate())
        async let hrv = (try? fetchLatestHRV())
        async let rr = (try? fetchLatestRespiratoryRate())
        async let activity = MotionActivityDetector.shared.currentActivity()
        async let asleep = isCurrentlyAsleep()

        let hrVal: Double? = await hr ?? nil
        let hrvVal: Double? = await hrv ?? nil
        let rrVal: Double? = await rr ?? nil
        let activityVal = await activity
        let asleepVal = await asleep

        // 用主 helper 算一次当下 stress score
        let score: StressScore?
        if let hrVal, hrVal > 0 {
            let evaluated = await evaluateCurrentStress(hr: hrVal, hrv: hrvVal, rr: rrVal)
            score = evaluated.score
        } else {
            score = nil
        }

        let profile = UserProfileStore.shared.current
        return MoodFeatureSnapshot(
            hr: hrVal,
            hrv: hrvVal,
            rr: rrVal,
            stressScore: score?.value,
            activityRaw: activityVal.rawValue,
            wasAsleepRecently: asleepVal,
            age: profile.age,
            genderRaw: profile.gender.rawValue,
            algorithmVersion: AlgorithmVersion.current
        )
    }

}

// MARK: - DTOs

/// evaluateCurrentStress 的胖结果 — 调用方写 SwiftData 时一次拿齐
struct EvaluatedStress: Sendable {
    let score: StressScore
    let activityState: ActivityState
    let algorithmVersion: Int
    /// 是否用了 v2 z-score 路径(false = 冷启动 fallback 到 v1)
    let usedZScoreBaseline: Bool

    var value: Int { score.value }
    var level: StressLevel { score.level }
    var timestamp: Date { score.timestamp }
}

struct MoodFeatureSnapshot: Sendable {
    let hr: Double?
    let hrv: Double?
    let rr: Double?
    let stressScore: Int?
    let activityRaw: String
    let wasAsleepRecently: Bool
    let age: Int
    let genderRaw: String
    let algorithmVersion: Int
}
