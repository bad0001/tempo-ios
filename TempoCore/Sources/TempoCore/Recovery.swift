import Foundation

public struct Recovery: Codable, Hashable, Sendable {
    /// 0-100,当日恢复分
    public let value: Int
    public let level: RecoveryLevel
    /// HRV 相对 baseline 的偏移 %(正值 = 高于 baseline)
    public let hrvDelta: Double
    /// RHR 相对 baseline 的偏移 %(正值 = 低于 baseline,即更恢复)
    public let rhrDelta: Double
    /// 睡眠总时长(小时)
    public let sleepHours: Double
    /// 体温 z-score(可选,Watch S8+/Ultra 才有)
    public let wristTempZScore: Double?
    /// 睡眠分期数据(可选)
    public let sleepStages: SleepStageHours?
    public let timestamp: Date

    public init(
        overnightHRV: Double?,
        baselineHRV: Double,
        lastNightRHR: Double?,
        baselineRHR: Double,
        sleepHours: Double,
        sleepStages: SleepStageHours? = nil,
        wristTempStats: WristTempStats? = nil,
        timestamp: Date = .now
    ) {
        let hrvRatio: Double
        if let hrv = overnightHRV, baselineHRV > 0 {
            hrvRatio = hrv / baselineHRV
        } else {
            hrvRatio = 1.0
        }

        let rhrRatio: Double
        if let rhr = lastNightRHR, rhr > 0, baselineRHR > 0 {
            rhrRatio = baselineRHR / rhr
        } else {
            rhrRatio = 1.0
        }

        // HRV 0.5×baseline → 0 分,1.0× → 100 分,1.25× → 150(clamp)
        let hrvScore = max(0, min(100, (hrvRatio - 0.5) / 0.5 * 100))
        // RHR 0.7×baseline → 0(即心率比 baseline 高 43% = 极差),1.0× → 100
        let rhrScore = max(0, min(100, (rhrRatio - 0.7) / 0.3 * 100))

        // 睡眠分:有 stage 就用加权;无 stage fallback 到老的「时长 / 8」
        let sleepScore: Double
        if let stages = sleepStages, stages.hasStageData {
            sleepScore = stages.sleepScore
        } else {
            let sleepRatio = max(0, min(1.0, sleepHours / 8.0))
            sleepScore = sleepRatio * 100
        }

        // 加权:50% HRV + 30% RHR + 20% Sleep
        var composite = 0.5 * hrvScore + 0.3 * rhrScore + 0.2 * sleepScore

        // 体温修正:发热 / 显著偏离基线 → 扣分(最多 -15)
        if let stats = wristTempStats, stats.isConfident {
            composite -= stats.recoveryPenalty
        }

        let clamped = max(0, min(100, composite))

        self.value = Int(clamped.rounded())
        self.level = RecoveryLevel(value: self.value)
        self.hrvDelta = (hrvRatio - 1) * 100
        self.rhrDelta = (rhrRatio - 1) * 100
        self.sleepHours = sleepHours
        self.sleepStages = sleepStages
        self.wristTempZScore = wristTempStats?.zScore
        self.timestamp = timestamp
    }

    /// 数据不足时的兜底默认值(显示为 "—" 而非误导性数字)
    public static let unknown = Recovery(
        overnightHRV: nil,
        baselineHRV: 0,
        lastNightRHR: nil,
        baselineRHR: 0,
        sleepHours: 0
    )

    public var hasEnoughData: Bool {
        sleepHours > 0
    }

    /// 体温显著异常(用于 UI 提醒「可能感冒 / 过劳」)
    public var hasElevatedTemp: Bool {
        guard let z = wristTempZScore else { return false }
        return abs(z) > 1.5
    }
}

public enum RecoveryLevel: String, Codable, Sendable, CaseIterable {
    case poor
    case fair
    case good
    case excellent

    public init(value: Int) {
        switch value {
        case ...33: self = .poor
        case 34...66: self = .fair
        case 67...85: self = .good
        default: self = .excellent
        }
    }

    public var displayName: String {
        switch self {
        case .poor: "需休息"
        case .fair: "一般"
        case .good: "良好"
        case .excellent: "极佳"
        }
    }

    public var displayNameEnglish: String {
        switch self {
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }
}
