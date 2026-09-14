import Testing
import Foundation
@testable import TempoCore

@Suite("BreathingPattern 预设")
struct BreathingPatternTests {

    @Test("6 种预设都存在")
    func allPresetsCount() {
        #expect(BreathingPattern.allPresets.count == 6)
    }

    @Test("免费 / Pro 划分正确(免费 3,Pro 3)")
    func freeAndProSplit() {
        #expect(BreathingPattern.freePresets.count == 3)
        #expect(BreathingPattern.proPresets.count == 3)
        #expect(BreathingPattern.allPresets.count == BreathingPattern.freePresets.count + BreathingPattern.proPresets.count)
    }

    @Test("4-7-8 循环时长 = 19 秒")
    func fourSevenEightCycleDuration() {
        #expect(BreathingPattern.fourSevenEight.cycleDuration == 19)
    }

    @Test("盒式呼吸循环时长 = 16 秒")
    func boxCycleDuration() {
        #expect(BreathingPattern.boxBreathing.cycleDuration == 16)
    }

    @Test("等长呼吸循环时长 = 10 秒")
    func coherentCycleDuration() {
        #expect(BreathingPattern.coherent.cycleDuration == 10)
    }

    @Test("共振呼吸 5.5 BPM = 11 秒一周期")
    func resonantBPMMatch() {
        #expect(BreathingPattern.resonant.cycleDuration == 11)
    }

    @Test("所有预设都有 id 且不重复")
    func uniqueIDs() {
        let ids = BreathingPattern.allPresets.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("所有预设都有非空中英文名 + 描述")
    func nonEmptyMetadata() {
        for pattern in BreathingPattern.allPresets {
            #expect(!pattern.displayName.isEmpty)
            #expect(!pattern.displayNameEnglish.isEmpty)
            #expect(!pattern.descriptionText.isEmpty)
            #expect(pattern.cycleDuration > 0)
            #expect(pattern.inhale > 0)
            #expect(pattern.exhale > 0)
        }
    }

    @Test("Codable 往返保持一致")
    func codableRoundTrip() throws {
        let original = BreathingPattern.fourSevenEight
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BreathingPattern.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("StressLevel / RecoveryLevel / StrainLevel 一致性")
struct LevelDisplayNameTests {

    @Test("StressLevel 中英文 displayName 都非空", arguments: StressLevel.allCases)
    func stressLevelNonEmpty(level: StressLevel) {
        #expect(!level.displayName.isEmpty)
        #expect(!level.displayNameEnglish.isEmpty)
    }

    @Test("RecoveryLevel 中英文 displayName 都非空", arguments: RecoveryLevel.allCases)
    func recoveryLevelNonEmpty(level: RecoveryLevel) {
        #expect(!level.displayName.isEmpty)
        #expect(!level.displayNameEnglish.isEmpty)
    }

    @Test("StrainLevel 中英文 displayName 都非空", arguments: StrainLevel.allCases)
    func strainLevelNonEmpty(level: StrainLevel) {
        #expect(!level.displayName.isEmpty)
        #expect(!level.displayNameEnglish.isEmpty)
    }

    @Test("StressLevel rawValue 双向稳定")
    func stressLevelRoundtrip() {
        for level in StressLevel.allCases {
            #expect(StressLevel(rawValue: level.rawValue) == level)
        }
    }
}

@Suite("StressScore 边界与 Codable")
struct StressScoreEdgeTests {

    @Test("Score 负值 clamp 到 0")
    func negativeClamps() {
        let s = StressScore(value: -50)
        #expect(s.value == 0)
        #expect(s.level == .calm)
    }

    @Test("Score 超 100 clamp 到 100")
    func overflowClamps() {
        let s = StressScore(value: 200)
        #expect(s.value == 100)
        #expect(s.level == .extreme)
    }

    @Test("Codable 往返保持值与等级")
    func codableRoundTrip() throws {
        let original = StressScore(value: 73)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StressScore.self, from: data)
        #expect(decoded.value == 73)
        #expect(decoded.level == .high)
    }
}

@Suite("StressEvaluator 输入鲁棒性")
struct StressEvaluatorRobustnessTests {

    @Test("heartRate = 0 不崩溃,返回基线分附近")
    func zeroHeartRate() {
        let evaluator = StressEvaluator(baseline: .default)
        let s = evaluator.evaluate(heartRate: 0)
        #expect(s.value >= 0 && s.value <= 100)
    }

    @Test("baseline restingHeartRate = 0 不崩溃")
    func zeroBaselineRHR() {
        let baseline = PersonalBaseline(restingHeartRate: 0, averageHRV: 50)
        let evaluator = StressEvaluator(baseline: baseline)
        let s = evaluator.evaluate(heartRate: 80, hrv: 40)
        #expect(s.value >= 0 && s.value <= 100)
    }

    @Test("极端高心率 (200 bpm) 不超出 0-100")
    func extremeHRClamps() {
        let evaluator = StressEvaluator(baseline: .default)
        let s = evaluator.evaluate(heartRate: 200, hrv: 10)
        #expect(s.value <= 100)
        #expect(s.value >= 0)
    }

    @Test("极端低 HRV (1ms) 提高压力分")
    func extremeLowHRVRaisesStress() {
        let evaluator = StressEvaluator(baseline: .default)
        let calm = evaluator.evaluate(heartRate: 70, hrv: 80)
        let stressed = evaluator.evaluate(heartRate: 70, hrv: 1)
        #expect(stressed.value > calm.value)
    }

    @Test("呼吸频率为 0 应忽略而非误判")
    func zeroRespiratoryRateIgnored() {
        let evaluator = StressEvaluator(baseline: .default)
        let withZero = evaluator.evaluate(heartRate: 70, hrv: 50, respiratoryRate: 0)
        let without = evaluator.evaluate(heartRate: 70, hrv: 50, respiratoryRate: nil)
        #expect(withZero.value == without.value)
    }
}

@Suite("Recovery 边界")
struct RecoveryEdgeTests {

    @Test(".unknown 静态值 hasEnoughData = false")
    func unknownHasNoData() {
        #expect(Recovery.unknown.hasEnoughData == false)
    }

    @Test("HRV 等于 baseline + 8h 睡眠 = 接近满分")
    func hrvAtBaselineFullSleep() {
        let r = Recovery(
            overnightHRV: 50,
            baselineHRV: 50,
            lastNightRHR: 60,
            baselineRHR: 60,
            sleepHours: 8.0
        )
        #expect(r.value >= 90)
    }

    @Test("睡眠 0 小时 hasEnoughData = false")
    func zeroSleepNotEnough() {
        let r = Recovery(
            overnightHRV: 60,
            baselineHRV: 50,
            lastNightRHR: 55,
            baselineRHR: 60,
            sleepHours: 0
        )
        #expect(r.hasEnoughData == false)
    }

    @Test("HRV 远高于 baseline (1.5×) 仍 clamp 到 100 内")
    func hrvOverflowClamps() {
        let r = Recovery(
            overnightHRV: 100,
            baselineHRV: 50,
            lastNightRHR: 50,
            baselineRHR: 60,
            sleepHours: 9
        )
        #expect(r.value <= 100)
        #expect(r.value >= 0)
    }
}

@Suite("Strain 边界")
struct StrainEdgeTests {

    @Test("极端运动 (200bpm × 60min) clamp 到 10")
    func extremeWorkoutClamps() {
        let readings = (0..<60).map { _ in
            HeartRateReading(bpm: 200, timestamp: .now)
        }
        let s = Strain(readings: readings, restingHeartRate: 60, estimatedAge: 25)
        #expect(s.value <= 10)
        #expect(s.level == .allOut || s.level == .heavy)
    }

    @Test("年龄差异影响 maxHR 计算")
    func ageAffectsMaxHR() {
        let readings = (0..<30).map { _ in
            HeartRateReading(bpm: 150, timestamp: .now)
        }
        let young = Strain(readings: readings, restingHeartRate: 60, estimatedAge: 20)
        let old = Strain(readings: readings, restingHeartRate: 60, estimatedAge: 70)
        // 年长用户 maxHR 更低,150 bpm 相对更接近 max,strain 更高
        #expect(old.value >= young.value)
    }

    @Test("Strain.none 返回 0 分轻度")
    func staticNone() {
        #expect(Strain.none.value == 0)
        #expect(Strain.none.level == .light)
    }

    @Test("averageHeartRate 在空 readings 时为 0,不崩溃")
    func emptyReadingsAvg() {
        let s = Strain(readings: [], restingHeartRate: 60)
        #expect(s.averageHeartRate == 0)
        #expect(s.peakHeartRate == 0)
        #expect(s.elevatedMinutes == 0)
    }
}

@Suite("StressEntry @Model")
struct StressEntryTests {

    @Test("StressEntry.level 从 levelRaw 正确恢复")
    func levelFromRaw() {
        let entry = StressEntry(
            bpm: 75,
            scoreValue: 60,
            levelRaw: StressLevel.mild.rawValue
        )
        #expect(entry.level == .mild)
    }

    @Test("levelRaw 不合法时降级到 .relaxed,不崩溃")
    func corruptLevelRawDoesNotCrash() {
        let entry = StressEntry(
            bpm: 75,
            scoreValue: 60,
            levelRaw: "garbage_value"
        )
        #expect(entry.level == .relaxed)
    }

    @Test("默认值:hrv 可选,activityState 可选")
    func defaultsValid() {
        let entry = StressEntry(bpm: 70, scoreValue: 50, levelRaw: "relaxed")
        #expect(entry.hrv == nil)
        #expect(entry.activityStateRaw == nil)
    }
}

@Suite("WCMessageKeys 双端通信契约")
struct WCMessageKeysTests {

    @Test("关键消息 key 不为空,且唯一")
    func nonEmptyKeys() {
        #expect(!WCMessageKeys.heartRate.isEmpty)
        #expect(!WCMessageKeys.isMonitoring.isEmpty)
        #expect(WCMessageKeys.heartRate != WCMessageKeys.isMonitoring)
    }
}
