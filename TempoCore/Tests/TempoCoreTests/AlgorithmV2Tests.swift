import Testing
import Foundation
@testable import TempoCore

@Suite("UserProfile")
struct UserProfileTests {
    @Test("clamp 年龄范围")
    func clampAge() {
        let young = UserProfile(age: 5)
        #expect(young.age == 12)
        let old = UserProfile(age: 200)
        #expect(old.age == 100)
    }

    @Test("Tanaka maxHR 公式")
    func tanakaMaxHR() {
        let twenty = UserProfile(age: 20)
        #expect(twenty.estimatedMaxHR == 208 - 0.7 * 20)
        let sixty = UserProfile(age: 60)
        #expect(sixty.estimatedMaxHR == 208 - 0.7 * 60)
        let veryOld = UserProfile(age: 100)
        // 208 - 70 = 138,但 clamp 到 140
        #expect(veryOld.estimatedMaxHR == 140)
    }

    @Test("isPregnant / hasCardiacCondition")
    func conditions() {
        let pregnant = UserProfile(conditions: ["pregnancy"])
        #expect(pregnant.isPregnant)
        #expect(!pregnant.hasCardiacCondition)

        let heart = UserProfile(conditions: ["arrhythmia"])
        #expect(heart.hasCardiacCondition)
        #expect(!heart.isPregnant)
    }
}

@Suite("BaselineStats")
struct BaselineStatsTests {
    @Test("低样本 → 不可信")
    func lowSamples() {
        let s = BaselineStats(hrMean: 70, hrStddev: 5, hrvMean: 50, hrvStddev: 10, sampleCount: 20)
        #expect(!s.isConfident)
    }

    @Test("50 样本起步 → 可信")
    func enoughSamples() {
        let s = BaselineStats(hrMean: 70, hrStddev: 5, hrvMean: 50, hrvStddev: 10, sampleCount: 50)
        #expect(s.isConfident)
    }

    @Test("z-score 计算 / 防除零")
    func zScore() {
        let s = BaselineStats(hrMean: 70, hrStddev: 5, hrvMean: 50, hrvStddev: 10, sampleCount: 100)
        #expect(s.hrZScore(70) == 0)
        #expect(s.hrZScore(75) == 1.0)
        #expect(s.hrZScore(80) == 2.0)
        #expect(s.hrvZScore(40) == -1.0)
    }

    @Test("stddev=0 不会除零")
    func stddevZeroFloor() {
        // 传入 0 → 内部 floor 到 2
        let s = BaselineStats(hrMean: 70, hrStddev: 0, hrvMean: 50, hrvStddev: 0, sampleCount: 100)
        #expect(s.hrStddev >= 2)
        #expect(s.hrvStddev >= 2)
        // 算 z 不会 NaN
        #expect(s.hrZScore(80).isFinite)
    }
}

@Suite("CircadianAdjustment")
struct CircadianAdjustmentTests {
    @Test("凌晨 4 点最高 + 清晨 7 点不再是最高")
    func dailyPeakTrough() {
        let h04 = CircadianAdjustment.adjustment(forHour: 4)
        let h07 = CircadianAdjustment.adjustment(forHour: 7)
        let h14 = CircadianAdjustment.adjustment(forHour: 14)
        // h=4 是 cosine 主峰 (+5),h=14 是主谷 (-5);h=7 在 7 附近介于两者之间
        #expect(h04 > h14)
        #expect(h04 > h07)
    }

    @Test("24h 整数总和 ≈ 0(全天均值不变)")
    func zeroMeanDaily() {
        let total = (0..<24).map { CircadianAdjustment.adjustment(forHour: $0) }.reduce(0, +)
        // cosine 24 整点和应该约 0(浮点误差容忍 1)
        #expect(abs(total) < 1.0)
    }

    @Test("曲线连续 — 邻近小时差异 < 3")
    func smooth() {
        for h in 0..<23 {
            let diff = abs(CircadianAdjustment.adjustment(forHour: h) - CircadianAdjustment.adjustment(forHour: h + 1))
            #expect(diff < 3.0)
        }
    }
}

@Suite("HRVPhasic")
struct HRVPhasicTests {
    @Test("ratio < 0.7 = 急性应激,加分")
    func acuteStress() {
        let p = HRVPhasic(recent60minMean: 25, tonicBaseline: 50, recentSampleCount: 5)
        #expect(p.isAcuteStress)
        #expect(p.stressAdjustment > 0)
    }

    @Test("ratio > 1.3 = 急性放松,减分")
    func acuteCalm() {
        let p = HRVPhasic(recent60minMean: 75, tonicBaseline: 50, recentSampleCount: 5)
        #expect(p.isAcuteCalm)
        #expect(p.stressAdjustment < 0)
    }

    @Test("正常区间 → 0")
    func neutral() {
        let p = HRVPhasic(recent60minMean: 50, tonicBaseline: 50, recentSampleCount: 5)
        #expect(p.stressAdjustment == 0)
    }

    @Test("样本数不足 → isConfident=false 不影响分数")
    func notConfident() {
        let p = HRVPhasic(recent60minMean: 25, tonicBaseline: 50, recentSampleCount: 1)
        #expect(!p.isConfident)
        #expect(p.stressAdjustment == 0)
    }
}

@Suite("StressEvaluator v2 z-score")
struct StressEvaluatorV2Tests {
    @Test("baseline mean → score 接近 50")
    func atMean() {
        let stats = BaselineStats(hrMean: 70, hrStddev: 5, hrvMean: 50, hrvStddev: 10, sampleCount: 100)
        let eval = StressEvaluator()
        let score = eval.evaluate(
            heartRate: 70, hrv: 50,
            stats: stats,
            circadianEnabled: false
        )
        #expect(abs(score.value - 50) <= 5)
    }

    @Test("hr +1σ 显著加分")
    func hrPlusOneSigma() {
        let stats = BaselineStats(hrMean: 70, hrStddev: 5, hrvMean: 50, hrvStddev: 10, sampleCount: 100)
        let eval = StressEvaluator()
        let base = eval.evaluate(heartRate: 70, hrv: 50, stats: stats, circadianEnabled: false).value
        let high = eval.evaluate(heartRate: 75, hrv: 50, stats: stats, circadianEnabled: false).value
        #expect(high > base + 4)   // +1σ 应当加 5-8 分
    }

    @Test("hrv -1σ 显著加分(HRV ↓ = stress ↑)")
    func hrvMinusOneSigma() {
        let stats = BaselineStats(hrMean: 70, hrStddev: 5, hrvMean: 50, hrvStddev: 10, sampleCount: 100)
        let eval = StressEvaluator()
        let base = eval.evaluate(heartRate: 70, hrv: 50, stats: stats, circadianEnabled: false).value
        let low = eval.evaluate(heartRate: 70, hrv: 40, stats: stats, circadianEnabled: false).value
        #expect(low > base + 4)
    }

    @Test("stats 不可信 → fallback v1")
    func fallbackV1() {
        let stats = BaselineStats(hrMean: 0, hrStddev: 0, hrvMean: 0, hrvStddev: 0, sampleCount: 10)
        let eval = StressEvaluator(baseline: PersonalBaseline(restingHeartRate: 60, averageHRV: 50))
        // v1 路径:80 - 60 = 20 → +20*0.8 = +16,score = 66
        let score = eval.evaluate(
            heartRate: 80, hrv: 50,
            stats: stats,
            circadianEnabled: false
        )
        #expect(score.value > 60)
        #expect(score.value < 75)
    }

    @Test("phasic 急性应激额外加分")
    func phasicBonus() {
        let stats = BaselineStats(hrMean: 70, hrStddev: 5, hrvMean: 50, hrvStddev: 10, sampleCount: 100)
        let phasic = HRVPhasic(recent60minMean: 25, tonicBaseline: 50, recentSampleCount: 5)
        let eval = StressEvaluator()
        let base = eval.evaluate(heartRate: 70, hrv: 50, stats: stats, circadianEnabled: false).value
        let withPhasic = eval.evaluate(heartRate: 70, hrv: 50, stats: stats, hrvPhasic: phasic, circadianEnabled: false).value
        #expect(withPhasic > base)
    }

    @Test("circadian on/off 差异")
    func circadianToggle() {
        let stats = BaselineStats(hrMean: 70, hrStddev: 5, hrvMean: 50, hrvStddev: 10, sampleCount: 100)
        let eval = StressEvaluator()
        let morning4am = Calendar.current.date(bySettingHour: 4, minute: 0, second: 0, of: Date())!
        let on = eval.evaluate(heartRate: 70, hrv: 50, stats: stats, timestamp: morning4am, circadianEnabled: true).value
        let off = eval.evaluate(heartRate: 70, hrv: 50, stats: stats, timestamp: morning4am, circadianEnabled: false).value
        #expect(on != off)
    }
}

@Suite("Strain personalized")
struct StrainPersonalizedTests {
    @Test("不同年龄同样负荷 → 老年 strain 偏低(maxHR 低,intensity 反而高,但 elevated 阈值不变)")
    func ageImpact() {
        let readings = (0..<60).map { i in
            HeartRateReading(bpm: 140, timestamp: Date().addingTimeInterval(Double(i)))
        }
        let young = Strain(readings: readings, restingHeartRate: 60, profile: UserProfile(age: 20))
        let old = Strain(readings: readings, restingHeartRate: 60, profile: UserProfile(age: 70))
        // 20 岁 maxHR = 208 - 14 = 194,hrRange = 194 - 60 = 134,intensity 140 ≈ 0.6
        // 70 岁 maxHR = 208 - 49 = 159,hrRange = 159 - 60 = 99,intensity 140 ≈ 0.81
        // intensity² 累计 → 老的更高
        #expect(old.value > young.value)
    }

    @Test("nil profile fallback 到 30 岁默认")
    func nilProfileFallback() {
        let readings = (0..<60).map { _ in HeartRateReading(bpm: 130) }
        let nilProfile = Strain(readings: readings, restingHeartRate: 60, profile: nil)
        // 老接口 estimatedAge: 30
        let deprecatedDefault = Strain(readings: readings, restingHeartRate: 60, profile: UserProfile(age: 30))
        // 两个分数应一致(maxHR 都 190 vs Tanaka 208-21=187,稍微差但接近)
        // 注意 fallback nil 用 220-30=190,而 UserProfile(30) 用 Tanaka 187
        // 所以会有微差,但都在 ±0.5 范围
        #expect(abs(nilProfile.value - deprecatedDefault.value) < 1.0)
    }
}

@Suite("AlgorithmVersion")
struct AlgorithmVersionTests {
    @Test("当前版本 ≥ 2")
    func currentBumped() {
        #expect(AlgorithmVersion.current >= 2)
    }
}
