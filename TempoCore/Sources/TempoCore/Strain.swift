import Foundation

public struct Strain: Codable, Hashable, Sendable {
    /// 0-10 日内累积负荷
    public let value: Double
    public let level: StrainLevel
    /// 心率高于 RHR 的总分钟数(粗算)
    public let elevatedMinutes: Int
    /// 平均心率
    public let averageHeartRate: Double
    /// 最高心率
    public let peakHeartRate: Double
    public let timestamp: Date

    /// v2 入口:接受 UserProfile?,自动取 age & Tanaka maxHR
    public init(
        readings: [HeartRateReading],
        restingHeartRate: Double,
        profile: UserProfile?,
        timestamp: Date = .now
    ) {
        guard !readings.isEmpty else {
            self.value = 0
            self.level = .light
            self.elevatedMinutes = 0
            self.averageHeartRate = 0
            self.peakHeartRate = 0
            self.timestamp = timestamp
            return
        }

        // v2:用户填了 profile 用 Tanaka(208 - 0.7×age),否则 fallback Tanaka 30 岁(187)
        let maxHR = (profile ?? UserProfile(age: 30)).estimatedMaxHR
        let safeRHR = max(50, restingHeartRate)
        let hrRange = max(40, maxHR - safeRHR)

        var totalPoints: Double = 0
        var elevatedCount: Int = 0
        var sumBPM: Double = 0
        var peak: Double = 0

        for reading in readings {
            sumBPM += reading.bpm
            peak = max(peak, reading.bpm)

            guard reading.bpm > safeRHR else { continue }

            let intensity = max(0, min(1.5, (reading.bpm - safeRHR) / hrRange))
            // 高强度加权(运动比静息每分钟得更多分)
            totalPoints += intensity * intensity * 2

            if reading.bpm > safeRHR * 1.15 {
                elevatedCount += 1
            }
        }

        // 对数映射到 0-10,经验缩放
        let raw = log10(totalPoints + 1) * 4.5
        self.value = max(0, min(10, raw))
        self.level = StrainLevel(value: self.value)
        self.elevatedMinutes = elevatedCount
        self.averageHeartRate = sumBPM / Double(readings.count)
        self.peakHeartRate = peak
        self.timestamp = timestamp
    }

    /// v1 backward-compat:接收 estimatedAge: Int = 30
    @available(*, deprecated, message: "Use init(readings:restingHeartRate:profile:timestamp:) — pass UserProfile instead of raw age")
    public init(
        readings: [HeartRateReading],
        restingHeartRate: Double,
        estimatedAge: Int = 30,
        timestamp: Date = .now
    ) {
        self.init(
            readings: readings,
            restingHeartRate: restingHeartRate,
            profile: UserProfile(age: estimatedAge),
            timestamp: timestamp
        )
    }

    public static let none = Strain(
        readings: [],
        restingHeartRate: 60,
        profile: nil
    )
}

public enum StrainLevel: String, Codable, Sendable, CaseIterable {
    case light
    case moderate
    case heavy
    case allOut

    public init(value: Double) {
        switch value {
        case ..<4.5: self = .light
        case 4.5..<6.5: self = .moderate
        case 6.5..<8.5: self = .heavy
        default: self = .allOut
        }
    }

    public var displayName: String {
        switch self {
        case .light: "轻度"
        case .moderate: "中度"
        case .heavy: "高度"
        case .allOut: "极限"
        }
    }

    public var displayNameEnglish: String {
        switch self {
        case .light: "Light"
        case .moderate: "Moderate"
        case .heavy: "Heavy"
        case .allOut: "All Out"
        }
    }
}
