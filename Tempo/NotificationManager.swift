//
//  NotificationManager.swift
//  Tempo
//

import Foundation
import UserNotifications
import TempoCore

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let cooldown: TimeInterval = 1800
    private let cooldownKey = "lastHighStressNotificationAt"

    private var lastHighStressNotificationAt: Date? {
        get { UserDefaults.standard.object(forKey: cooldownKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: cooldownKey) }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func scheduleHighStressAlert(score: StressScore) async {
        if let last = lastHighStressNotificationAt,
           Date().timeIntervalSince(last) < cooldown {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "压力警报"
        content.body = "你的压力分已达 \(score.value),建议立刻休息或试试 4-7-8 呼吸训练。"
        content.sound = .default
        content.categoryIdentifier = "stress.high"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "stress.high.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
        lastHighStressNotificationAt = Date()
    }

    func scheduleCareFollowUp(friendName: String, minutes: Int) async throws {
        _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])

        let content = UNMutableNotificationContent()
        content.title = "回看一下 \(friendName)"
        content.body = "刚才 Ta 可能有点累,现在适合补一句话。"
        content.sound = .default
        content.userInfo = [
            "type": "care_follow_up",
            "friendName": friendName,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, TimeInterval(minutes * 60)),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "care.followup.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func cancelHighStressAlerts() {
        Task {
            let pending = await center.pendingNotificationRequests()
            let pendingIDs = pending
                .map(\.identifier)
                .filter { $0.hasPrefix("stress.high.") }
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)

            let delivered = await center.deliveredNotifications()
            let deliveredIDs = delivered
                .map(\.request.identifier)
                .filter { $0.hasPrefix("stress.high.") }
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }
}
