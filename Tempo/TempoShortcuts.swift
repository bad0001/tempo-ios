//
//  TempoShortcuts.swift
//  Tempo
//

import AppIntents
import SwiftData
import TempoCore

struct GetCurrentStressIntent: AppIntent {
    static var title: LocalizedStringResource = "查看当前压力"
    static var description: IntentDescription = IntentDescription(
        "返回你最新的 Tempo 压力分。"
    )

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = TempoSharedStore.makeModelContainer()
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<StressEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let latest = try? context.fetch(descriptor).first else {
            return .result(dialog: "暂无 Tempo 数据。请在 Apple Watch 上启动 Tempo 进行监测。")
        }

        let level = latest.level.tempoDisplayName
        let score = latest.scoreValue
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: latest.timestamp)

        return .result(
            dialog: "你最新的压力分是 \(score),状态\(level),记录于 \(time)。"
        )
    }
}

struct GetRecoveryIntent: AppIntent {
    static var title: LocalizedStringResource = "查看今日恢复"
    static var description: IntentDescription = IntentDescription(
        "返回你今日的 Tempo 恢复分。"
    )

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recovery = await HealthKitService.shared.computeRecovery()
        guard recovery.hasEnoughData else {
            return .result(dialog: "暂无足够数据计算恢复分。请保持戴 Apple Watch 入睡几晚后再询问。")
        }

        return .result(
            dialog: "你今日的恢复分是 \(recovery.value)%,状态\(recovery.level.tempoDisplayName)。"
        )
    }
}

struct StartBreathingIntent: AppIntent {
    static var title: LocalizedStringResource = "开始呼吸训练"
    static var description: IntentDescription = IntentDescription(
        "打开 Tempo 进入呼吸训练页面。"
    )

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct TempoShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetCurrentStressIntent(),
            phrases: [
                "查看 \(.applicationName) 压力",
                "我现在 \(.applicationName) 压力多少",
                "\(.applicationName) 当前压力"
            ],
            shortTitle: "查看压力",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: GetRecoveryIntent(),
            phrases: [
                "查看 \(.applicationName) 恢复",
                "\(.applicationName) 今日恢复多少",
                "我今天 \(.applicationName) 恢复怎么样"
            ],
            shortTitle: "查看恢复",
            systemImageName: "heart.text.square"
        )
        AppShortcut(
            intent: StartBreathingIntent(),
            phrases: [
                "用 \(.applicationName) 做呼吸训练",
                "打开 \(.applicationName) 呼吸",
                "\(.applicationName) 帮我放松"
            ],
            shortTitle: "开始呼吸",
            systemImageName: "wind"
        )
    }
}
