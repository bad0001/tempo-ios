//
//  MentalHealthSurvey.swift
//  TempoCore
//
//  GAD-7 / PHQ-9 / PSS-10 心理健康自评量表结果。
//  本机 SwiftData 持久化,绝不上传服务器。
//
//  学术依据:
//   - GAD-7: Spitzer 2006 Arch Intern Med(广泛焦虑评分 0-21)
//   - PHQ-9: Kroenke 2001 J Gen Intern Med(抑郁评分 0-27)
//   - PSS-10: Cohen 1983 J Health Soc Behav(感知压力 0-40)
//

import Foundation
import SwiftData

public enum SurveyKind: String, Codable, Sendable, CaseIterable, Identifiable {
    public var id: String { rawValue }
    case gad7
    case phq9
    case pss10

    public var displayName: String {
        switch self {
        case .gad7: "GAD-7 焦虑自评"
        case .phq9: "PHQ-9 抑郁自评"
        case .pss10: "PSS-10 压力感知"
        }
    }

    public var subtitle: String {
        switch self {
        case .gad7: "过去 2 周,你被这些问题困扰的频率"
        case .phq9: "过去 2 周,你被以下问题困扰的频率"
        case .pss10: "过去 1 个月,你感觉如何"
        }
    }

    public var scoreMax: Int {
        switch self {
        case .gad7: 21
        case .phq9: 27
        case .pss10: 40
        }
    }

    /// 临床切点(基于学术建议)
    public func interpretation(score: Int) -> SurveyInterpretation {
        switch self {
        case .gad7:
            switch score {
            case 0...4: return SurveyInterpretation(severity: .minimal, label: "轻微", advice: "焦虑水平很低,继续保持。")
            case 5...9: return SurveyInterpretation(severity: .mild, label: "轻度", advice: "轻度焦虑信号,可尝试呼吸训练或冥想。")
            case 10...14: return SurveyInterpretation(severity: .moderate, label: "中度", advice: "建议寻求心理专业人士帮助。")
            default: return SurveyInterpretation(severity: .severe, label: "重度", advice: "强烈建议尽快联系心理医生。")
            }
        case .phq9:
            switch score {
            case 0...4: return SurveyInterpretation(severity: .minimal, label: "轻微", advice: "情绪健康,继续保持。")
            case 5...9: return SurveyInterpretation(severity: .mild, label: "轻度", advice: "轻度低落,关注情绪和睡眠。")
            case 10...14: return SurveyInterpretation(severity: .moderate, label: "中度", advice: "建议与心理咨询师谈谈。")
            case 15...19: return SurveyInterpretation(severity: .severe, label: "中重度", advice: "建议尽快就诊。")
            default: return SurveyInterpretation(severity: .severe, label: "重度", advice: "请立即联系专业医疗机构。")
            }
        case .pss10:
            switch score {
            case 0...13: return SurveyInterpretation(severity: .minimal, label: "轻微", advice: "压力水平正常。")
            case 14...26: return SurveyInterpretation(severity: .moderate, label: "中度", advice: "压力较高,关注休息与放松。")
            default: return SurveyInterpretation(severity: .severe, label: "高压力", advice: "建议咨询专业人士。")
            }
        }
    }
}

public struct SurveyInterpretation: Codable, Hashable, Sendable {
    public let severity: SurveySeverity
    public let label: String
    public let advice: String

    public init(severity: SurveySeverity, label: String, advice: String) {
        self.severity = severity
        self.label = label
        self.advice = advice
    }
}

public enum SurveySeverity: String, Codable, Sendable {
    case minimal
    case mild
    case moderate
    case severe
}

@Model
public final class MentalHealthSurveyResult {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var kindRaw: String = SurveyKind.gad7.rawValue
    public var score: Int = 0
    /// JSON 编码的逐题分数(0-3 或 0-4)
    public var rawAnswersJSON: String = "[]"
    /// 严重程度 raw
    public var severityRaw: String = SurveySeverity.minimal.rawValue
    /// 用户附注
    public var note: String = ""

    public var kind: SurveyKind {
        SurveyKind(rawValue: kindRaw) ?? .gad7
    }

    public var severity: SurveySeverity {
        SurveySeverity(rawValue: severityRaw) ?? .minimal
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        kind: SurveyKind,
        score: Int,
        answers: [Int],
        severity: SurveySeverity,
        note: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.score = score
        self.severityRaw = severity.rawValue
        self.rawAnswersJSON = (try? JSONEncoder().encode(answers))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.note = note
    }
}

// MARK: - Standard questionnaires

public enum SurveyQuestions {
    public static let gad7: [String] = [
        "感到紧张、焦虑或急躁",
        "无法停止或控制担忧",
        "对各种各样的事情担忧过多",
        "难以放松",
        "因为不安难以静坐",
        "变得容易烦恼或急躁",
        "感到害怕,似乎将有可怕的事情发生"
    ]

    public static let phq9: [String] = [
        "做事时提不起兴趣或没有乐趣",
        "感到心情低落、沮丧或绝望",
        "入睡困难、睡不安稳或睡得过多",
        "感觉疲倦或没有活力",
        "食欲不振或吃得过多",
        "觉得自己很糟,或觉得让自己或家人失望",
        "对事物专注有困难,比如看报或看电视",
        "动作或说话缓慢到别人注意到,或反之坐立不安、烦躁",
        "有不如死了或自残的念头"
    ]

    public static let pss10: [String] = [
        "因为发生了出乎意料的事而感到心烦",
        "感到无法控制生活中的重要事情",
        "感到紧张和压力",
        "对处理私人问题的能力有信心",                        // 反向
        "感到事情正在按你希望的方向进行",                    // 反向
        "发现自己无法应对必须要处理的所有事情",
        "能够控制生活中的烦恼",                              // 反向
        "感到自己掌控全局",                                  // 反向
        "因为发生了无法控制的事情而生气",
        "感到困难积累到无法克服"
    ]

    /// PSS-10 反向计分的题目索引(0-based)
    public static let pss10ReverseItems: Set<Int> = [3, 4, 6, 7]

    public static func questions(for kind: SurveyKind) -> [String] {
        switch kind {
        case .gad7: return gad7
        case .phq9: return phq9
        case .pss10: return pss10
        }
    }

    /// GAD-7 / PHQ-9 答案范围 0-3,PSS-10 是 0-4(频率档位)
    public static func answerRange(for kind: SurveyKind) -> ClosedRange<Int> {
        switch kind {
        case .gad7, .phq9: return 0...3
        case .pss10: return 0...4
        }
    }

    public static func answerLabels(for kind: SurveyKind) -> [String] {
        switch kind {
        case .gad7, .phq9: return ["完全没有", "几天", "一半以上时间", "几乎每天"]
        case .pss10: return ["从不", "偶尔", "有时", "经常", "总是"]
        }
    }

    /// 计算总分(PSS-10 处理反向计分)
    public static func computeScore(answers: [Int], kind: SurveyKind) -> Int {
        switch kind {
        case .gad7, .phq9:
            return answers.reduce(0, +)
        case .pss10:
            var total = 0
            for (i, v) in answers.enumerated() {
                total += pss10ReverseItems.contains(i) ? (4 - v) : v
            }
            return total
        }
    }
}
