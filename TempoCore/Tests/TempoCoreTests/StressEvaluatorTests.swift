import Testing
import Foundation
@testable import TempoCore

@Suite("StressEvaluator")
struct StressEvaluatorTests {
    let evaluator = StressEvaluator(baseline: .default)

    @Test("静息正常 HR 应判平静")
    func calmAtRest() {
        let score = evaluator.evaluate(heartRate: 60, hrv: 60)
        #expect(score.value <= 50)
    }

    @Test("HR 远高于静息应判压力上升")
    func highHRMeansHighStress() {
        let score = evaluator.evaluate(heartRate: 100, hrv: 30)
        #expect(score.value >= 60)
    }

    @Test("运动状态下高 HR 不应误判为压力")
    func exerciseNotMistakenAsStress() {
        let resting = evaluator.evaluate(heartRate: 130, hrv: 25, activityState: .resting)
        let exercising = evaluator.evaluate(heartRate: 130, hrv: 25, activityState: .exercising)
        #expect(exercising.value < resting.value)
    }

    @Test("睡眠状态下应判低压力", arguments: [40.0, 50.0, 60.0])
    func sleepIsLowStress(hr: Double) {
        let score = evaluator.evaluate(heartRate: hr, hrv: 70, activityState: .sleeping)
        #expect(score.level == .calm || score.level == .relaxed)
    }

    @Test("StressLevel 分级边界")
    func levelBoundaries() {
        #expect(StressLevel(score: 0) == .calm)
        #expect(StressLevel(score: 25) == .calm)
        #expect(StressLevel(score: 26) == .relaxed)
        #expect(StressLevel(score: 50) == .relaxed)
        #expect(StressLevel(score: 51) == .mild)
        #expect(StressLevel(score: 70) == .mild)
        #expect(StressLevel(score: 71) == .high)
        #expect(StressLevel(score: 85) == .high)
        #expect(StressLevel(score: 86) == .extreme)
        #expect(StressLevel(score: 100) == .extreme)
    }

    @Test("Score 自动 clamp 到 0-100")
    func scoreClamping() {
        #expect(StressScore(value: -10).value == 0)
        #expect(StressScore(value: 150).value == 100)
        #expect(StressScore(value: 50).value == 50)
    }

    @Test("呼吸频率偏高加分")
    func highRespiratoryRateAddsStress() {
        let normal = evaluator.evaluate(heartRate: 70, hrv: 50, respiratoryRate: 14)
        let elevated = evaluator.evaluate(heartRate: 70, hrv: 50, respiratoryRate: 22)
        #expect(elevated.value > normal.value)
    }
}
