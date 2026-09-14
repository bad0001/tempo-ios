#if os(iOS)
import ActivityKit
import Foundation

public struct BreathingActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public let patternId: String
    public let patternName: String
    public let targetCycles: Int

    public init(patternId: String, patternName: String, targetCycles: Int) {
        self.patternId = patternId
        self.patternName = patternName
        self.targetCycles = targetCycles
    }

    public struct State: Codable, Hashable {
        public var phase: String
        public var phaseLabel: String
        public var remainingSeconds: Int
        public var completedCycles: Int
        public var isFinished: Bool

        public init(
            phase: String,
            phaseLabel: String,
            remainingSeconds: Int,
            completedCycles: Int,
            isFinished: Bool
        ) {
            self.phase = phase
            self.phaseLabel = phaseLabel
            self.remainingSeconds = remainingSeconds
            self.completedCycles = completedCycles
            self.isFinished = isFinished
        }
    }
}
#endif
