//
//  AICoachService.swift
//  Tempo
//

import Foundation
import TempoCore
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AICoachService {
    static let shared = AICoachService()

    func ask(_ question: String, contextSummary: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                return try await askWithFoundationModels(question, contextSummary: contextSummary)
            } catch {
                return ruleBased(question: question, contextSummary: contextSummary)
            }
        }
        #endif
        return ruleBased(question: question, contextSummary: contextSummary)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func askWithFoundationModels(_ question: String, contextSummary: String) async throws -> String {
        let instructionsText = """
        你是 Tempo 的健康教练。Tempo 是一款基于 Apple Watch 的压力监测和呼吸训练 App。
        你将基于用户最近 30 天的健康数据回答问题。

        要求:
        - 简洁友好,不超过 3 段
        - 给出具体数据支持(平均压力分、最高峰时间等)
        - 提供可执行的建议(呼吸训练、休息时长、活动调整)
        - 不做医疗诊断,如涉及健康风险建议就医
        - 用中文回答
        - 如果数据不足,直接说明并鼓励用户多用几天

        Tempo 提供 6 种呼吸训练:等长(5-5)、4-7-8、盒式(4-4-4-4)、共振(5.5 BPM)、Wim Hof、布泰科。
        合理时可推荐具体的训练。

        用户最近 30 天数据摘要:
        \(contextSummary)
        """

        let session = LanguageModelSession(instructions: instructionsText)
        let response = try await session.respond(to: question)
        return response.content
    }
    #endif

    func generateReportInsight(period: String, contextSummary: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let instructionsText = """
            你是 Tempo 的健康教练。基于以下 \(period) 数据,写一段 80-120 字的中文洞察文案。

            要求:
            - 简洁友好,2-3 句话
            - 具体引用数据(平均压力、最高峰时段、训练次数等)
            - 一句话总结整体状态,一句话给出下一步具体建议
            - 不重复"建议每天"这种空话,推荐到具体呼吸模式或休息时长
            - 不做医疗诊断

            \(period)数据:
            \(contextSummary)
            """
            do {
                let session = LanguageModelSession(instructions: instructionsText)
                let response = try await session.respond(to: "请根据上述数据,生成一段个性化的\(period)洞察。")
                return response.content
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    private func ruleBased(question: String, contextSummary: String) -> String {
        let q = question.lowercased()
        if q.contains("压力") || q.contains("stress") || q.contains("最高") || q.contains("最累") {
            return "你的最近压力概况:\n\n\(contextSummary)\n\n建议每天做 1-2 次 4-7-8 呼吸训练,睡前进行盒式呼吸放松。"
        }
        if q.contains("睡") || q.contains("sleep") {
            return "睡眠是恢复的核心。建议保证 7-9 小时睡眠,睡前 1 小时避免屏幕,室温 18-20°C 最佳。"
        }
        if q.contains("呼吸") || q.contains("breath") {
            return """
            推荐场景化呼吸:
            • 早晨:Box Breathing(4-4-4-4)激活专注力
            • 工作压力大:4-7-8 呼吸 5 个循环
            • 睡前:共振呼吸(5.5 BPM)10 分钟
            • 焦虑发作:Wim Hof 30 次激活
            """
        }
        if q.contains("恢复") || q.contains("recovery") || q.contains("强度") || q.contains("strain") {
            return "Tempo 主页的 Recovery / Strain 双圆环可以一眼看出今日状态。Recovery > 70% 适合冲刺,< 40% 建议休息。"
        }
        return "你最近的数据:\n\n\(contextSummary)\n\n你可以问\"我什么时候压力最高\"\"该做什么呼吸训练\"\"我的恢复怎么样\"。"
    }
}

enum AICoachContextBuilder {
    static func summary(from entries: [StressEntry]) -> String {
        guard !entries.isEmpty else {
            return "暂无历史数据。请在 Apple Watch 上启动 Tempo 监测几天后再来问。"
        }
        let scores = entries.map(\.scoreValue)
        let avg = scores.reduce(0, +) / scores.count
        let maxScore = scores.max() ?? 0
        let minScore = scores.min() ?? 0
        let dayCount = Set(entries.map { Calendar.current.startOfDay(for: $0.timestamp) }).count

        let formatter = DateFormatter()
        formatter.locale = TempoAppLanguage.currentLocale
        formatter.dateFormat = "MM-dd HH:mm"

        let highStress = entries.filter { $0.scoreValue >= 70 }.prefix(5)
        let highStressDescription: String
        if highStress.isEmpty {
            highStressDescription = "无"
        } else {
            highStressDescription = highStress
                .map { "\(formatter.string(from: $0.timestamp))(\($0.scoreValue))" }
                .joined(separator: ", ")
        }

        // Hourly average pattern
        let hourGroups = Dictionary(grouping: entries) {
            Calendar.current.component(.hour, from: $0.timestamp)
        }
        let busyHour = hourGroups
            .mapValues { items in items.map(\.scoreValue).reduce(0, +) / max(items.count, 1) }
            .max(by: { $0.value < $1.value })

        var summary = """
        - 总记录: \(entries.count) 条,跨 \(dayCount) 天
        - 平均压力分: \(avg)
        - 最高: \(maxScore),最低: \(minScore)
        - 最近高压时刻(≥70): \(highStressDescription)
        """

        if let busy = busyHour {
            summary += "\n- 一天中压力最高时段: \(busy.key) 点(平均 \(busy.value) 分)"
        }

        return summary
    }
}
