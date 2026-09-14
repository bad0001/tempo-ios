//
//  MoodEntry.swift
//  TempoCore
//
//  用户主动记录的「感受 + 影响因素」。
//  跟 StressEntry 共享一个 ModelContainer (App Group),所以放 TempoCore.
//
//  v2:记录 mood 时同步快照当前 HR/HRV/RR/activity/stress + age,
//  作为「主观 label + 客观 features」配对,供未来本机 ML 模型训练用。
//  这些 feature 字段只在本机 SwiftData,不上传。
//

import Foundation
import SwiftData

@Model
public final class MoodEntry {
    public var timestamp: Date = Date()
    public var moodRaw: String = MoodLevel.neutral.rawValue
    public var tags: [String] = []
    public var note: String = ""

    // MARK: - ML feature snapshot(本机)
    /// 记录此 mood 时的客观特征 — 全部为可选,可能数据不全。
    public var hrAtLog: Double?
    public var hrvAtLog: Double?
    public var rrAtLog: Double?
    public var stressScoreAtLog: Int?
    /// ActivityState.rawValue
    public var activityRawAtLog: String?
    /// 最近 24h 是否在睡眠中(0 = 否, 1 = 是)
    public var wasAsleepRecently: Bool?
    /// 用户年龄(snapshot 时,profile 改了不影响历史)
    public var ageAtLog: Int?
    /// gender raw
    public var genderRawAtLog: String?
    /// 算法版本号(future-proof)
    public var algorithmVersionAtLog: Int?
    /// 主观 Borg CR-10 身体感受(0-10,0=完全平静,10=极度紧张/疲惫)
    /// 给 PersonalStressModel 当 label
    public var borgSubjective: Int?

    public var mood: MoodLevel {
        MoodLevel(rawValue: moodRaw) ?? .neutral
    }

    public var moodTags: [MoodTag] {
        tags.compactMap { MoodTag(rawValue: $0) }
    }

    public init(
        timestamp: Date = .now,
        mood: MoodLevel = .neutral,
        tags: [String] = [],
        note: String = "",
        hrAtLog: Double? = nil,
        hrvAtLog: Double? = nil,
        rrAtLog: Double? = nil,
        stressScoreAtLog: Int? = nil,
        activityRawAtLog: String? = nil,
        wasAsleepRecently: Bool? = nil,
        ageAtLog: Int? = nil,
        genderRawAtLog: String? = nil,
        algorithmVersionAtLog: Int? = nil,
        borgSubjective: Int? = nil
    ) {
        self.timestamp = timestamp
        self.moodRaw = mood.rawValue
        self.tags = tags
        self.note = note
        self.hrAtLog = hrAtLog
        self.hrvAtLog = hrvAtLog
        self.rrAtLog = rrAtLog
        self.stressScoreAtLog = stressScoreAtLog
        self.activityRawAtLog = activityRawAtLog
        self.wasAsleepRecently = wasAsleepRecently
        self.ageAtLog = ageAtLog
        self.genderRawAtLog = genderRawAtLog
        self.algorithmVersionAtLog = algorithmVersionAtLog
        self.borgSubjective = borgSubjective
    }
}

// MARK: - Mood Level

public enum MoodLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case great
    case good
    case neutral
    case low
    case anxious
    case tired

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .great: "状态超棒"
        case .good: "心情不错"
        case .neutral: "还算平静"
        case .low: "有点低落"
        case .anxious: "有些焦虑"
        case .tired: "比较疲惫"
        }
    }

    public var emoji: String {
        switch self {
        case .great: "😄"
        case .good: "🙂"
        case .neutral: "😐"
        case .low: "😟"
        case .anxious: "😰"
        case .tired: "😴"
        }
    }

    /// -2 (差) 到 +2 (好) 的情绪量化分,用于 AI 教练分析
    public var score: Int {
        switch self {
        case .great: 2
        case .good: 1
        case .neutral: 0
        case .low: -1
        case .anxious: -2
        case .tired: -1
        }
    }
}

// MARK: - Mood Tag

public enum MoodTag: String, Codable, Sendable, CaseIterable, Identifiable {
    case caffeine
    case alcohol
    case work
    case period
    case insomnia
    case exercise
    case meditation
    case socializing
    case argument
    case news
    case nature
    case music

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .caffeine: "咖啡因"
        case .alcohol: "饮酒"
        case .work: "工作"
        case .period: "例假"
        case .insomnia: "失眠"
        case .exercise: "运动"
        case .meditation: "冥想"
        case .socializing: "社交"
        case .argument: "争吵"
        case .news: "刷新闻"
        case .nature: "亲近自然"
        case .music: "听音乐"
        }
    }

    public var emoji: String {
        switch self {
        case .caffeine: "☕️"
        case .alcohol: "🍷"
        case .work: "💼"
        case .period: "🩸"
        case .insomnia: "🌙"
        case .exercise: "🏃"
        case .meditation: "🧘"
        case .socializing: "👯"
        case .argument: "💢"
        case .news: "📰"
        case .nature: "🌿"
        case .music: "🎵"
        }
    }

    /// 对压力 / 节奏的影响倾向(用于 AI 教练判断要不要建议改变)
    public var pressureImpact: Impact {
        switch self {
        case .exercise, .meditation, .nature, .music, .socializing: .positive
        case .caffeine, .alcohol, .insomnia, .argument, .news, .work: .negative
        case .period: .neutral
        }
    }

    public enum Impact: String, Sendable {
        case positive, neutral, negative
    }
}
