//
//  HealthKitService.swift
//  Tempo
//

import Foundation
import HealthKit
import TempoCore

struct DailySleepData: Identifiable {
    let date: Date
    let totalHours: Double
    let deepHours: Double
    let coreHours: Double
    let remHours: Double

    var id: Date { date }
}

struct HealthMetricHistoryPoint: Identifiable, Hashable {
    let date: Date
    let value: Double

    var id: Date { date }
}

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    private var cachedBaseline: PersonalBaseline?
    private var baselineFetchedAt: Date?
    private var cachedHRV: Double?
    private var hrvFetchedAt: Date?

    private static let readTypes: Set<HKObjectType> = {
        var s: Set<HKObjectType> = []
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .respiratoryRate,
            .oxygenSaturation,
            .activeEnergyBurned,
            .stepCount,
            .appleSleepingWristTemperature
        ]
        for id in quantityIDs {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                s.insert(t)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            s.insert(sleep)
        }
        if let mind = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            s.insert(mind)
        }
        if let ecg = HKObjectType.electrocardiogramType() as HKObjectType? {
            s.insert(ecg)
        }
        return s
    }()

    private static let writeTypes: Set<HKSampleType> = {
        var s: Set<HKSampleType> = []
        if let mind = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            s.insert(mind)
        }
        return s
    }()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// PersonalInfo 改 age/gender 后清缓存(Strain maxHR 会变)
    func invalidateBaselineCache() {
        cachedBaseline = nil
        baselineFetchedAt = nil
        cachedHRV = nil
        hrvFetchedAt = nil
    }

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        guard isAvailable else { return false }
        try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
        return true
    }

    // MARK: - Reads

    func fetchRecentHeartRates(within seconds: TimeInterval = 86400, limit: Int = 300) async throws -> [HeartRateReading] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-seconds),
            end: Date()
        )
        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let readings: [HeartRateReading] = (samples as? [HKQuantitySample] ?? []).map {
                    HeartRateReading(bpm: $0.quantity.doubleValue(for: unit), timestamp: $0.startDate)
                }
                cont.resume(returning: readings)
            }
            store.execute(query)
        }
    }

    /// 直接从 HealthKit 读最近一条心率(任何来源 — Watch / 第三方 / 手动录入).
    /// 让 Tempo 在 Watch App 未启动监测时也能展示心率.
    func fetchLatestHeartRate() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        return try await fetchLatestQuantity(type: type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    func fetchLatestHRV() async throws -> Double? {
        if let cached = cachedHRV,
           let fetched = hrvFetchedAt,
           Date().timeIntervalSince(fetched) < 600 {
            return cached
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let value = try await fetchLatestQuantity(type: type, unit: .secondUnit(with: .milli))
        if let value {
            cachedHRV = value
            hrvFetchedAt = Date()
        }
        return value
    }

    func fetchLatestRestingHeartRate() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        return try await fetchLatestQuantity(type: type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    func fetchDailyHRVHistory(daysBack: Int = 30) async throws -> [HealthMetricHistoryPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        return try await fetchDailyAverageSamples(
            type: type,
            unit: .secondUnit(with: .milli),
            daysBack: daysBack
        )
    }

    /// 拉过去 N 天的 HRV raw samples(用于 server 上传).返回 (timestamp, valueMs).
    func fetchRecentHRVSamples(daysBack: Int = 1, maxCount: Int = 500) async throws -> [(date: Date, valueMs: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: endDate) ?? endDate
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: maxCount,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let unit = HKUnit.secondUnit(with: .milli)
                let result: [(date: Date, valueMs: Double)] = (samples ?? []).compactMap { sample in
                    guard let q = sample as? HKQuantitySample else { return nil }
                    return (q.startDate, q.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    func fetchDailyRestingHeartRateHistory(daysBack: Int = 30) async throws -> [HealthMetricHistoryPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return [] }
        return try await fetchDailyAverageSamples(
            type: type,
            unit: HKUnit.count().unitDivided(by: .minute()),
            daysBack: daysBack
        )
    }

    func fetchLatestRespiratoryRate() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else { return nil }
        return try await fetchLatestQuantity(type: type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    /// 返回最近一条 SpO2 百分比(0-100,非 0-1)
    func fetchLatestSpO2Percent() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return nil }
        let raw = try await fetchLatestQuantity(type: type, unit: .percent())
        guard let raw else { return nil }
        return raw * 100  // HK percent unit 返回 0-1
    }

    func fetchPersonalBaseline(daysBack: Int = 14) async throws -> PersonalBaseline {
        if let cached = cachedBaseline,
           let fetched = baselineFetchedAt,
           Date().timeIntervalSince(fetched) < 3600 {
            return cached
        }

        async let rhr = fetchLatestRestingHeartRate()
        async let hrv = averageHRV(daysBack: daysBack)

        let rhrValue = try await rhr ?? PersonalBaseline.default.restingHeartRate
        let hrvValue = try await hrv ?? PersonalBaseline.default.averageHRV

        let baseline = PersonalBaseline(restingHeartRate: rhrValue, averageHRV: hrvValue)
        cachedBaseline = baseline
        baselineFetchedAt = Date()
        return baseline
    }

    // MARK: - Recovery & Strain

    func fetchOvernightHRV() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let cutoff = Date().addingTimeInterval(-12 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())
        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error { cont.resume(throwing: error); return }
                let value = statistics?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
                cont.resume(returning: value)
            }
            store.execute(query)
        }
    }

    func fetchOvernightRHR() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())
        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error { cont.resume(throwing: error); return }
                let value = statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                cont.resume(returning: value)
            }
            store.execute(query)
        }
    }

    func fetchLastNightSleepHours() async throws -> Double {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let cutoff = Date().addingTimeInterval(-16 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let sleepSamples = (samples as? [HKCategorySample] ?? []).filter { sample in
                    sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                    sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                let totalSeconds = sleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: totalSeconds / 3600)
            }
            store.execute(query)
        }
    }

    /// v3 入口:自动使用 sleep stages + wrist temperature(extension 实现)
    /// 老调用方无需修改 — 直接享受新算法。
    func computeRecovery() async -> Recovery {
        await computeRecoveryV3()
    }

    func fetchTodayHeartRates() async throws -> [HeartRateReading] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let secondsSinceStart = Date().timeIntervalSince(startOfDay)
        return try await fetchRecentHeartRates(within: secondsSinceStart, limit: 1000)
    }

    func fetchSleepHistory(daysBack: Int = 30) async throws -> [DailySleepData] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(daysBack) * 86400)
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }

                let cal = Calendar.current
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                let grouped = Dictionary(grouping: categorySamples) {
                    cal.startOfDay(for: $0.endDate)
                }

                let result: [DailySleepData] = grouped.map { (date, samples) in
                    var deep: TimeInterval = 0
                    var core: TimeInterval = 0
                    var rem: TimeInterval = 0
                    var total: TimeInterval = 0

                    for s in samples {
                        let duration = s.endDate.timeIntervalSince(s.startDate)
                        switch s.value {
                        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                            deep += duration; total += duration
                        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                            core += duration; total += duration
                        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                            rem += duration; total += duration
                        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                            total += duration
                        default:
                            break
                        }
                    }

                    return DailySleepData(
                        date: date,
                        totalHours: total / 3600,
                        deepHours: deep / 3600,
                        coreHours: core / 3600,
                        remHours: rem / 3600
                    )
                }.sorted { $0.date < $1.date }

                cont.resume(returning: result)
            }
            store.execute(query)
        }
    }

    /// 老入口:30 岁默认。新代码用 computePersonalizedStrain()。
    func computeStrain() async -> Strain {
        await computePersonalizedStrain()
    }

    // MARK: - Writes

    func writeMindfulSession(start: Date, end: Date) async throws {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }
        let sample = HKCategorySample(type: type, value: 0, start: start, end: end)
        try await store.save(sample)
    }

    // MARK: - Private

    private func averageHRV(daysBack: Int) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-Double(daysBack) * 86400),
            end: Date()
        )
        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let value = statistics?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
                cont.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchLatestQuantity(type: HKQuantityType, unit: HKUnit) async throws -> Double? {
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchDailyAverageSamples(
        type: HKQuantityType,
        unit: HKUnit,
        daysBack: Int
    ) async throws -> [HealthMetricHistoryPoint] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date().addingTimeInterval(-Double(daysBack) * 86_400))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let grouped = Dictionary(grouping: (samples as? [HKQuantitySample]) ?? []) {
                    calendar.startOfDay(for: $0.startDate)
                }
                let points = grouped.compactMap { date, samples -> HealthMetricHistoryPoint? in
                    guard !samples.isEmpty else { return nil }
                    let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                    return HealthMetricHistoryPoint(date: date, value: total / Double(samples.count))
                }
                .sorted { $0.date < $1.date }
                cont.resume(returning: points)
            }
            store.execute(query)
        }
    }
}
