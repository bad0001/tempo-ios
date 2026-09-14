//
//  HealthKitService+Recovery.swift
//  Tempo
//
//  Recovery v3 数据采集:体温 + 睡眠分期 + ECG 高分辨率 HRV。
//

import Foundation
import HealthKit
import TempoCore

@MainActor
extension HealthKitService {

    // MARK: - Wrist Temperature

    /// 昨晚的体温偏差(°C,相对 Apple 自己的 baseline)
    func fetchLastNightWristTemperature() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else { return nil }
        let cutoff = Date().addingTimeInterval(-16 * 3600)   // 最近 16h(昨晚)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                // Apple HK 默认单位:°C (offset),deviation 可正可负
                let value = statistics?.averageQuantity()?.doubleValue(for: HKUnit.degreeCelsius())
                cont.resume(returning: value)
            }
            HKHealthStore().execute(query)
        }
    }

    /// 14 天体温偏差的均值 / stddev,用于算 z-score
    func fetchWristTemperatureStats(daysBack: Int = 14) async -> WristTempStats {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else {
            return .unknown
        }
        let cutoff = Date().addingTimeInterval(-Double(daysBack) * 86400)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())

        let samples: [Double] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let values: [Double] = (samples as? [HKQuantitySample] ?? []).map {
                    $0.quantity.doubleValue(for: HKUnit.degreeCelsius())
                }
                cont.resume(returning: values)
            }
            HKHealthStore().execute(query)
        }

        guard samples.count >= 5 else {
            return WristTempStats(
                lastNightDeviationC: samples.last,
                baselineMean: 0,
                baselineStddev: 0,
                sampleCount: samples.count
            )
        }

        // 14d 全部样本算均值 stddev,昨晚一条单独 last
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)
        let stddev = variance.squareRoot()

        let lastNight = await fetchLastNightWristTemperature()

        return WristTempStats(
            lastNightDeviationC: lastNight,
            baselineMean: mean,
            baselineStddev: stddev,
            sampleCount: samples.count
        )
    }

    // MARK: - Sleep Stages

    /// 昨晚的睡眠分期分布(小时)
    func fetchLastNightSleepStages() async -> SleepStageHours {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return .unknown
        }
        let cutoff = Date().addingTimeInterval(-16 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let categories = (samples as? [HKCategorySample]) ?? []
                var deep: TimeInterval = 0
                var rem: TimeInterval = 0
                var core: TimeInterval = 0
                var awake: TimeInterval = 0
                var unspecified: TimeInterval = 0
                for s in categories {
                    let duration = s.endDate.timeIntervalSince(s.startDate)
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deep += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        rem += duration
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        core += duration
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awake += duration
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        unspecified += duration
                    default:
                        break
                    }
                }
                cont.resume(returning: SleepStageHours(
                    deep: deep / 3600,
                    rem: rem / 3600,
                    core: core / 3600,
                    awake: awake / 3600,
                    unspecified: unspecified / 3600
                ))
            }
            HKHealthStore().execute(query)
        }
    }

    // MARK: - Recovery v3 — 整合体温 + 睡眠分期

    /// 升级版 computeRecovery:加入体温 + 睡眠分期。
    /// 老 computeRecovery 保留兼容性。
    func computeRecoveryV3() async -> Recovery {
        async let hrv = fetchOvernightHRV()
        async let rhr = fetchOvernightRHR()
        async let stages = fetchLastNightSleepStages()
        async let baseline = fetchPersonalBaseline()
        async let tempStats = fetchWristTemperatureStats()

        let baselineValue: PersonalBaseline
        do { baselineValue = try await baseline } catch { baselineValue = .default }

        let hrvValue: Double?
        do { hrvValue = try await hrv } catch { hrvValue = nil }

        let rhrValue: Double?
        do { rhrValue = try await rhr } catch { rhrValue = nil }

        let stagesValue = await stages
        let tempValue = await tempStats

        return Recovery(
            overnightHRV: hrvValue,
            baselineHRV: baselineValue.averageHRV,
            lastNightRHR: rhrValue,
            baselineRHR: baselineValue.restingHeartRate,
            sleepHours: stagesValue.totalAsleepHours,
            sleepStages: stagesValue,
            wristTempStats: tempValue
        )
    }

    // MARK: - ECG

    /// 拉最近 N 天的 ECG samples,每个 sample 是 ~30s 单次手动录制
    func fetchRecentECG(daysBack: Int = 30, maxCount: Int = 10) async -> [HKElectrocardiogram] {
        let type = HKObjectType.electrocardiogramType()
        let cutoff = Date().addingTimeInterval(-Double(daysBack) * 86400)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: maxCount,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKElectrocardiogram]) ?? [])
            }
            HKHealthStore().execute(query)
        }
    }

    /// 单次 ECG 的逐点 voltage(μV)— 用于 R-peak 检测
    /// 注意:HKElectrocardiogramQuery 是异步迭代器,这里把所有 voltage 收集起来
    func fetchECGVoltage(_ ecg: HKElectrocardiogram) async -> [Double] {
        return await withCheckedContinuation { cont in
            var voltages: [Double] = []
            let query = HKElectrocardiogramQuery(ecg) { _, result in
                switch result {
                case .measurement(let m):
                    if let q = m.quantity(for: .appleWatchSimilarToLeadI) {
                        voltages.append(q.doubleValue(for: .voltUnit(with: .micro)))
                    }
                case .done:
                    cont.resume(returning: voltages)
                case .error:
                    cont.resume(returning: voltages)
                @unknown default:
                    cont.resume(returning: voltages)
                }
            }
            HKHealthStore().execute(query)
        }
    }
}
