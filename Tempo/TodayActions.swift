//
//  TodayActions.swift
//  Tempo
//
//  「今日关键行动」 — 基于 mood + HK 数据规则生成 3-4 条具体建议.
//  不调用 LLM(deterministic 任务,规则更稳定 + 性能更好).
//

import Foundation
import SwiftUI
import SwiftData
import TempoCore

// MARK: - Service

@MainActor
@Observable
final class TodayActionsService {
    static let shared = TodayActionsService()

    var actions: [DailyAction] = []
    var lastGeneratedAt: Date?

    private init() {}

    func generate(
        stress: StressScore?,
        recovery: Recovery,
        strain: Strain,
        latestMood: MoodEntry?,
        moodLogged24h: Bool
    ) {
        var output: [DailyAction] = []

        let hour = Calendar.current.component(.hour, from: Date())

        // 1. 极高压力 → 优先呼吸训练
        if let stress, stress.value >= 75 {
            output.append(DailyAction(
                title: "做组 4-7-8 呼吸",
                reason: "压力分 \(stress.value),5 分钟可降到 50 以下",
                category: .breathing,
                primary: true
            ))
        }

        // 2. Recovery 低 → 减负
        if recovery.value > 0 && recovery.value < 50 {
            output.append(DailyAction(
                title: "今天放慢节奏",
                reason: "恢复评分 \(recovery.value),建议减少高强度活动",
                category: .movement
            ))
        }

        // 3. Strain 高 → 拉伸 / 走路
        if strain.value > 7 {
            output.append(DailyAction(
                title: "走路或拉伸 10 分钟",
                reason: "今日负荷 \(String(format: "%.1f", strain.value))/10",
                category: .movement
            ))
        }

        // 4. Mood tag 触发
        if let mood = latestMood {
            let tags = Set(mood.tags)

            if tags.contains("caffeine") && hour >= 14 {
                output.append(DailyAction(
                    title: "下午别再碰咖啡",
                    reason: "今天有咖啡因摄入,过晚饮用会影响夜间 HRV",
                    category: .nutrition
                ))
            }

            if tags.contains("insomnia") {
                output.append(DailyAction(
                    title: "睡前共振呼吸 10 分钟",
                    reason: "失眠需要降低交感神经活跃度,5.5 BPM 最有效",
                    category: .sleep
                ))
            }

            if (tags.contains("argument") || tags.contains("work") || tags.contains("news"))
                && !output.contains(where: { $0.category == .breathing }) {
                output.append(DailyAction(
                    title: "做组盒式呼吸",
                    reason: "外部刺激较多,盒式 4-4-4-4 帮助稳定",
                    category: .breathing
                ))
            }

            if mood.mood.score <= -1
                && !output.contains(where: { $0.category == .mindfulness }) {
                output.append(DailyAction(
                    title: "出门走 20 分钟",
                    reason: "心情有点低落,自然环境能改善 HRV",
                    category: .mindfulness
                ))
            }
        }

        // 5. 没记 mood → 提醒记
        if !moodLogged24h
            && !output.contains(where: { $0.category == .mindfulness }) {
                output.append(DailyAction(
                    title: "记录一下当下心情",
                    reason: "感受记录能让今天的建议更贴近你",
                    category: .mindfulness
                ))
        }

        // 6. 时间段相关
        if (hour >= 22 || hour < 6)
            && !output.contains(where: { $0.category == .sleep }) {
            output.append(DailyAction(
                title: "睡前共振呼吸 5 分钟",
                reason: "5.5 BPM 呼吸帮助快速入睡",
                category: .sleep
            ))
        } else if hour < 10
            && !output.contains(where: { $0.category == .breathing }) {
            output.append(DailyAction(
                title: "晨间盒式呼吸",
                reason: "4-4-4-4 节奏激活专注力",
                category: .breathing
            ))
        }

        // Fallback
        if output.isEmpty {
            output = [
                DailyAction(
                    title: "做组 5-5 等长呼吸",
                    reason: "保持心律韵律最简单的方式",
                    category: .breathing,
                    primary: true
                ),
                DailyAction(
                    title: "记录此刻感受",
                    reason: "帮 Tempo 更懂你的状态",
                    category: .mindfulness
                )
            ]
        }

        self.actions = Array(output.prefix(4))
        self.lastGeneratedAt = Date()
    }

    // MARK: - Action Type

    struct DailyAction: Identifiable, Hashable {
        let id = UUID()
        var title: String
        var reason: String
        var category: Category
        var primary: Bool = false

        enum Category: String, Hashable {
            case breathing
            case movement
            case nutrition
            case sleep
            case mindfulness

            var icon: String {
                switch self {
                case .breathing: "wind"
                case .movement: "figure.walk"
                case .nutrition: "cup.and.saucer.fill"
                case .sleep: "moon.fill"
                case .mindfulness: "leaf.fill"
                }
            }

            var color: Color {
                switch self {
                case .breathing: TempoTheme.accent
                case .movement: TempoTheme.success
                case .nutrition: Color(hex: "F97316")
                case .sleep: Color(hex: "8B5CF6")
                case .mindfulness: TempoTheme.success
                }
            }
        }
    }
}

// MARK: - Card View

struct TodayActionsCard: View {
    let actions: [TodayActionsService.DailyAction]
    @Environment(\.switchToTab) private var switchToTab

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今日关键行动")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Text("\(actions.count) 条")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(TempoTheme.accentSoft))
            }

            VStack(spacing: 10) {
                ForEach(actions) { action in
                    actionRow(action)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 22, padding: 18)
    }

    private func actionRow(_ action: TodayActionsService.DailyAction) -> some View {
        HStack(spacing: 12) {
            SoftIconBubble(systemName: action.category.icon, color: action.category.color, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(action.title))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if action.primary {
                        Text("优先")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(action.category.color))
                    }
                }
                Text(LocalizedStringKey(action.reason))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()

            // 呼吸类 → 跳到呼吸 tab
            if action.category == .breathing {
                Button {
                    NotificationCenter.default.post(name: .tempoOpenBreathing, object: nil, userInfo: [:])
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(action.category.color)
                }
                .buttonStyle(.tempoPress)
            }
        }
    }
}
