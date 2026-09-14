import Foundation
import SwiftData

@Model
public final class StressEntry {
    public var id: UUID
    public var timestamp: Date
    public var bpm: Double
    public var hrv: Double?
    public var scoreValue: Int
    public var levelRaw: String
    public var activityStateRaw: String?
    /// 用了哪个版本算法算出来的(便于历史分线展示)
    /// SwiftData lightweight migration 老 entry 默认 1
    public var algorithmVersion: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        bpm: Double,
        hrv: Double? = nil,
        scoreValue: Int,
        levelRaw: String,
        activityStateRaw: String? = nil,
        algorithmVersion: Int = AlgorithmVersion.current
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bpm = bpm
        self.hrv = hrv
        self.scoreValue = scoreValue
        self.levelRaw = levelRaw
        self.activityStateRaw = activityStateRaw
        self.algorithmVersion = algorithmVersion
    }

    public var level: StressLevel {
        StressLevel(rawValue: levelRaw) ?? .relaxed
    }

    public var activityState: ActivityState? {
        activityStateRaw.flatMap { ActivityState(rawValue: $0) }
    }
}
