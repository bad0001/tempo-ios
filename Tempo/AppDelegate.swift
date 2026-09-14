//
//  AppDelegate.swift
//  Tempo
//
//  Push Notifications 注册 + APNs token 同步 + 远程通知路由.
//

import Foundation
import os
import CloudKit
import UIKit
import UserNotifications
import TempoCore

private enum TempoServerPush {
    nonisolated static func handles(_ type: String) -> Bool {
        switch type {
        case "friend_removed",
             "care_event",
             "invite_received",
             "invite_accepted",
             "friend_request_received",
             "friend_request_accepted",
             "bottle_reply":
            true
        default:
            false
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// APNs 注册重试次数(指数退避)
    private var apnsRetryCount = 0
    private let apnsMaxRetries = 5

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 注册接收远程通知
        UNUserNotificationCenter.current().delegate = NotificationsHandler.shared
        application.registerForRemoteNotifications()
        return true
    }

    // MARK: - APNs token

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        TempoLog.push.debug("APNs token registered: \(tokenString.prefix(16))...")
        apnsRetryCount = 0
        UserDefaults.standard.set(false, forKey: "push.registrationFailed")
        Task { @MainActor in
            APNsTokenStore.shared.store(deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        TempoLog.push.error("APNs register failed (attempt \(self.apnsRetryCount + 1)): \(error.localizedDescription)")
        apnsRetryCount += 1
        if apnsRetryCount < apnsMaxRetries {
            // 指数退避:2s, 4s, 8s, 16s, 32s
            let delay = pow(2.0, Double(apnsRetryCount))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                TempoLog.push.debug("APNs retry attempt \(self.apnsRetryCount)/\(self.apnsMaxRetries) after \(delay)s")
                application.registerForRemoteNotifications()
            }
        } else {
            // 5 次后放弃,标记给 UI 提示用户去设置里检查通知权限
            UserDefaults.standard.set(true, forKey: "push.registrationFailed")
            TempoLog.push.error("APNs gave up after \(self.apnsMaxRetries) attempts; user should check Settings → Tempo → Notifications")
        }
    }

    // MARK: - Silent push (CloudKit subscription notifications)

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let serverType = userInfo["type"] as? String,
           TempoServerPush.handles(serverType) {
            Task { @MainActor in
                await NotificationsHandler.shared.handleServerPush(userInfo)
                completionHandler(.newData)
            }
            return
        }

        guard let dict = userInfo as? [String: NSObject],
              let _ = CKNotification(fromRemoteNotificationDictionary: dict) else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            await FriendsService.shared.refreshFriends()
            await FriendsService.shared.loadEncourages()
            await FriendsService.shared.loadFriendAlerts()
            await FriendsService.shared.loadResonantEvents()
            PhoneSessionManager.shared.pushCachedSnapshotToWatch()
            // 检查是否有朋友新进高压 → 触发本地提醒
            await NotificationsHandler.shared.notifyHighStressFriendsIfNeeded()
            // 检查是否有未读鼓励 → 触发本地提醒
            await NotificationsHandler.shared.notifyUnreadEncouragesIfNeeded()
            // 检查是否有新 health alert → 触发本地提醒
            await NotificationsHandler.shared.notifyFriendHealthAlertsIfNeeded()
            // 检查是否有新共振事件(心跳 / 邀请呼吸冥想 / 完成回执)→ 触发本地提醒
            await NotificationsHandler.shared.notifyResonantEventsIfNeeded()
            completionHandler(.newData)
        }
    }
}

// MARK: - Notifications Handler

@MainActor
final class NotificationsHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsHandler()

    /// 已经为某朋友某次高压通知过的 timestamp,避免反复推送
    private var lastNotifiedAt: [String: Date] = [:]
    private let cooldown: TimeInterval = 1800  // 30 分钟

    /// 检查所有朋友 stress,如果新进 ≥ 阈值且距上次通知 ≥ cooldown,触发本地通知
    func notifyHighStressFriendsIfNeeded() async {
        let threshold = UserDefaults.standard.double(forKey: "user.musicTriggerThreshold")
        let triggerScore = threshold > 0 ? Int(threshold) : 70

        for friend in FriendsService.shared.friends where friend.stressScore >= triggerScore {
            if FriendsService.shared.isMuted(friend) {
                continue
            }
            if let last = lastNotifiedAt[friend.id], Date().timeIntervalSince(last) < cooldown {
                continue
            }
            await scheduleHighStressFriendNotification(friend: friend)
            lastNotifiedAt[friend.id] = Date()
        }
    }

    /// 已经为某条 encourage 通知过的 record id,避免重复
    private var notifiedEncourageIDs: Set<String> = []

    /// 检查是否有新 encourage(sentAt > lastEncourageReadAt)且没通知过 → 触发本地通知
    func notifyUnreadEncouragesIfNeeded() async {
        let lastRead = FriendsService.shared.lastEncourageReadAt
        for e in FriendsService.shared.encourages where e.isUnread(comparedWith: lastRead) {
            if notifiedEncourageIDs.contains(e.id) { continue }
            if FriendsService.shared.isMuted(serverUserId: e.fromUserId, displayName: e.fromName, zoneID: e.zoneID) {
                notifiedEncourageIDs.insert(e.id)
                continue
            }
            await scheduleEncourageNotification(encourage: e)
            notifiedEncourageIDs.insert(e.id)
        }
    }

    /// 已经为某条 health alert 通知过的 record id,避免重复
    private var notifiedAlertIDs: Set<String> = []

    /// 已经为某条 resonant event 通知过的 record id,避免重复
    private var notifiedResonantEventIDs: Set<String> = []
    private var presentedServerCareEventIDs: Set<String> = []

    func notifyResonantEventsIfNeeded() async {
        let lastRead = FriendsService.shared.lastResonantEventReadAt
        for event in FriendsService.shared.resonantEvents where event.isUnread(comparedWith: lastRead) {
            if notifiedResonantEventIDs.contains(event.id) { continue }
            if FriendsService.shared.isMuted(serverUserId: event.fromUserId, displayName: event.fromName, zoneID: event.zoneID) {
                notifiedResonantEventIDs.insert(event.id)
                continue
            }
            await scheduleResonantEventNotification(event: event)
            notifiedResonantEventIDs.insert(event.id)
        }
    }

    private func scheduleResonantEventNotification(event: ResonantEvent) async {
        if FriendsService.shared.isMuted(serverUserId: event.fromUserId, displayName: event.fromName, zoneID: event.zoneID) {
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = ResonantEventMessage.notificationTitle(type: event.type, fromName: event.fromName)
        content.body = ResonantEventMessage.notificationBody(type: event.type, payload: event.payload)
        content.sound = .default
        content.userInfo = [
            "kind": "resonant_event",
            "eventID": event.id,
            "eventType": event.type.rawValue,
            "fromName": event.fromName,
            "fromUserId": event.fromUserId ?? "",
            "minutes": event.payload["minutes"] ?? "5"
        ]
        switch event.type {
        case .breathingInvite, .meditationInvite:
            content.categoryIdentifier = "TEMPO_TRAINING_INVITE"
        case .heartbeat:
            content.categoryIdentifier = "TEMPO_HEARTBEAT"
        case .sessionCompleted:
            content.categoryIdentifier = "TEMPO_SESSION_COMPLETED"
        }
        let req = UNNotificationRequest(
            identifier: "resonant.\(event.id)",
            content: content,
            trigger: nil
        )
        try? await center.add(req)
    }

    func notifyFriendHealthAlertsIfNeeded() async {
        for alert in FriendsService.shared.friendAlerts {
            if notifiedAlertIDs.contains(alert.id) { continue }
            // 跳过已静音好友
            if let friend = FriendsService.shared.friends.first(where: { $0.zoneID == alert.zoneID }),
               FriendsService.shared.isMuted(friend) {
                continue
            }
            await scheduleHealthAlertNotification(alert: alert)
            notifiedAlertIDs.insert(alert.id)
        }
    }

    private func scheduleHealthAlertNotification(alert: FriendAlert) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = HealthAlertMessage.friendNotificationTitle(friendName: alert.fromName, metric: alert.metric)
        content.body = HealthAlertMessage.friendNotificationBody(metric: alert.metric, severity: alert.severity)
        content.sound = .default
        content.categoryIdentifier = "FRIEND_HEALTH_ALERT"
        content.userInfo = ["alertID": alert.id, "zoneOwner": alert.zoneID.ownerName]
        let req = UNNotificationRequest(
            identifier: "alert.\(alert.id)",
            content: content,
            trigger: nil
        )
        try? await center.add(req)
    }

    private func scheduleEncourageNotification(encourage: Encourage) async {
        if FriendsService.shared.isMuted(serverUserId: encourage.fromUserId, displayName: encourage.fromName, zoneID: encourage.zoneID) {
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "\(encourage.fromName) 给你发了鼓励"
        content.body = encourage.message
        content.sound = .default
        content.categoryIdentifier = "FRIEND_ENCOURAGE_RECEIVED"
        content.userInfo = [
            "encourageID": encourage.id,
            "fromUserId": encourage.fromUserId ?? "",
            "fromName": encourage.fromName,
        ]
        let req = UNNotificationRequest(
            identifier: "encourage.\(encourage.id)",
            content: content,
            trigger: nil
        )
        try? await center.add(req)
    }

    private func scheduleHighStressFriendNotification(friend: Friend) async {
        if FriendsService.shared.isMuted(friend) {
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(friend.displayName) 压力上行"
        content.body = "Ta 现在有些紧绷,要不要发个鼓励?"
        content.sound = .default
        content.categoryIdentifier = "FRIEND_HIGH_STRESS"
        content.userInfo = ["friendID": friend.id]

        let req = UNNotificationRequest(
            identifier: "friend.\(friend.id).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        try? await center.add(req)
    }

    /// App 启动时调用,注册一次 NotificationCategory + Action
    func registerCategories() {
        let encourageAction = UNNotificationAction(
            identifier: "ENCOURAGE_QUICK",
            title: "发送鼓励",
            options: [.foreground]
        )
        let highStress = UNNotificationCategory(
            identifier: "FRIEND_HIGH_STRESS",
            actions: [encourageAction],
            intentIdentifiers: [],
            options: []
        )

        // 训练邀请(呼吸 / 冥想):带「现在做」action
        let acceptTrainingAction = UNNotificationAction(
            identifier: "ACCEPT_TRAINING",
            title: "现在做",
            options: [.foreground]
        )
        let trainingInvite = UNNotificationCategory(
            identifier: "TEMPO_TRAINING_INVITE",
            actions: [acceptTrainingAction],
            intentIdentifiers: [],
            options: []
        )

        // 心跳:简单 banner,无 action
        let heartbeat = UNNotificationCategory(
            identifier: "TEMPO_HEARTBEAT",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // 完成回执:简单 banner
        let sessionCompleted = UNNotificationCategory(
            identifier: "TEMPO_SESSION_COMPLETED",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            highStress, trainingInvite, heartbeat, sessionCompleted,
        ])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let serverType = userInfo["type"] as? String,
           TempoServerPush.handles(serverType) {
            Task { @MainActor in
                await NotificationsHandler.shared.handleServerPush(userInfo)
                if serverType == "care_event",
                   NotificationsHandler.shared.isMutedCareEventSender(userInfo) {
                    completionHandler([])
                    return
                }
                completionHandler([.banner, .sound])
            }
            return
        }
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        Task { @MainActor in
            // 高压预警通知 → "ENCOURAGE_QUICK" action 直接发预设鼓励;点击通知 banner → 跳关怀面板
            if let friendID = userInfo["friendID"] as? String {
                if actionId == "ENCOURAGE_QUICK",
                   let friend = FriendsService.shared.friends.first(where: { $0.id == friendID }) {
                    if let preset = EncouragePresets.all.first {
                        try? await FriendsService.shared.sendEncourage(to: friend, message: preset)
                    }
                } else if actionId == UNNotificationDefaultActionIdentifier {
                    NotificationCenter.default.post(
                        name: .tempoOpenCarePanel,
                        object: nil,
                        userInfo: ["friendID": friendID]
                    )
                }
            }
            // 训练邀请通知:点击 / 选「现在做」→ 弹 invite responder sheet
            if userInfo["kind"] as? String == "resonant_event",
               let eventTypeRaw = userInfo["eventType"] as? String,
               let eventType = ResonantEventType(rawValue: eventTypeRaw),
               (actionId == "ACCEPT_TRAINING" || actionId == UNNotificationDefaultActionIdentifier) {
                let fromName = userInfo["fromName"] as? String ?? "好友"
                let minutes = Int(userInfo["minutes"] as? String ?? "5") ?? 5
                let eventID = userInfo["eventID"] as? String ?? ""
                if eventType == .breathingInvite || eventType == .meditationInvite {
                    NotificationCenter.default.post(
                        name: .tempoTrainingInvite,
                        object: nil,
                        userInfo: [
                            "type": eventType.rawValue,
                            "minutes": minutes,
                            "fromName": fromName,
                            "eventID": eventID,
                        ]
                    )
                } else if eventType == .heartbeat || eventType == .sessionCompleted {
                    // 心跳 / 完成回执 → 跳关怀面板,通过 fromName 反查
                    NotificationCenter.default.post(
                        name: .tempoOpenCarePanel,
                        object: nil,
                        userInfo: [
                            "fromName": fromName,
                            "markCareRead": true,
                            "eventID": eventID,
                        ]
                    )
                }
            }
            // 鼓励通知点击 → 跳关怀面板(没有 friendID,只有 encourageID)
            if let encourageID = userInfo["encourageID"] as? String,
               actionId == UNNotificationDefaultActionIdentifier {
                NotificationCenter.default.post(
                    name: .tempoOpenCarePanel,
                    object: nil,
                    userInfo: ["markCareRead": true, "eventID": encourageID]
                )
            }
            // server 推送的邀请通知(type=invite_received / invite_accepted / friend_request_received / friend_request_accepted)
            // → 跳共振设置页让用户在 inbox 看到 + 接受
            if let serverType = userInfo["type"] as? String,
               actionId == UNNotificationDefaultActionIdentifier {
                switch serverType {
                case "invite_received", "friend_request_received":
                    await self.handleServerPush(userInfo)
                    NotificationCenter.default.post(name: .tempoOpenResonantSettings, object: nil, userInfo: [:])
                case "invite_accepted", "friend_request_accepted":
                    // 邀请被接受 → 跳共振设置看朋友列表
                    await self.handleServerPush(userInfo)
                    NotificationCenter.default.post(name: .tempoOpenResonantSettings, object: nil, userInfo: [:])
                case "friend_removed":
                    await self.handleServerPush(userInfo)
                    NotificationCenter.default.post(name: .tempoOpenResonantSettings, object: nil, userInfo: [:])
                case "care_event":
                    await self.handleServerPush(userInfo)
                    let eventTypeRaw = userInfo["eventType"] as? String ?? ""
                    let fromName = userInfo["fromName"] as? String ?? "好友"
                    let eventID = userInfo["eventId"] as? String ?? ""
                    let payload = self.serverPayload(from: userInfo)
                    let minutes = Int(payload["minutes"] ?? "5") ?? 5
                    if eventTypeRaw == ResonantEventType.breathingInvite.rawValue || eventTypeRaw == ResonantEventType.meditationInvite.rawValue {
                        NotificationCenter.default.post(
                            name: .tempoTrainingInvite,
                            object: nil,
                            userInfo: [
                                "type": eventTypeRaw,
                                "minutes": minutes,
                                "fromName": fromName,
                                "eventID": eventID,
                            ]
                        )
                    } else {
                        await FriendsService.shared.markCareEventsRead(eventIDs: [eventID])
                        NotificationCenter.default.post(
                            name: .tempoOpenCarePanel,
                            object: nil,
                            userInfo: [
                                "fromName": fromName,
                                "markCareRead": true,
                                "eventID": eventID,
                            ]
                        )
                    }
                case "bottle_reply":
                    let bottleID = userInfo["bottleId"] as? String
                    let replyID = userInfo["replyId"] as? String
                    BottleDeepLinkStore.save(bottleID: bottleID, replyID: replyID)
                    NotificationCenter.default.post(
                        name: .tempoOpenBottleSea,
                        object: nil,
                        userInfo: [
                            "bottleId": bottleID ?? "",
                            "replyId": replyID ?? "",
                        ]
                    )
                default:
                    break
                }
            }
            completionHandler()
        }
    }

    func handleServerPush(_ userInfo: [AnyHashable: Any]) async {
        switch userInfo["type"] as? String {
        case "invite_received", "friend_request_received":
            FriendsService.shared.pendingFriendRequestCount = max(
                1,
                FriendsService.shared.pendingFriendRequestCount
            )
            await FriendsService.shared.refreshPendingFriendRequests()
            NotificationCenter.default.post(name: .tempoFriendRequestsChanged, object: nil)
        case "invite_accepted", "friend_request_accepted":
            FriendsService.shared.restoreRemovedFriend(
                serverUserId: userInfo["friendUserId"] as? String,
                publicId: userInfo["friendPublicId"] as? String
            )
            await FriendsService.shared.publishLatestStressSnapshotIfPossible()
            await FriendsService.shared.refreshFriends()
            await FriendsService.shared.refreshPendingFriendRequests()
            NotificationCenter.default.post(name: .tempoFriendRequestsChanged, object: nil)
        case "friend_removed":
            let removedAtMilliseconds: TimeInterval? = {
                if let value = userInfo["removedAt"] as? NSNumber {
                    return value.doubleValue
                }
                if let value = userInfo["removedAt"] as? String {
                    return TimeInterval(value)
                }
                return nil
            }()
            await FriendsService.shared.handleRemoteFriendRemoval(
                serverUserId: userInfo["fromUserId"] as? String,
                publicId: userInfo["fromPublicId"] as? String,
                displayName: userInfo["fromName"] as? String,
                removedAt: removedAtMilliseconds.map { $0 / 1000 }
            )
        case "care_event":
            await FriendsService.shared.loadEncourages()
            await FriendsService.shared.loadResonantEvents()
            PhoneSessionManager.shared.pushCachedSnapshotToWatch()
            presentCareEventInAppIfNeeded(userInfo)
        case "bottle_reply":
            return
        default:
            return
        }
    }

    private func presentCareEventInAppIfNeeded(_ userInfo: [AnyHashable: Any]) {
        guard UIApplication.shared.applicationState == .active else { return }
        guard !isMutedCareEventSender(userInfo) else { return }
        let eventID = (userInfo["eventId"] as? String) ?? (userInfo["eventID"] as? String) ?? UUID().uuidString
        guard !presentedServerCareEventIDs.contains(eventID) else { return }
        presentedServerCareEventIDs.insert(eventID)

        let eventTypeRaw = userInfo["eventType"] as? String ?? ""
        let fromName = userInfo["fromName"] as? String ?? "密友"
        let payload = serverPayload(from: userInfo)
        let message = userInfo["message"] as? String
        let icon: String
        let body: String
        if eventTypeRaw == "encourage" {
            icon = "envelope.fill"
            body = message.flatMap { $0.isEmpty ? nil : $0 } ?? "给你发了鼓励"
        } else if eventTypeRaw == "trend_summary" {
            icon = "chart.xyaxis.line"
            body = "分享了 \(payload["range"] ?? "近期")压力摘要 · 平均 \(payload["average"] ?? "—")"
        } else if let type = ResonantEventType(rawValue: eventTypeRaw) {
            icon = type.icon
            body = ResonantEventMessage.notificationBody(type: type, payload: payload)
        } else {
            icon = "heart.circle.fill"
            body = "发来一条关怀"
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(
            name: .tempoCareEventReceived,
            object: nil,
            userInfo: [
                "eventID": eventID,
                "fromName": fromName,
                "body": body,
                "icon": icon
            ]
        )
    }

    private func isMutedCareEventSender(_ userInfo: [AnyHashable: Any]) -> Bool {
        FriendsService.shared.isMuted(
            serverUserId: userInfo["fromUserId"] as? String,
            publicId: userInfo["fromPublicId"] as? String,
            displayName: userInfo["fromName"] as? String
        )
    }

    private func serverPayload(from userInfo: [AnyHashable: Any]) -> [String: String] {
        guard let raw = userInfo["payloadJSON"] as? String,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return decoded
    }

}

// MARK: - Internal NotificationCenter names

extension Notification.Name {
    static let tempoTrainingInvite = Notification.Name("tempo.trainingInvite")
    static let tempoOpenCarePanel = Notification.Name("tempo.openCarePanel")
    static let tempoOpenResonantSettings = Notification.Name("tempo.openResonantSettings")
    static let tempoOpenBreathing = Notification.Name("tempo.openBreathing")
    static let tempoOpenBottleSea = Notification.Name("tempo.openBottleSea")
    static let tempoCareEventReceived = Notification.Name("tempo.careEventReceived")
    static let tempoFriendRequestsChanged = Notification.Name("tempo.friendRequestsChanged")
}
