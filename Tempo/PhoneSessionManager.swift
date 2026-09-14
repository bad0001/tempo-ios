//
//  PhoneSessionManager.swift
//  Tempo
//
//  iPhone 侧接收 WatchConnectivity 心率数据并写入本地压力记录。
//

import Foundation
import Observation
import os
import SwiftData
import WatchConnectivity
import WidgetKit
import TempoCore

@Observable
final class HeartRateState {
    var bpm: Double = 0
    var lastUpdate: Date?
}

final class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()
    let state = HeartRateState()

    var modelContainer: ModelContainer?
    private var lastEntryTimestamp: Date?
    private var completedWatchCareReplyIDs: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "watch.completedCareReplyIDs") ?? []
    )
    private var watchCareReplyIDsInFlight: Set<String> = []

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func ingest(
        _ payload: [String: Any],
        replyHandler: (([String: Any]) -> Void)? = nil
    ) {
        if payload[WCMessageKeys.watchRequestSnapshot] as? Bool == true {
            Task { @MainActor in
                pushCachedSnapshotToWatch()
                replyHandler?([WCMessageKeys.watchCareReplySucceeded: true])
            }
        }

        if let message = payload[WCMessageKeys.watchCareReplyMessage] as? String,
           let friendUserID = payload[WCMessageKeys.watchCareFriendUserID] as? String,
           let eventID = payload[WCMessageKeys.watchCareEventID] as? String {
            Task { @MainActor in
                let result = await handleWatchCareReply(
                    eventID: eventID,
                    friendUserID: friendUserID,
                    message: message
                )
                replyHandler?(result)
            }
        }

        if let bpm = payload[WCMessageKeys.heartRate] as? Double {
            Task { @MainActor in
                state.bpm = bpm
                state.lastUpdate = Date()
                await saveStressEntry(bpm: bpm)
            }
        }
    }

    @MainActor
    private func handleWatchCareReply(
        eventID: String,
        friendUserID: String,
        message: String
    ) async -> [String: Any] {
        if completedWatchCareReplyIDs.contains(eventID) {
            pushCachedSnapshotToWatch()
            return [WCMessageKeys.watchCareReplySucceeded: true]
        }
        guard watchCareReplyIDsInFlight.insert(eventID).inserted else {
            return [
                WCMessageKeys.watchCareReplySucceeded: false,
                WCMessageKeys.watchCareReplyError: "这条回应正在发送",
            ]
        }
        defer { watchCareReplyIDsInFlight.remove(eventID) }

        do {
            try await FriendsService.shared.replyToCareEventFromWatch(
                eventID: eventID,
                friendUserID: friendUserID,
                message: message
            )
            completedWatchCareReplyIDs.insert(eventID)
            if completedWatchCareReplyIDs.count > 100 {
                completedWatchCareReplyIDs = Set(completedWatchCareReplyIDs.suffix(100))
            }
            UserDefaults.standard.set(
                Array(completedWatchCareReplyIDs),
                forKey: "watch.completedCareReplyIDs"
            )
            pushCachedSnapshotToWatch()
            return [WCMessageKeys.watchCareReplySucceeded: true]
        } catch {
            TempoLog.watch.error("Watch care reply failed: \(error.localizedDescription)")
            return [
                WCMessageKeys.watchCareReplySucceeded: false,
                WCMessageKeys.watchCareReplyError: error.localizedDescription,
            ]
        }
    }

    @MainActor
    private func saveStressEntry(bpm: Double) async {
        guard let container = modelContainer else { return }
        if let last = lastEntryTimestamp, Date().timeIntervalSince(last) < 30 {
            return
        }

        let hrv = try? await HealthKitService.shared.fetchLatestHRV()
        let evaluated = await HealthKitService.shared.evaluateCurrentStress(
            hr: bpm,
            hrv: hrv,
            container: container
        )
        let score = evaluated.score

        let context = container.mainContext
        let entry = StressEntry(
            bpm: bpm,
            hrv: hrv,
            scoreValue: score.value,
            levelRaw: score.level.rawValue,
            activityStateRaw: evaluated.activityState.rawValue,
            algorithmVersion: evaluated.algorithmVersion
        )
        context.insert(entry)
        try? context.save()
        lastEntryTimestamp = Date()

        let stressThreshold = UserDefaults.standard.object(forKey: "stress.notificationThreshold") == nil
            ? 80
            : UserDefaults.standard.integer(forKey: "stress.notificationThreshold")
        if score.value >= stressThreshold, UserDefaults.standard.bool(forKey: "smartRemindersEnabled") {
            await NotificationManager.shared.scheduleHighStressAlert(score: score)
        }

        // 共振关怀:只同步压力摘要到 Tempo 后端,绑定好友从后端读取。
        await FriendsService.shared.updateMyStress(score: score.value, level: score.level.rawValue)

        // 健康告警评估:仅当用户开启了对应 metric 的 alert 才会触发。
        let spo2 = try? await HealthKitService.shared.fetchLatestSpO2Percent()
        await HealthAlertMonitor.shared.evaluateAll(heartRate: bpm, spo2Percent: spo2)
    }

    func sendContinuousMonitoring(_ enabled: Bool) async {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = [WCMessageKeys.isMonitoring: enabled]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                TempoLog.watch.debug("WC sendMessage(monitoring) failed: \(error.localizedDescription)")
            }
        } else {
            do {
                try session.updateApplicationContext(payload)
            } catch {
                TempoLog.watch.debug("WC updateApplicationContext(monitoring) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Phone → Watch 推送派生指标快照(stress/recovery/strain/sleep/temp)。
    /// 同时:
    ///   - 写 App Group 文件 → Widget extension 能读到
    ///   - WC updateApplicationContext → Watch 能读到
    func pushSnapshotToWatch(_ snapshot: WatchSnapshot) {
        // 1) 写 App Group 文件供 Widget 读
        _ = SharedSnapshotStore.write(snapshot)
        // 主动让 WidgetCenter 刷新(没动也无所谓,有动就刷)
        WidgetCenter.shared.reloadAllTimelines()

        // 2) WC push 给 Watch
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let json = snapshot.encodeJSON() else { return }
        let payload: [String: Any] = [WCMessageKeys.watchSnapshotJSON: json]
        do {
            try session.updateApplicationContext(payload)
        } catch {
            TempoLog.watch.debug("pushSnapshotToWatch failed: \(error.localizedDescription)")
        }
    }

    /// 用最近一次健康快照合并当前未读关怀后推给 Watch。
    /// 可由 Watch 主动请求、APNs 刷新或手机启动触发，不依赖用户打开首页。
    @MainActor
    func pushCachedSnapshotToWatch() {
        let base = SharedSnapshotStore.read() ?? .empty
        let merged = base.replacingCareSignal(FriendsService.shared.latestUnreadWatchCareSignal)
        pushSnapshotToWatch(merged)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { ingest(message) }
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        ingest(message, replyHandler: replyHandler)
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { ingest(userInfo) }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in pushCachedSnapshotToWatch() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
