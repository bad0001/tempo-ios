import Foundation

public struct StressScore: Codable, Hashable, Sendable {
    public let value: Int
    public let level: StressLevel
    public let timestamp: Date

    public init(value: Int, timestamp: Date = .now) {
        let clamped = max(0, min(100, value))
        self.value = clamped
        self.level = StressLevel(score: clamped)
        self.timestamp = timestamp
    }
}

public enum StressLevel: String, Codable, Sendable, CaseIterable {
    case calm
    case relaxed
    case mild
    case high
    case extreme

    public init(score: Int) {
        switch score {
        case ...25: self = .calm
        case 26...50: self = .relaxed
        case 51...70: self = .mild
        case 71...85: self = .high
        default: self = .extreme
        }
    }

    public var displayName: String {
        switch self {
        case .calm: "平静"
        case .relaxed: "放松"
        case .mild: "轻度"
        case .high: "较高"
        case .extreme: "极高"
        }
    }

    public var displayNameEnglish: String {
        switch self {
        case .calm: "Calm"
        case .relaxed: "Relaxed"
        case .mild: "Mild"
        case .high: "High"
        case .extreme: "Extreme"
        }
    }
}
