import Testing
import Foundation
@testable import TempoCore

@Suite("WristTempStats")
struct WristTempStatsTests {
    @Test("样本不足 → !isConfident,无惩罚")
    func lowSampleCount() {
        let s = WristTempStats(lastNightDeviationC: 0.5, baselineMean: 0, baselineStddev: 0.2, sampleCount: 3)
        #expect(!s.isConfident)
        #expect(s.recoveryPenalty == 0)
    }

    @Test("正常 z<1 → 不扣分")
    func normalRange() {
        let s = WristTempStats(lastNightDeviationC: 0.1, baselineMean: 0, baselineStddev: 0.2, sampleCount: 14)
        #expect(s.isConfident)
        // z = 0.5,abs < 1 → 0
        #expect(s.recoveryPenalty == 0)
    }

    @Test("|z|=1.5 → 7.5 分扣")
    func halfWayPenalty() {
        let s = WristTempStats(lastNightDeviationC: 0.3, baselineMean: 0, baselineStddev: 0.2, sampleCount: 14)
        // z = 1.5 → (1.5-1)*15 = 7.5
        #expect(abs(s.recoveryPenalty - 7.5) < 0.01)
    }

    @Test("|z|=2 → 满扣 15 分,isElevated")
    func maxPenalty() {
        let s = WristTempStats(lastNightDeviationC: 0.4, baselineMean: 0, baselineStddev: 0.2, sampleCount: 14)
        // z = 2 → 15
        #expect(s.recoveryPenalty == 15)
        #expect(s.isElevated)
    }

    @Test("|z|>2 → 仍 15 分(不爆)")
    func cappedPenalty() {
        let s = WristTempStats(lastNightDeviationC: 1.0, baselineMean: 0, baselineStddev: 0.2, sampleCount: 14)
        // z = 5 → 仍 15
        #expect(s.recoveryPenalty == 15)
    }
}

@Suite("SleepStageHours")
struct SleepStageHoursTests {
    @Test("理想 8 小时含 1.5h deep + 1.5h REM → 高分")
    func idealSleep() {
        let s = SleepStageHours(deep: 1.5, rem: 1.5, core: 5, awake: 0.5, unspecified: 0)
        // deepScore=100, remScore=100, durationScore=100
        // sleepScore = 0.35*100 + 0.25*100 + 0.4*100 = 100
        #expect(s.sleepScore >= 99)
    }

    @Test("无 deep 无 REM → 显著低分")
    func noDeepNoREM() {
        let s = SleepStageHours(deep: 0, rem: 0, core: 8, awake: 0, unspecified: 0)
        // deepScore=0, remScore=0, durationScore=100
        // = 0+0+40 = 40
        #expect(s.sleepScore < 50)
    }

    @Test("4 小时浅睡 → 极低分")
    func shortBadSleep() {
        let s = SleepStageHours(deep: 0.3, rem: 0.3, core: 3.4, awake: 0.5, unspecified: 0)
        // 总 4h,deep 20%,rem 20%,duration 50%
        // = 0.35*20 + 0.25*20 + 0.4*50 = 7+5+20 = 32
        #expect(s.sleepScore < 50)
    }

    @Test("hasStageData 检测")
    func stageDataPresence() {
        let none = SleepStageHours.unknown
        #expect(!none.hasStageData)
        let some = SleepStageHours(deep: 0.5, rem: 0, core: 0, awake: 0, unspecified: 0)
        #expect(some.hasStageData)
    }
}

@Suite("Recovery v3")
struct RecoveryV3Tests {
    @Test("无 stages + 无 temp → 老公式行为")
    func backwardCompat() {
        let r = Recovery(
            overnightHRV: 50, baselineHRV: 50,
            lastNightRHR: 60, baselineRHR: 60,
            sleepHours: 8
        )
        // baseline-perfect:0.5*100 + 0.3*100 + 0.2*100 = 100
        #expect(r.value >= 95)
        #expect(r.wristTempZScore == nil)
    }

    @Test("有 stages 时用 stage 加权 sleep score")
    func withStages() {
        let stages = SleepStageHours(deep: 0, rem: 0, core: 8, awake: 0, unspecified: 0)
        let r = Recovery(
            overnightHRV: 50, baselineHRV: 50,
            lastNightRHR: 60, baselineRHR: 60,
            sleepHours: 8,
            sleepStages: stages
        )
        // sleep stage 给 40 分而非 100 → recovery 比 backwardCompat 低
        #expect(r.value < 90)
    }

    @Test("体温显著偏高 → recovery 扣分")
    func tempPenalty() {
        let tempStats = WristTempStats(lastNightDeviationC: 0.4, baselineMean: 0, baselineStddev: 0.2, sampleCount: 14)
        let r = Recovery(
            overnightHRV: 50, baselineHRV: 50,
            lastNightRHR: 60, baselineRHR: 60,
            sleepHours: 8,
            wristTempStats: tempStats
        )
        // 100 - 15 = 85
        #expect(r.value < 90)
        #expect(r.hasElevatedTemp)
    }
}

@Suite("ECGMetrics")
struct ECGMetricsTests {
    @Test("低样本 → unknown")
    func tooFewRR() {
        let m = ECGMetrics(rrIntervalsMs: [800, 810])
        #expect(m.sdnn == 0)
        #expect(m.rmssd == 0)
        #expect(!m.isConfident)
    }

    @Test("规则 RR → RMSSD 计算正确")
    func rmssdFormula() {
        // RR: [800, 820, 800, 820, 800] → diff: [20, -20, 20, -20] → 平方均值 = 400
        // RMSSD = sqrt(400) = 20
        let rrs = [800.0, 820, 800, 820, 800]
        let m = ECGMetrics(rrIntervalsMs: rrs)
        #expect(abs(m.rmssd - 20.0) < 1.0)
    }

    @Test("pNN50 计算")
    func pnn50Formula() {
        // RR diff [70, -70, 60, -60] → 4 个都 >50 → pNN50 = 100
        let rrs = [800.0, 870, 800, 860, 800]
        let m = ECGMetrics(rrIntervalsMs: rrs)
        #expect(m.pnn50 == 100)
    }

    @Test("avgHeartRate from meanRR")
    func bpmFromRR() {
        let rrs = Array(repeating: 1000.0, count: 30)
        let m = ECGMetrics(rrIntervalsMs: rrs)
        // 1000ms → 60bpm
        #expect(abs(m.avgHeartRate - 60.0) < 0.1)
    }
}

@Suite("Mental Health Surveys")
struct MentalHealthSurveysTests {
    @Test("GAD-7 分数加总")
    func gad7Score() {
        let answers = [3, 3, 3, 3, 3, 3, 3]   // 全选最严重
        let score = SurveyQuestions.computeScore(answers: answers, kind: .gad7)
        #expect(score == 21)   // 满分
        #expect(SurveyKind.gad7.interpretation(score: score).severity == .severe)
    }

    @Test("GAD-7 轻度 5-9 分")
    func gad7Mild() {
        let answers = [1, 1, 1, 1, 1, 1, 1]   // 7 × 1 = 7
        let score = SurveyQuestions.computeScore(answers: answers, kind: .gad7)
        #expect(score == 7)
        #expect(SurveyKind.gad7.interpretation(score: score).severity == .mild)
    }

    @Test("PHQ-9 重度切点")
    func phq9Severe() {
        let answers = [3, 3, 3, 3, 3, 3, 0, 0, 0]   // 18 分
        let score = SurveyQuestions.computeScore(answers: answers, kind: .phq9)
        #expect(score == 18)
        #expect(SurveyKind.phq9.interpretation(score: score).severity == .severe)
    }

    @Test("PSS-10 反向计分")
    func pss10Reverse() {
        // 4 个反向题(idx 3, 4, 6, 7)填 0,其余 4 分
        // 反向后:idx 3,4,6,7 都变 4;非反向都 4 → 总 40 满分
        let answers = [4, 4, 4, 0, 0, 4, 0, 0, 4, 4]
        let score = SurveyQuestions.computeScore(answers: answers, kind: .pss10)
        #expect(score == 40)
    }

    @Test("PSS-10 全 0 答案(因含反向)= 16 分,不是 0")
    func pss10AllZero() {
        let answers = Array(repeating: 0, count: 10)
        let score = SurveyQuestions.computeScore(answers: answers, kind: .pss10)
        // 6 个非反向题 0,4 个反向题 (4-0)=4 → 0+16 = 16
        #expect(score == 16)
    }

    @Test("题目数量正确")
    func questionCount() {
        #expect(SurveyQuestions.gad7.count == 7)
        #expect(SurveyQuestions.phq9.count == 9)
        #expect(SurveyQuestions.pss10.count == 10)
    }
}

@Suite("MoodEntry borg field")
struct MoodEntryBorgTests {
    @Test("默认 init 无 borg")
    func defaultNoBorg() {
        let e = MoodEntry(timestamp: .now, mood: .neutral, tags: [], note: "")
        #expect(e.borgSubjective == nil)
    }

    @Test("显式 borg 保留")
    func withBorg() {
        let e = MoodEntry(timestamp: .now, mood: .neutral, tags: [], note: "", borgSubjective: 7)
        #expect(e.borgSubjective == 7)
    }
}
