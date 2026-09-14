import Foundation

public struct BreathingPattern: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let displayNameEnglish: String
    public let descriptionText: String
    public let inhale: Double
    public let hold1: Double
    public let exhale: Double
    public let hold2: Double
    public let isPro: Bool

    public var cycleDuration: Double {
        inhale + hold1 + exhale + hold2
    }

    public init(
        id: String,
        displayName: String,
        displayNameEnglish: String,
        descriptionText: String,
        inhale: Double,
        hold1: Double = 0,
        exhale: Double,
        hold2: Double = 0,
        isPro: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.displayNameEnglish = displayNameEnglish
        self.descriptionText = descriptionText
        self.inhale = inhale
        self.hold1 = hold1
        self.exhale = exhale
        self.hold2 = hold2
        self.isPro = isPro
    }
}

public extension BreathingPattern {
    static let coherent = BreathingPattern(
        id: "coherent",
        displayName: "等长呼吸",
        displayNameEnglish: "Coherent Breathing",
        descriptionText: "吸呼各 5 秒,日常放松最简单",
        inhale: 5, exhale: 5
    )

    static let fourSevenEight = BreathingPattern(
        id: "4-7-8",
        displayName: "4-7-8 呼吸",
        displayNameEnglish: "4-7-8 Breathing",
        descriptionText: "经典安神节奏:吸 4 秒、屏 7 秒、呼 8 秒",
        inhale: 4, hold1: 7, exhale: 8
    )

    static let boxBreathing = BreathingPattern(
        id: "box",
        displayName: "盒式呼吸",
        displayNameEnglish: "Box Breathing",
        descriptionText: "海豹突击队同款,吸-屏-呼-屏 各 4 秒",
        inhale: 4, hold1: 4, exhale: 4, hold2: 4
    )

    static let resonant = BreathingPattern(
        id: "resonant",
        displayName: "共振呼吸",
        displayNameEnglish: "Resonant Breathing",
        descriptionText: "5.5 BPM 慢节奏,显著提升 HRV",
        inhale: 5.5, exhale: 5.5,
        isPro: true
    )

    static let wimHof = BreathingPattern(
        id: "wim-hof",
        displayName: "Wim Hof 呼吸",
        displayNameEnglish: "Wim Hof Method",
        descriptionText: "深快呼吸 30 次后憋气,激活交感神经",
        inhale: 1.5, exhale: 1.5,
        isPro: true
    )

    static let buteyko = BreathingPattern(
        id: "buteyko",
        displayName: "布泰科呼吸",
        displayNameEnglish: "Buteyko Breathing",
        descriptionText: "浅缓呼吸,降低呼吸频率提升耐受",
        inhale: 4, exhale: 6,
        isPro: true
    )

    static let allPresets: [BreathingPattern] = [
        .coherent,
        .fourSevenEight,
        .boxBreathing,
        .resonant,
        .wimHof,
        .buteyko
    ]

    static let freePresets: [BreathingPattern] = allPresets.filter { !$0.isPro }
    static let proPresets: [BreathingPattern] = allPresets.filter { $0.isPro }
}
