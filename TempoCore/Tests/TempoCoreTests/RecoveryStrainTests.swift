import Testing
import Foundation
@testable import TempoCore

@Suite("Recovery")
struct RecoveryTests {

    @Test("HRV 高于 baseline + 睡足 → 高恢复")
    func wellRested() {
        let r = Recovery(
            overnightHRV: 70,
            baselineHRV: 50,
            lastNightRHR: 55,
            baselineRHR: 60,
            sleepHours: 8.5
        )
        #expect(r.value >= 80)
        #expect(r.level == .excellent || r.level == .good)
    }

    @Test("HRV 低于 baseline + 睡眠不足 → 低恢复")
    func underRecovered() {
        let r = Recovery(
            overnightHRV: 30,
            baselineHRV: 50,
            lastNightRHR: 70,
            baselineRHR: 60,
            sleepHours: 5.0
        )
        #expect(r.value <= 50)
    }

    @Test("数据缺失时降级为未知")
    func missingData() {
        let r = Recovery(
            overnightHRV: nil,
            baselineHRV: 0,
            lastNightRHR: nil,
            baselineRHR: 0,
            sleepHours: 0
        )
        #expect(r.hasEnoughData == false)
    }

    @Test("RecoveryLevel 边界")
    func levelBoundaries() {
        #expect(RecoveryLevel(value: 0) == .poor)
        #expect(RecoveryLevel(value: 33) == .poor)
        #expect(RecoveryLevel(value: 34) == .fair)
        #expect(RecoveryLevel(value: 66) == .fair)
        #expect(RecoveryLevel(value: 67) == .good)
        #expect(RecoveryLevel(value: 85) == .good)
        #expect(RecoveryLevel(value: 86) == .excellent)
        #expect(RecoveryLevel(value: 100) == .excellent)
    }
}

@Suite("Strain")
struct StrainTests {

    @Test("空读数 → 0 分轻度")
    func emptyReadings() {
        let s = Strain(readings: [], restingHeartRate: 60)
        #expect(s.value == 0)
        #expect(s.level == .light)
    }

    @Test("全程静息心率 → 接近 0")
    func allResting() {
        let readings = (0..<60).map { _ in
            HeartRateReading(bpm: 60, timestamp: .now)
        }
        let s = Strain(readings: readings, restingHeartRate: 60)
        #expect(s.value < 2)
        #expect(s.level == .light)
    }

    @Test("中度运动 30 分钟 → 中等以上")
    func moderateExercise() {
        let readings = (0..<30).map { _ in
            HeartRateReading(bpm: 130, timestamp: .now)
        }
        let s = Strain(readings: readings, restingHeartRate: 60, estimatedAge: 30)
        #expect(s.value >= 4)
    }

    @Test("StrainLevel 边界")
    func levelBoundaries() {
        #expect(StrainLevel(value: 0) == .light)
        #expect(StrainLevel(value: 4.4) == .light)
        #expect(StrainLevel(value: 4.5) == .moderate)
        #expect(StrainLevel(value: 6.5) == .heavy)
        #expect(StrainLevel(value: 8.5) == .allOut)
    }
}
