import Foundation

public struct HeartRateReading: Codable, Hashable, Sendable {
    public let bpm: Double
    public let timestamp: Date

    public init(bpm: Double, timestamp: Date = .now) {
        self.bpm = bpm
        self.timestamp = timestamp
    }
}
