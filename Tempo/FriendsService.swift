//
//  FriendsService.swift
//  Tempo
//
//  共振关怀 — server public_id 朋友绑定 + 后端压力摘要 + APNs 关怀事件.
//
//  数据模型:
//   - server 保存 public_id、friend_requests、friendships、care_events、stress_snapshots
//   - HealthKit 原始心率/睡眠等只在本机;压力摘要可分享,HRV 样本必须由用户单独开启后上传
//   - CloudKit 旧路径保留作历史数据兜底,不再作为登录用户的核心关怀通道
//
//  推送:
//   - 关怀事件/解绑/好友请求由 Tempo server 路由 APNs
//   - 接收端刷新 server inbox + friend stress snapshots
//

import Foundation
import os
import CloudKit
import SwiftUI
import TempoCore
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class FriendsService {
    static let shared = FriendsService()

    static let containerID = "iCloud.com.ayipocket.tempo"
    static let zoneName = "TempoFriends"
    static let myStressRecordType = "MyStress"
    static let myStressRecordName = "myStress"
    static let encourageRecordType = "Encourage"
    static let alertRecordType = "HealthAlert"
    static let resonantEventRecordType = "ResonantEvent"
    static let sharedSubscriptionID = "tempo.shared.changes"
    static let privateSubscriptionID = "tempo.private.changes"
    static let tempoUserIdField = "tempoUserId"
    static let tempoPublicIdField = "tempoPublicId"

    @ObservationIgnored
    let container: CKContainer

    enum ICloudStatus: Equatable {
        case checking
        case unavailable(String)
        case ready
    }

    var iCloudStatus: ICloudStatus = .checking
    var friends: [Friend] = []
    var encourages: [Encourage] = []
    var friendAlerts: [FriendAlert] = []
    var resonantEvents: [ResonantEvent] = []
    var careTimeline: [CareInteraction] = []
    var isCareTimelineRefreshing = false
    var pendingFriendRequestCount: Int = 0
    var lastError: String?
    var friendSyncState: TempoLoadState = .idle

    @ObservationIgnored
    private var lastSuccessfulFriendSyncAt: Date?

    @ObservationIgnored
    private var isFriendRefreshInFlight = false

    private struct FriendSnapshotCacheEnvelope: Codable {
        let snapshots: [ServerFriendStress]
        let updatedAt: Date
    }

    private static let friendSnapshotCachePrefix = "friends.serverSnapshots."

    @ObservationIgnored
    private var careTimelineFriendUserId: String?

    /// 用户主动解除后先在本机隐藏,避免 CloudKit leave share 偶发失败时 UI 又把 Ta 刷回来.
    var locallyRemovedFriendIDs: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "friends.locallyRemoved.ids") ?? [])
    }()

    var locallyRemovedServerUserIDs: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "friends.locallyRemoved.serverUserIds") ?? [])
    }()

    var locallyRemovedPublicIDs: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "friends.locallyRemoved.publicIds") ?? [])
    }()

    @ObservationIgnored
    private var locallyRemovedAtByServerUserID: [String: TimeInterval] = {
        (UserDefaults.standard.dictionary(forKey: "friends.locallyRemoved.atByServerUserId") as? [String: Double]) ?? [:]
    }()

    /// 用户点击解除后到 server 确认前的短暂过渡集。
    /// 只在请求进行中阻止好友被刷回;请求结束后 server friendship 是唯一真值。
    @ObservationIgnored
    private var pendingServerRemovalIDs: Set<String> = []

    /// 我自己当前 active 的 alert record ID(用来 dedupe / clear)
    @ObservationIgnored
    private var myActiveAlertRecordIDs: [HealthAlertMetric: CKRecord.ID] = [:]

    /// 已静音的好友 ID 集(只屏蔽提醒,不隐藏 stress / 不删除绑定)
    var mutedFriendIDs: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "friends.muted") ?? [])
    }()

    /// 全局开关:是否把我的 stress 同步给所有好友(默认 on)
    var sharingMyStress: Bool = {
        if UserDefaults.standard.object(forKey: "friends.sharingMyStress") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "friends.sharingMyStress")
    }()

    /// 是否分享呼吸/冥想训练 session 给好友(默认 off,用户主动开)
    var shareTrainingWithFriends: Bool = {
        UserDefaults.standard.bool(forKey: "friends.shareTraining")
    }()

    /// 是否上传 HRV 到 server。健康数据出设备必须单独 opt-in,默认 off。
    var shareHRVWithServer: Bool = {
        if UserDefaults.standard.object(forKey: "friends.shareHRV") == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: "friends.shareHRV")
    }()

    /// 上次"全部标已读"的时间,持久化到 UserDefaults
    var lastEncourageReadAt: Date = {
        let ts = UserDefaults.standard.double(forKey: "friends.encourages.lastReadAt")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }()

    var unreadEncouragesCount: Int {
        encourages.filter { $0.isUnread(comparedWith: lastEncourageReadAt) }.count
    }

    /// 共振事件的"上次已读"时间
    var lastResonantEventReadAt: Date = {
        let ts = UserDefaults.standard.double(forKey: "friends.resonantEvents.lastReadAt")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }()

    var unreadResonantEventsCount: Int {
        resonantEvents.filter { $0.isUnread(comparedWith: lastResonantEventReadAt) }.count
    }

    /// 手表只展示一条最新、未读、未静音的关怀。
    /// 路由字段全部来自现有 server 事件，Watch 不直接持有登录凭证。
    var latestUnreadWatchCareSignal: WatchCareSignal? {
        var signals: [WatchCareSignal] = []

        for encourage in encourages where encourage.isUnread(comparedWith: lastEncourageReadAt) {
            guard let eventID = encourage.serverEventId,
                  let friendUserID = serverUserID(
                    explicit: encourage.fromUserId,
                    displayName: encourage.fromName,
                    zoneID: encourage.zoneID
                  ) else { continue }
            guard !isMuted(
                serverUserId: friendUserID,
                displayName: encourage.fromName,
                zoneID: encourage.zoneID
            ) else { continue }
            signals.append(WatchCareSignal(
                eventID: eventID,
                friendUserID: friendUserID,
                senderName: encourage.fromName,
                message: String(encourage.message.prefix(120)),
                kind: "encourage",
                sentAt: encourage.sentAt
            ))
        }

        for event in resonantEvents where event.isUnread(comparedWith: lastResonantEventReadAt) {
            guard let eventID = event.serverEventId,
                  let friendUserID = serverUserID(
                    explicit: event.fromUserId,
                    displayName: event.fromName,
                    zoneID: event.zoneID
                  ) else { continue }
            guard !isMuted(
                serverUserId: friendUserID,
                displayName: event.fromName,
                zoneID: event.zoneID
            ) else { continue }
            signals.append(WatchCareSignal(
                eventID: eventID,
                friendUserID: friendUserID,
                senderName: event.fromName,
                message: ResonantEventMessage.notificationBody(type: event.type, payload: event.payload),
                kind: event.type.rawValue,
                sentAt: event.sentAt
            ))
        }

        return signals.max { $0.sentAt < $1.sentAt }
    }

    private func serverUserID(
        explicit: String?,
        displayName: String,
        zoneID: CKRecordZone.ID
    ) -> String? {
        explicit ?? friends.first {
            $0.zoneID == zoneID || $0.displayName == displayName
        }?.serverUserId
    }

    private init() {
        self.container = CKContainer(identifier: Self.containerID)
        // 架构已切到 Tempo Server 主通道,不再硬卡 iCloud 账户状态.
        // iCloudStatus 默认 .ready,所有共振关怀流程走 server.
        // CloudKit 留在代码里仅作过渡 / 旧 share URL 接受兼容(将在下个大版本完全移除).
        self.iCloudStatus = .ready
        Task { await checkStatus() }
    }

    // MARK: - Status

    /// Server-first 架构:不再硬卡 iCloud 账户.
    /// 只做 server 端 refresh + 后台异步检测 iCloud(不阻塞 UI).
    func checkStatus() async {
        iCloudStatus = .ready
        await refreshFriends()
        await loadFriendAlerts()
        // 后台异步看一眼 iCloud account(用于 log / debug,不影响 UI 流程)
        if let status = try? await container.accountStatus() {
            TempoLog.friends.debug("iCloud accountStatus (informational): \(status.rawValue)")
        }
    }

    // MARK: - My display name

    func myDisplayName() -> String {
        if let serverName = TempoSession.shared.displayName, !serverName.isEmpty {
            return serverName
        }
        if let custom = UserDefaults.standard.string(forKey: "user.displayName"), !custom.isEmpty {
            return custom
        }
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Tempo 用户"
        #endif
    }

    // MARK: - Update my stress

    private enum StressSnapshotCache {
        static let score = "friends.latestStress.score"
        static let level = "friends.latestStress.level"
        static let updatedAt = "friends.latestStress.updatedAt"
    }

    private func cacheLatestStress(score: Int, level: String) {
        UserDefaults.standard.set(score, forKey: StressSnapshotCache.score)
        UserDefaults.standard.set(level, forKey: StressSnapshotCache.level)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: StressSnapshotCache.updatedAt)
    }

    private func cachedLatestStress(maxAge: TimeInterval = 7 * 86_400) -> (score: Int, level: String)? {
        guard UserDefaults.standard.object(forKey: StressSnapshotCache.score) != nil,
              let level = UserDefaults.standard.string(forKey: StressSnapshotCache.level),
              !level.isEmpty else {
            return nil
        }
        let updatedAt = UserDefaults.standard.double(forKey: StressSnapshotCache.updatedAt)
        guard updatedAt > 0, Date().timeIntervalSince1970 - updatedAt <= maxAge else {
            return nil
        }
        return (UserDefaults.standard.integer(forKey: StressSnapshotCache.score), level)
    }

    /// 写最新 stress 摘要 + append 历史。共振关怀走 Tempo server.
    func updateMyStress(score: Int, level: String) async {
        cacheLatestStress(score: score, level: level)
        guard sharingMyStress else { return }
        if AlertSettings.shared.isPaused { return }

        guard TempoSession.shared.isLoggedIn else { return }
        // 1. snapshot(每用户一行,显示给好友)
        do {
            try await TempoAPIClient.shared.updateStressSnapshot(
                score: score,
                level: level,
                displayName: myDisplayName()
            )
        } catch {
            TempoLog.friends.debug("server stress snapshot failed: \(error)")
        }
        // 2. history(append-only,做趋势曲线 + AI 分析)
        do {
            try await TempoAPIClient.shared.appendStressHistory(score: score, level: level)
        } catch {
            TempoLog.friends.debug("server stress history append failed: \(error)")
        }
    }

    /// Phase 2:上传过去 N 天 HRV samples 到 server(用于 server 端 daily_summary 聚合 + AI 分析).
    /// 调用时机:TempoApp launch + 每隔 1h(后台 task).不每次 stress 触发,避免请求洪水.
    /// 用户的 sharingMyStress=off 时不上传(尊重设置).
    func uploadRecentHRVIfPossible(daysBack: Int = 1) async {
        guard TempoSession.shared.isLoggedIn else { return }
        guard sharingMyStress else { return }
        guard shareHRVWithServer else { return }
        do {
            let samples = try await HealthKitService.shared.fetchRecentHRVSamples(daysBack: daysBack, maxCount: 500)
            guard !samples.isEmpty else { return }
            let uploads = samples.map { s in
                HRVSampleUpload(
                    valueMs: s.valueMs,
                    measuredAt: Int64(s.date.timeIntervalSince1970 * 1000),
                    source: "ios"
                )
            }
            let accepted = try await TempoAPIClient.shared.uploadHRVSamples(uploads)
            TempoLog.friends.debug("uploaded \(accepted) HRV samples to server")
        } catch {
            TempoLog.friends.debug("HRV upload failed: \(error)")
        }
    }

    /// 绑定关系刚建立/收到对方接受时主动发布一次最新摘要,避免好友端一直显示未知。
    /// 只上传 stress score + level + displayName,不上传 HealthKit 原始数据.
    func publishLatestStressSnapshotIfPossible() async {
        guard sharingMyStress else { return }
        if AlertSettings.shared.isPaused { return }
        guard TempoSession.shared.isLoggedIn else { return }

        let heartRate = (try? await HealthKitService.shared.fetchLatestHeartRate()) ?? 0
        let hrv = try? await HealthKitService.shared.fetchLatestHRV()

        guard heartRate > 0 || hrv != nil else {
            if let cached = cachedLatestStress() {
                await updateMyStress(score: cached.score, level: cached.level)
            }
            return
        }

        let evaluated = await HealthKitService.shared.evaluateCurrentStress(
            hr: heartRate,
            hrv: hrv
        )
        await updateMyStress(score: evaluated.value, level: evaluated.level.rawValue)
    }

    // MARK: - Load friends from server

    func refreshFriends() async {
        guard TempoSession.shared.isLoggedIn else {
            friends = []
            friendSyncState = .empty
            return
        }
        guard !isFriendRefreshInFlight else { return }
        isFriendRefreshInFlight = true
        defer { isFriendRefreshInFlight = false }

        if friends.isEmpty, let cached = readFriendSnapshotCache() {
            applyServerFriendSnapshots(cached.snapshots)
            lastSuccessfulFriendSyncAt = cached.updatedAt
            friendSyncState = .cached(cached.updatedAt)
        } else if friends.isEmpty {
            friendSyncState = .loading
        }

        do {
            let response = try await TempoAPIClient.shared.friendStressSnapshots()
            applyServerFriendSnapshots(response.friends)
            let now = Date()
            lastSuccessfulFriendSyncAt = now
            writeFriendSnapshotCache(response.friends, updatedAt: now)
            friendSyncState = friends.isEmpty ? .empty : .ready(now)
        } catch {
            TempoLog.friends.debug("server friend stress refresh failed: \(error)")
            // 失败时保留上次 friends，并明确告诉页面正在显示缓存。
            if friends.isEmpty, let cached = readFriendSnapshotCache() {
                applyServerFriendSnapshots(cached.snapshots)
                lastSuccessfulFriendSyncAt = cached.updatedAt
                friendSyncState = .cached(cached.updatedAt)
            } else if !friends.isEmpty {
                friendSyncState = .cached(lastSuccessfulFriendSyncAt)
            } else {
                friendSyncState = .failed(TempoErrorCopy.message(for: error))
            }
        }
    }

    private func applyServerFriendSnapshots(_ snapshots: [ServerFriendStress]) {
        // server 返回的 active friendship 是双向关系的权威状态。
        // 这里主动清理旧 tombstone，避免延迟到达的 friend_removed push
        // 在重新绑定之后又单边隐藏密友。
        for snapshot in snapshots where !pendingServerRemovalIDs.contains(snapshot.userId) {
            restoreRemovedFriend(
                serverUserId: snapshot.userId,
                publicId: snapshot.publicId,
                zoneID: zoneIDForServerFriend(snapshot)
            )
        }
        friends = snapshots.map { snapshot in
            Friend(server: snapshot, fallbackZoneID: zoneIDForServerFriend(snapshot))
        }.filter { friend in
            friend.serverUserId.map { !pendingServerRemovalIDs.contains($0) } ?? true
        }
    }

    private var friendSnapshotCacheKey: String? {
        guard let userId = TempoSession.shared.userId, !userId.isEmpty else { return nil }
        return Self.friendSnapshotCachePrefix + userId
    }

    private func readFriendSnapshotCache() -> FriendSnapshotCacheEnvelope? {
        guard let key = friendSnapshotCacheKey,
              let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FriendSnapshotCacheEnvelope.self, from: data)
    }

    private func writeFriendSnapshotCache(_ snapshots: [ServerFriendStress], updatedAt: Date) {
        guard let key = friendSnapshotCacheKey,
              let data = try? JSONEncoder().encode(
                FriendSnapshotCacheEnvelope(snapshots: snapshots, updatedAt: updatedAt)
              ) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func zoneIDForServerFriend(_ snapshot: ServerFriendStress) -> CKRecordZone.ID {
        // CKRecordZone.ID 仅作为 Friend 模型字段(老 schema 字段,server-backed friend 的 ownerName == "_tempoServer")
        return CKRecordZone.ID(zoneName: "server.\(snapshot.userId)", ownerName: "_tempoServer")
    }

    // MARK: - Send encourage to a friend

    func sendEncourage(to friend: Friend, message: String) async throws {
        let toUserId: String?
        if let existingServerUserId = friend.serverUserId {
            toUserId = existingServerUserId
        } else {
            toUserId = await resolveServerUserId(for: friend)
        }
        guard let toUserId else {
            throw FriendError.serverIdentityMissing
        }
        let response = try await TempoAPIClient.shared.sendCareEvent(
            toUserId: toUserId,
            type: "encourage",
            message: message
        )
        appendToCareTimeline(response.event)
    }

    /// 用户主动确认后分享结构化压力摘要。payload 只含区间聚合值,不含逐点 HealthKit 记录。
    func sendTrendSummary(to friend: Friend, payload: [String: String]) async throws {
        let toUserId: String?
        if let existingServerUserId = friend.serverUserId {
            toUserId = existingServerUserId
        } else {
            toUserId = await resolveServerUserId(for: friend)
        }
        guard let toUserId else {
            throw FriendError.serverIdentityMissing
        }
        let response = try await TempoAPIClient.shared.sendCareEvent(
            toUserId: toUserId,
            type: "trend_summary",
            payload: payload
        )
        appendToCareTimeline(response.event)
    }

    // MARK: - Resonant events(心跳 / 邀请呼吸 / 邀请冥想 / 完成回执)

    /// 给某朋友发一个共振事件.关怀动作走 Tempo server + APNs,不再写 CloudKit.
    func sendResonantEvent(
        to friend: Friend,
        type: ResonantEventType,
        payload: [String: String] = [:]
    ) async throws {
        let toUserId: String?
        if let existingServerUserId = friend.serverUserId {
            toUserId = existingServerUserId
        } else {
            toUserId = await resolveServerUserId(for: friend)
        }
        guard let toUserId else {
            throw FriendError.serverIdentityMissing
        }
        let response = try await TempoAPIClient.shared.sendCareEvent(
            toUserId: toUserId,
            type: type.rawValue,
            payload: payload
        )
        appendToCareTimeline(response.event)
        TempoLog.friends.debug("sent server care event \(type.rawValue) to \(friend.displayName, privacy: .private)")
    }

    /// 加载与当前密友的双向互动。发送状态以 server 入库为“已发送”,read_at 为“已查看”。
    func loadCareTimeline(for friend: Friend) async {
        guard TempoSession.shared.isLoggedIn else {
            careTimeline = []
            careTimelineFriendUserId = nil
            return
        }
        let friendUserId: String?
        if let existing = friend.serverUserId {
            friendUserId = existing
        } else {
            friendUserId = await resolveServerUserId(for: friend)
        }
        guard let friendUserId else {
            careTimeline = []
            careTimelineFriendUserId = nil
            return
        }

        if careTimelineFriendUserId != friendUserId {
            careTimelineFriendUserId = friendUserId
            careTimeline = CareTimelineCache.load(
                currentUserId: TempoSession.shared.userId,
                friendUserId: friendUserId
            )
        }
        isCareTimelineRefreshing = true
        defer { isCareTimelineRefreshing = false }
        do {
            let response = try await TempoAPIClient.shared.careEventTimeline(friendUserId: friendUserId)
            let loaded = response.events.map { CareInteraction(server: $0, currentUserId: TempoSession.shared.userId) }
                .sorted { $0.sentAt > $1.sentAt }
            CareTimelineCache.save(
                loaded,
                currentUserId: TempoSession.shared.userId,
                friendUserId: friendUserId
            )
            guard careTimelineFriendUserId == friendUserId else { return }
            careTimeline = loaded
        } catch {
            TempoLog.friends.debug("loadCareTimeline failed: \(error)")
            // 网络失败时保留已显示的本地时间线,避免面板退回空状态。
        }
    }

    /// 用一句话回应某条收到的关怀，并在 server 上保留原事件关联。
    func replyToCareEvent(_ event: CareInteraction, for friend: Friend, message: String) async throws {
        guard !event.isOutgoing else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let friendUserId: String?
        if let existing = friend.serverUserId {
            friendUserId = existing
        } else {
            friendUserId = await resolveServerUserId(for: friend)
        }
        guard let friendUserId else { throw FriendError.serverIdentityMissing }
        let response = try await TempoAPIClient.shared.sendCareEvent(
            toUserId: friendUserId,
            type: "encourage",
            message: trimmed,
            replyToEventId: event.eventId
        )
        appendToCareTimeline(response.event)
    }

    /// Apple Watch 快捷回复由 iPhone 中转；继续走同一条 Tempo server 关怀链路。
    /// friendUserID 与 eventID 来自已签名登录用户的 inbox 快照，Watch 不接触 session token。
    func replyToCareEventFromWatch(
        eventID: String,
        friendUserID: String,
        message: String
    ) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty, !friendUserID.isEmpty, !trimmed.isEmpty else { return }
        let response = try await TempoAPIClient.shared.sendCareEvent(
            toUserId: friendUserID,
            type: "encourage",
            message: trimmed,
            replyToEventId: eventID
        )
        appendToCareTimeline(response.event)
        await markCareEventsRead(eventIDs: [eventID])
    }

    /// 只标记用户真正打开的事件，避免点一位密友时把其他人的新关怀一起清掉。
    func markCareEventsRead(eventIDs: [String]) async {
        let ids = Array(Set(eventIDs)).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        do {
            let response = try await TempoAPIClient.shared.markCareEventsRead(eventIds: ids)
            let readAt = Date(timeIntervalSince1970: TimeInterval(response.readAt) / 1000)
            let idSet = Set(ids)
            for index in careTimeline.indices where idSet.contains(careTimeline[index].eventId) {
                careTimeline[index].readAt = readAt
            }
            for index in encourages.indices where encourages[index].serverEventId.map(idSet.contains) == true {
                encourages[index].readAt = readAt
            }
            for index in resonantEvents.indices where resonantEvents[index].serverEventId.map(idSet.contains) == true {
                resonantEvents[index].readAt = readAt
            }
            persistVisibleCareTimeline()
        } catch {
            TempoLog.friends.debug("markCareEventsRead failed: \(error)")
        }
    }

    private func appendToCareTimeline(_ event: ServerCareEvent) {
        let interaction = CareInteraction(server: event, currentUserId: TempoSession.shared.userId)
        let counterpartUserId = event.fromUserId == TempoSession.shared.userId ? event.toUserId : event.fromUserId
        if let counterpartUserId, careTimelineFriendUserId != counterpartUserId {
            careTimelineFriendUserId = counterpartUserId
            careTimeline = CareTimelineCache.load(
                currentUserId: TempoSession.shared.userId,
                friendUserId: counterpartUserId
            )
        }
        careTimeline.removeAll { $0.eventId == interaction.eventId }
        careTimeline.insert(interaction, at: 0)
        persistVisibleCareTimeline()
    }

    private func persistVisibleCareTimeline() {
        guard let friendUserId = careTimelineFriendUserId else { return }
        CareTimelineCache.save(
            careTimeline,
            currentUserId: TempoSession.shared.userId,
            friendUserId: friendUserId
        )
    }

    /// 从 Tempo server 读所有 ResonantEvent(朋友给我的).
    func loadResonantEvents() async {
        guard TempoSession.shared.isLoggedIn else {
            resonantEvents = []
            return
        }
        do {
            let response = try await TempoAPIClient.shared.careEventInbox()
            let loaded = response.events.compactMap { event in
                ResonantEvent(server: event, zoneID: zoneID(for: event))
            }
            resonantEvents = loaded.sorted { $0.sentAt > $1.sentAt }
            TempoLog.friends.debug("loaded \(self.resonantEvents.count) resonant events, unread \(self.unreadResonantEventsCount)")
        } catch {
            TempoLog.friends.debug("loadResonantEvents failed: \(error)")
        }
    }

    /// 把 lastReadAt 推到最新一条事件时间戳.
    func markResonantEventsRead() {
        let newDate = resonantEvents.first?.sentAt ?? Date()
        UserDefaults.standard.set(newDate.timeIntervalSince1970, forKey: "friends.resonantEvents.lastReadAt")
        lastResonantEventReadAt = newDate
        let ids = resonantEvents.compactMap(\.serverEventId)
        let now = Date()
        for index in resonantEvents.indices { resonantEvents[index].readAt = now }
        Task { await markCareEventsRead(eventIDs: ids) }
    }

    /// 删除一条事件.server-only(CloudKit fallback 已废弃).
    func deleteResonantEvent(_ event: ResonantEvent) async {
        guard let serverEventId = event.serverEventId else {
            // 没 serverEventId 说明是历史 CloudKit 残留事件,直接从内存里删,不查 server
            resonantEvents.removeAll { $0.id == event.id }
            return
        }
        do {
            try await TempoAPIClient.shared.deleteCareEvent(serverEventId)
            resonantEvents.removeAll { $0.id == event.id }
        } catch {
            TempoLog.friends.debug("deleteResonantEvent failed: \(error)")
        }
    }

    /// 给某朋友 ID 找最近的 events(可能用于卡片角标).
    func eventsFromFriend(_ friend: Friend) -> [ResonantEvent] {
        resonantEvents.filter { $0.zoneID == friend.zoneID }
    }

    // MARK: - Incoming encourages (from friends to me)

    /// 从 Tempo server 读朋友给我的鼓励.
    func loadEncourages() async {
        guard TempoSession.shared.isLoggedIn else {
            encourages = []
            return
        }
        do {
            let response = try await TempoAPIClient.shared.careEventInbox()
            let loaded = response.events.compactMap { event in
                Encourage(server: event, zoneID: zoneID(for: event))
            }
            encourages = loaded.sorted { $0.sentAt > $1.sentAt }
            TempoLog.friends.debug("loaded \(self.encourages.count) encourages, unread \(self.unreadEncouragesCount)")
        } catch {
            TempoLog.friends.debug("loadEncourages failed: \(error)")
        }
    }

    /// 把 lastReadAt 推到最新一条的时间戳.
    func markAllEncouragesRead() {
        let newDate = encourages.first?.sentAt ?? Date()
        UserDefaults.standard.set(newDate.timeIntervalSince1970, forKey: "friends.encourages.lastReadAt")
        lastEncourageReadAt = newDate
        let ids = encourages.compactMap(\.serverEventId)
        let now = Date()
        for index in encourages.indices { encourages[index].readAt = now }
        Task { await markCareEventsRead(eventIDs: ids) }
    }

    // MARK: - Mute / Sharing toggle

    func isMuted(_ friend: Friend) -> Bool {
        muteIDs(for: friend).contains { mutedFriendIDs.contains($0) }
    }

    func isMuted(serverUserId: String?, publicId: String? = nil, displayName: String? = nil, zoneID: CKRecordZone.ID? = nil) -> Bool {
        if let friend = friends.first(where: { friend in
            (serverUserId != nil && friend.serverUserId == serverUserId)
            || (publicId != nil && friend.publicId == publicId)
            || (zoneID != nil && friend.zoneID == zoneID)
            || (displayName != nil && friend.displayName == displayName)
        }) {
            return isMuted(friend)
        }
        if let serverUserId, mutedFriendIDs.contains(serverUserId) { return true }
        if let publicId, mutedFriendIDs.contains(publicId) { return true }
        return false
    }

    private func muteIDs(for friend: Friend) -> [String] {
        [friend.id, friend.serverUserId, friend.publicId].compactMap { $0 }
    }

    private func persistMutedFriendIDs() {
        UserDefaults.standard.set(Array(mutedFriendIDs), forKey: "friends.muted")
    }

    // MARK: - Relationship label(本地存储,我对 Ta 的称呼/关系)

    func relationship(for friend: Friend) -> String? {
        UserDefaults.standard.string(forKey: "friend.relationship.\(friend.id)")
    }

    func setRelationship(_ label: String?, for friend: Friend) {
        let key = "friend.relationship.\(friend.id)"
        if let label, !label.isEmpty {
            UserDefaults.standard.set(label, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // 触发 observation
        friends = friends
    }

    func toggleMute(_ friend: Friend) {
        let shouldMute = !isMuted(friend)
        if shouldMute {
            muteIDs(for: friend).forEach { mutedFriendIDs.insert($0) }
        } else {
            muteIDs(for: friend).forEach { mutedFriendIDs.remove($0) }
        }
        persistMutedFriendIDs()
        PhoneSessionManager.shared.pushCachedSnapshotToWatch()

        guard let serverUserId = friend.serverUserId else { return }
        Task {
            do {
                try await TempoAPIClient.shared.setFriendMuted(userId: serverUserId, muted: shouldMute)
            } catch {
                TempoLog.friends.debug("server mute sync failed: \(error)")
            }
        }
    }

    func setSharingMyStress(_ on: Bool) {
        sharingMyStress = on
        UserDefaults.standard.set(on, forKey: "friends.sharingMyStress")
        if !on {
            Task { try? await TempoAPIClient.shared.deleteStressSnapshot() }
        } else {
            Task { await publishLatestStressSnapshotIfPossible() }
        }
        Task { _ = try? await TempoAPIClient.shared.updateSharePrefs(shareStress: on) }
    }

    func setShareTrainingWithFriends(_ on: Bool) {
        shareTrainingWithFriends = on
        UserDefaults.standard.set(on, forKey: "friends.shareTraining")
        Task { _ = try? await TempoAPIClient.shared.updateSharePrefs(shareTraining: on) }
    }

    func setShareHRVWithServer(_ on: Bool) {
        shareHRVWithServer = on
        UserDefaults.standard.set(on, forKey: "friends.shareHRV")
        Task { _ = try? await TempoAPIClient.shared.updateSharePrefs(shareHRV: on) }
        if on {
            Task { await uploadRecentHRVIfPossible(daysBack: 1) }
        }
    }

    /// 启动时从 server 同步一次 share prefs(以 server 为准,跨设备保持一致).
    func syncSharePrefsFromServer() async {
        guard TempoSession.shared.isLoggedIn else { return }
        do {
            let resp = try await TempoAPIClient.shared.sharePrefs()
            sharingMyStress = resp.prefs.shareStress
            shareTrainingWithFriends = resp.prefs.shareTraining
            shareHRVWithServer = resp.prefs.shareHRV
            UserDefaults.standard.set(resp.prefs.shareStress, forKey: "friends.sharingMyStress")
            UserDefaults.standard.set(resp.prefs.shareTraining, forKey: "friends.shareTraining")
            UserDefaults.standard.set(resp.prefs.shareHRV, forKey: "friends.shareHRV")
        } catch {
            TempoLog.friends.debug("syncSharePrefs failed: \(error)")
        }
    }

    func pauseStressSharing(forSeconds seconds: TimeInterval) {
        AlertSettings.shared.pauseSharing(forSeconds: seconds)
        Task { try? await TempoAPIClient.shared.deleteStressSnapshot() }
    }

    func resumeStressSharing() {
        AlertSettings.shared.resumeSharing()
        Task { await publishLatestStressSnapshotIfPossible() }
    }

    // MARK: - Leave share (解除好友绑定)

    /// 通知 server 删除 friendship,并立即本机隐藏.
    func leaveShare(with friend: Friend) async {
        var delayedProblem: String?

        markFriendLocallyRemoved(friend)
        friends.removeAll { $0.id == friend.id }
        let mutedBefore = mutedFriendIDs
        muteIDs(for: friend).forEach { mutedFriendIDs.remove($0) }
        if mutedFriendIDs != mutedBefore {
            persistMutedFriendIDs()
        }

        let serverUserId: String?
        if let existingServerUserId = friend.serverUserId {
            serverUserId = existingServerUserId
        } else {
            serverUserId = await resolveServerUserId(for: friend)
        }
        if let serverUserId {
            locallyRemovedServerUserIDs.insert(serverUserId)
            UserDefaults.standard.set(Array(locallyRemovedServerUserIDs), forKey: "friends.locallyRemoved.serverUserIds")
            pendingServerRemovalIDs.insert(serverUserId)
            do {
                try await TempoAPIClient.shared.removeFriend(userId: serverUserId)
                pendingServerRemovalIDs.remove(serverUserId)
            } catch {
                pendingServerRemovalIDs.remove(serverUserId)
                delayedProblem = "解除没有完成,关系仍保持,请重试"
                TempoLog.friends.debug("server remove friend failed: \(error)")
                await refreshFriends()
            }
        } else {
            delayedProblem = "已从本机解除,对方通知可能延迟"
            TempoLog.friends.debug("friend has no server user id, skipped server removal")
        }

        if let delayedProblem {
            lastError = delayedProblem
        } else {
            lastError = nil
        }
        TempoLog.friends.debug("left friend \(friend.displayName, privacy: .private)")
    }

    private func resolveServerUserId(for friend: Friend) async -> String? {
        do {
            let response = try await TempoAPIClient.shared.friends()
            let exactMatches = response.friends.filter { summary in
                if let publicId = friend.publicId, let summaryPublicId = summary.publicId {
                    return publicId == summaryPublicId
                }
                return summary.displayName == friend.displayName
            }
            let resolved: ServerFriendSummary?
            if exactMatches.count == 1 {
                resolved = exactMatches[0]
            } else if response.friends.count == 1 && friends.count == 1 {
                resolved = response.friends[0]
            } else {
                resolved = nil
            }
            if let resolved {
                FriendIdentityStore.store(
                    serverUserId: resolved.userId,
                    publicId: resolved.publicId,
                    for: friend.zoneID
                )
                return resolved.userId
            }
        } catch {
            TempoLog.friends.debug("resolve server friend id failed: \(error)")
        }
        return nil
    }

    private func zoneID(for event: ServerCareEvent) -> CKRecordZone.ID {
        if let friend = friends.first(where: {
            $0.serverUserId == event.fromUserId
            || $0.publicId == event.fromPublicId
            || $0.displayName == event.fromName
        }) {
            return friend.zoneID
        }
        return CKRecordZone.ID(zoneName: "_serverCareEvents", ownerName: CKCurrentUserDefaultName)
    }

    private func isLocallyRemoved(_ friend: Friend) -> Bool {
        locallyRemovedFriendIDs.contains(friend.id)
        || friend.serverUserId.map { locallyRemovedServerUserIDs.contains($0) } == true
        || friend.publicId.map { locallyRemovedPublicIDs.contains($0) } == true
    }

    private func markFriendLocallyRemoved(_ friend: Friend) {
        locallyRemovedFriendIDs.insert(friend.id)
        if let serverUserId = friend.serverUserId {
            locallyRemovedServerUserIDs.insert(serverUserId)
            locallyRemovedAtByServerUserID[serverUserId] = Date().timeIntervalSince1970
        }
        if let publicId = friend.publicId {
            locallyRemovedPublicIDs.insert(publicId)
        }
        UserDefaults.standard.set(Array(locallyRemovedFriendIDs), forKey: "friends.locallyRemoved.ids")
        UserDefaults.standard.set(Array(locallyRemovedServerUserIDs), forKey: "friends.locallyRemoved.serverUserIds")
        UserDefaults.standard.set(Array(locallyRemovedPublicIDs), forKey: "friends.locallyRemoved.publicIds")
        persistLocallyRemovedTimestamps()
    }

    func rememberServerIdentity(userId: String?, publicId: String?, for zoneID: CKRecordZone.ID) {
        FriendIdentityStore.store(serverUserId: userId, publicId: publicId, for: zoneID)
    }

    func restoreRemovedFriend(serverUserId: String?, publicId: String?, zoneID: CKRecordZone.ID? = nil) {
        var changed = false
        if let zoneID {
            let friendID = "\(zoneID.zoneName).\(zoneID.ownerName).\(Self.myStressRecordName)"
            if locallyRemovedFriendIDs.remove(friendID) != nil {
                changed = true
            }
        }
        if let serverUserId, locallyRemovedServerUserIDs.remove(serverUserId) != nil {
            changed = true
        }
        if let serverUserId, locallyRemovedFriendIDs.remove(serverUserId) != nil {
            changed = true
        }
        if let publicId, locallyRemovedPublicIDs.remove(publicId) != nil {
            changed = true
        }
        if let serverUserId, locallyRemovedAtByServerUserID.removeValue(forKey: serverUserId) != nil {
            changed = true
        }
        if changed {
            UserDefaults.standard.set(Array(locallyRemovedFriendIDs), forKey: "friends.locallyRemoved.ids")
            UserDefaults.standard.set(Array(locallyRemovedServerUserIDs), forKey: "friends.locallyRemoved.serverUserIds")
            UserDefaults.standard.set(Array(locallyRemovedPublicIDs), forKey: "friends.locallyRemoved.publicIds")
            persistLocallyRemovedTimestamps()
        }
    }

    private func persistLocallyRemovedTimestamps() {
        UserDefaults.standard.set(
            locallyRemovedAtByServerUserID,
            forKey: "friends.locallyRemoved.atByServerUserId"
        )
    }

    @discardableResult
    func applyRemoteFriendRemoval(
        serverUserId: String?,
        publicId: String?,
        displayName: String?,
        removedAt: TimeInterval? = nil
    ) -> Bool {
        if let serverUserId {
            locallyRemovedServerUserIDs.insert(serverUserId)
            locallyRemovedAtByServerUserID[serverUserId] = removedAt ?? Date().timeIntervalSince1970
        }
        if let publicId {
            locallyRemovedPublicIDs.insert(publicId)
        }
        var didRemove = false
        friends.removeAll { friend in
            let matched =
                (serverUserId != nil && friend.serverUserId == serverUserId)
                || (publicId != nil && friend.publicId == publicId)
                || (displayName != nil && friend.displayName == displayName)
            if matched {
                locallyRemovedFriendIDs.insert(friend.id)
                didRemove = true
            }
            return matched
        }
        UserDefaults.standard.set(Array(locallyRemovedFriendIDs), forKey: "friends.locallyRemoved.ids")
        UserDefaults.standard.set(Array(locallyRemovedServerUserIDs), forKey: "friends.locallyRemoved.serverUserIds")
        UserDefaults.standard.set(Array(locallyRemovedPublicIDs), forKey: "friends.locallyRemoved.publicIds")
        persistLocallyRemovedTimestamps()
        return didRemove
    }

    func handleRemoteFriendRemoval(
        serverUserId: String?,
        publicId: String?,
        displayName: String?,
        removedAt: TimeInterval? = nil
    ) async {
        _ = applyRemoteFriendRemoval(
            serverUserId: serverUserId,
            publicId: publicId,
            displayName: displayName,
            removedAt: removedAt
        )
        // push 可能延迟或乱序。如果 server 上已有新的 active friendship,
        // refreshFriends 会立即恢复密友;真正的解除则不会再返回该好友。
        await refreshFriends()
    }

    // MARK: - Health alerts(向好友发"信号",绝不带数值)
    //
    // 架构注:已从 CloudKit 改走 server care_events 通道.
    //  - 发:遍历 friends 用 sendCareEvent type="health_alert", payload {metric, severity, cleared}
    //  - 收:由 refreshCareInbox 一次性拉,按 metric 分桶取最新一条决定是否 active
    //  - 优势:不依赖 iCloud、TestFlight/正式包都能 push、跨设备状态同步

    /// 记住本地 active 的 metric(让 writeHealthAlert 在同 metric 频繁触发时不重发)
    @ObservationIgnored
    private var activeAlertMetrics: Set<HealthAlertMetric> = []

    /// 触发一个健康告警:广播给所有有 server identity 的密友.
    /// 不写 CloudKit、不存数值,只发 metric + severity 信号.
    func writeHealthAlert(metric: HealthAlertMetric, severity: HealthAlertSeverity) async {
        guard sharingMyStress else { return }
        if AlertSettings.shared.isPaused { return }
        guard TempoSession.shared.isLoggedIn else { return }

        let payload: [String: String] = [
            "metric": metric.rawValue,
            "severity": severity.rawValue,
            "cleared": "0"
        ]
        var sent = 0
        for friend in friends {
            guard let toUserId = friend.serverUserId else { continue }
            do {
                _ = try await TempoAPIClient.shared.sendCareEvent(
                    toUserId: toUserId,
                    type: "health_alert",
                    payload: payload
                )
                sent += 1
            } catch {
                TempoLog.friends.debug("health alert send failed: \(error)")
            }
        }
        activeAlertMetrics.insert(metric)
        TempoLog.friends.debug("health alert \(metric.rawValue) \(severity.rawValue) broadcast to \(sent) friends")
    }

    /// 标记 metric 的 alert 已恢复:广播 cleared=1.
    func clearHealthAlert(metric: HealthAlertMetric) async {
        guard activeAlertMetrics.contains(metric) else { return }
        guard TempoSession.shared.isLoggedIn else { return }

        let payload: [String: String] = [
            "metric": metric.rawValue,
            "severity": "info",
            "cleared": "1"
        ]
        for friend in friends {
            guard let toUserId = friend.serverUserId else { continue }
            do {
                _ = try await TempoAPIClient.shared.sendCareEvent(
                    toUserId: toUserId,
                    type: "health_alert",
                    payload: payload
                )
            } catch {
                TempoLog.friends.debug("health alert clear failed: \(error)")
            }
        }
        activeAlertMetrics.remove(metric)
    }

    /// 从 server care-events inbox 加载 friend 端 active 的 HealthAlert.
    /// 规则:同 fromUser + metric 取最新一条;cleared=1 跳过;> 24h 跳过.
    func loadFriendAlerts() async {
        guard TempoSession.shared.isLoggedIn else {
            friendAlerts = []
            return
        }
        do {
            let response = try await TempoAPIClient.shared.careEventInbox()
            // (fromUserId, metric) → latest event
            var latest: [String: ServerCareEvent] = [:]
            for ev in response.events where ev.type == "health_alert" {
                let metric = ev.payload["metric"] ?? ""
                let key = "\(ev.fromUserId).\(metric)"
                if let existing = latest[key], existing.createdAt >= ev.createdAt { continue }
                latest[key] = ev
            }
            let now = Date()
            let alerts: [FriendAlert] = latest.values.compactMap { ev in
                guard ev.payload["cleared"] != "1" else { return nil }
                guard let metric = HealthAlertMetric(rawValue: ev.payload["metric"] ?? "") else { return nil }
                guard let severity = HealthAlertSeverity(rawValue: ev.payload["severity"] ?? "") else { return nil }
                let triggeredAt = Date(timeIntervalSince1970: TimeInterval(ev.createdAt) / 1000)
                guard now.timeIntervalSince(triggeredAt) < 86400 else { return nil }
                // 用 fromUserId 构造一个稳定的 zoneID,跟 refreshFriends/server-side Friend 一致
                let zoneID = CKRecordZone.ID(zoneName: "server.\(ev.fromUserId)", ownerName: "_tempoServer")
                return FriendAlert(
                    id: ev.eventId,
                    metric: metric,
                    severity: severity,
                    triggeredAt: triggeredAt,
                    cleared: false,
                    fromName: ev.fromName,
                    zoneID: zoneID,
                    recordID: CKRecord.ID(recordName: ev.eventId, zoneID: zoneID)
                )
            }
            friendAlerts = alerts.sorted { $0.triggeredAt > $1.triggeredAt }
            TempoLog.friends.debug("loaded \(self.friendAlerts.count) active friend alerts (server)")
        } catch {
            TempoLog.friends.debug("loadFriendAlerts failed: \(error)")
        }
    }

    /// 给某朋友 ID 找最近的 active alert(用于 friendCard 显示徽章)
    func activeAlerts(for friend: Friend) -> [FriendAlert] {
        friendAlerts.filter { $0.zoneID == friend.zoneID }
    }

    /// 用户退出 Tempo server session(SiwA 登出 / 删账号)时调,清掉跟 server 关联的本地状态.
    /// 不影响 CloudKit 端的 friends / encourages / alerts(那些独立于 server 存在).
    func clearServerState() {
        pendingFriendRequestCount = 0
        friends.removeAll { $0.serverUserId != nil || $0.zoneID.ownerName == "_tempoServer" }
        encourages.removeAll { $0.serverEventId != nil }
        resonantEvents.removeAll { $0.serverEventId != nil }
        friendAlerts.removeAll { $0.zoneID.ownerName == "_tempoServer" }
        careTimeline = []
        careTimelineFriendUserId = nil
        isCareTimelineRefreshing = false
        mutedFriendIDs = []
        locallyRemovedFriendIDs = []
        locallyRemovedServerUserIDs = []
        locallyRemovedPublicIDs = []
        locallyRemovedAtByServerUserID = [:]
        pendingServerRemovalIDs = []
        isFriendRefreshInFlight = false
        friendSyncState = .idle
        lastSuccessfulFriendSyncAt = nil
        UserDefaults.standard.removeObject(forKey: "friends.muted")
        UserDefaults.standard.removeObject(forKey: "friends.locallyRemoved.ids")
        UserDefaults.standard.removeObject(forKey: "friends.locallyRemoved.serverUserIds")
        UserDefaults.standard.removeObject(forKey: "friends.locallyRemoved.publicIds")
        UserDefaults.standard.removeObject(forKey: "friends.locallyRemoved.atByServerUserId")
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix(Self.friendSnapshotCachePrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        CareTimelineCache.clearAll()
    }

    /// 拉取 server 上的待处理 friend request 数(给 Settings row badge 用)
    func refreshPendingFriendRequests() async {
        guard TempoSession.shared.isLoggedIn else {
            pendingFriendRequestCount = 0
            return
        }
        do {
            let resp = try await TempoAPIClient.shared.friendRequestInbox()
            pendingFriendRequestCount = resp.requests.count
        } catch {
            // 忽略,保持现有值
            TempoLog.friends.debug("refreshPendingFriendRequests failed: \(error)")
        }
    }

    /// 删除一条 encourage.server-only(CloudKit fallback 已废弃).
    func deleteEncourage(_ encourage: Encourage) async {
        guard let serverEventId = encourage.serverEventId else {
            // 旧 CloudKit 残留:只从内存里删
            encourages.removeAll { $0.id == encourage.id }
            return
        }
        do {
            try await TempoAPIClient.shared.deleteCareEvent(serverEventId)
            encourages.removeAll { $0.id == encourage.id }
        } catch {
            TempoLog.friends.debug("deleteEncourage failed: \(error)")
        }
    }
}

// MARK: - Friend alert model

struct FriendAlert: Identifiable, Hashable {
    let id: String
    let metric: HealthAlertMetric
    let severity: HealthAlertSeverity
    let triggeredAt: Date
    let cleared: Bool
    let fromName: String
    let zoneID: CKRecordZone.ID
    let recordID: CKRecord.ID

    /// 全字段 init,server-side 加载用.
    /// zoneID 用 `server.<serverUserId>` 命名约定,跟 Friend.serverUserId 对应,
    /// 让 `activeAlerts(for:)` 通过 zoneID 匹配 friend 卡片.
    init(id: String,
         metric: HealthAlertMetric,
         severity: HealthAlertSeverity,
         triggeredAt: Date,
         cleared: Bool,
         fromName: String,
         zoneID: CKRecordZone.ID,
         recordID: CKRecord.ID) {
        self.id = id
        self.metric = metric
        self.severity = severity
        self.triggeredAt = triggeredAt
        self.cleared = cleared
        self.fromName = fromName
        self.zoneID = zoneID
        self.recordID = recordID
    }

    init?(record: CKRecord, zoneID: CKRecordZone.ID) {
        guard let metricRaw = record["metric"] as? String,
              let metric = HealthAlertMetric(rawValue: metricRaw) else { return nil }
        guard let sevRaw = record["severity"] as? String,
              let severity = HealthAlertSeverity(rawValue: sevRaw) else { return nil }
        self.id = record.recordID.recordName
        self.recordID = record.recordID
        self.metric = metric
        self.severity = severity
        self.triggeredAt = (record["triggeredAt"] as? Date) ?? Date()
        let clearedRaw = (record["cleared"] as? Int64) ?? 0
        self.cleared = clearedRaw != 0
        self.fromName = (record["fromName"] as? String) ?? "好友"
        self.zoneID = zoneID
    }

    var formattedTime: String {
        let interval = Date().timeIntervalSince(triggeredAt)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}

// MARK: - ResonantEvent model

struct ResonantEvent: Identifiable, Hashable {
    let id: String
    let serverEventId: String?
    let type: ResonantEventType
    let fromName: String
    let fromUserId: String?
    let payload: [String: String]
    let sentAt: Date
    var readAt: Date?
    let zoneID: CKRecordZone.ID
    let recordID: CKRecord.ID

    init?(record: CKRecord, zoneID: CKRecordZone.ID) {
        guard let typeRaw = record["type"] as? String,
              let type = ResonantEventType(rawValue: typeRaw) else { return nil }
        self.id = record.recordID.recordName
        self.serverEventId = nil
        self.recordID = record.recordID
        self.zoneID = zoneID
        self.type = type
        self.fromName = (record["from"] as? String) ?? "好友"
        self.fromUserId = record["fromUserId"] as? String
        self.sentAt = (record["sentAt"] as? Date) ?? Date()
        self.readAt = nil
        if let json = record["payloadJSON"] as? String,
           let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            self.payload = dict
        } else {
            self.payload = [:]
        }
    }

    init?(server event: ServerCareEvent, zoneID: CKRecordZone.ID) {
        guard event.type != "encourage",
              let type = ResonantEventType(serverRawValue: event.type) else { return nil }
        self.id = event.eventId
        self.serverEventId = event.eventId
        self.recordID = CKRecord.ID(recordName: event.eventId, zoneID: zoneID)
        self.zoneID = zoneID
        self.type = type
        self.fromName = event.fromName
        self.fromUserId = event.fromUserId
        self.payload = event.payload
        self.sentAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt) / 1000)
        self.readAt = event.readAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    func isUnread(comparedWith legacyReadAt: Date) -> Bool {
        serverEventId != nil ? readAt == nil : sentAt > legacyReadAt
    }

    var formattedTime: String {
        let interval = Date().timeIntervalSince(sentAt)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}

private extension ResonantEventType {
    init?(serverRawValue: String) {
        switch serverRawValue {
        case "breathingInvite": self = .breathingInvite
        case "meditationInvite": self = .meditationInvite
        case "sessionCompleted": self = .sessionCompleted
        default:
            guard let value = ResonantEventType(rawValue: serverRawValue) else { return nil }
            self = value
        }
    }
}

// MARK: - Encourage model

struct Encourage: Identifiable, Hashable {
    let id: String
    let serverEventId: String?
    let message: String
    let fromName: String
    let fromUserId: String?
    let sentAt: Date
    var readAt: Date?
    let zoneID: CKRecordZone.ID
    let recordID: CKRecord.ID

    init?(record: CKRecord, zoneID: CKRecordZone.ID) {
        guard let message = record["message"] as? String, !message.isEmpty else { return nil }
        self.id = record.recordID.recordName
        self.serverEventId = nil
        self.recordID = record.recordID
        self.zoneID = zoneID
        self.message = message
        self.fromName = (record["from"] as? String) ?? "好友"
        self.fromUserId = record["fromUserId"] as? String
        self.sentAt = (record["sentAt"] as? Date) ?? Date()
        self.readAt = nil
    }

    init?(server event: ServerCareEvent, zoneID: CKRecordZone.ID) {
        guard event.type == "encourage",
              let message = event.message,
              !message.isEmpty else { return nil }
        self.id = event.eventId
        self.serverEventId = event.eventId
        self.recordID = CKRecord.ID(recordName: event.eventId, zoneID: zoneID)
        self.zoneID = zoneID
        self.message = message
        self.fromName = event.fromName
        self.fromUserId = event.fromUserId
        self.sentAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt) / 1000)
        self.readAt = event.readAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    func isUnread(comparedWith legacyReadAt: Date) -> Bool {
        serverEventId != nil ? readAt == nil : sentAt > legacyReadAt
    }

    var formattedTime: String {
        let interval = Date().timeIntervalSince(sentAt)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 86400 * 7 { return "\(Int(interval / 86400)) 天前" }
        return DateFormatter.localizedString(from: sentAt, dateStyle: .short, timeStyle: .none)
    }
}

// MARK: - Bidirectional care timeline

private enum CareTimelineCache {
    private static let keyIndex = "friends.careTimeline.cacheKeys"

    private static func key(currentUserId: String, friendUserId: String) -> String {
        "friends.careTimeline.\(currentUserId).\(friendUserId)"
    }

    static func load(currentUserId: String?, friendUserId: String) -> [CareInteraction] {
        guard let currentUserId, !currentUserId.isEmpty else { return [] }
        let cacheKey = key(currentUserId: currentUserId, friendUserId: friendUserId)
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([CareInteraction].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.sentAt > $1.sentAt }
    }

    static func save(_ timeline: [CareInteraction], currentUserId: String?, friendUserId: String) {
        guard let currentUserId, !currentUserId.isEmpty,
              let data = try? JSONEncoder().encode(Array(timeline.prefix(80))) else { return }
        let cacheKey = key(currentUserId: currentUserId, friendUserId: friendUserId)
        UserDefaults.standard.set(data, forKey: cacheKey)
        var keys = Set(UserDefaults.standard.stringArray(forKey: keyIndex) ?? [])
        if keys.insert(cacheKey).inserted {
            UserDefaults.standard.set(Array(keys), forKey: keyIndex)
        }
    }

    static func clearAll() {
        let keys = UserDefaults.standard.stringArray(forKey: keyIndex) ?? []
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: keyIndex)
    }
}

struct CareInteraction: Identifiable, Hashable, Codable {
    let eventId: String
    let typeRawValue: String
    let message: String?
    let payload: [String: String]
    let fromUserId: String
    let fromName: String
    let toUserId: String?
    let toName: String?
    let replyToEventId: String?
    let sentAt: Date
    var readAt: Date?
    let isOutgoing: Bool

    var id: String { eventId }

    init(server event: ServerCareEvent, currentUserId: String?) {
        eventId = event.eventId
        typeRawValue = event.type
        message = event.message
        payload = event.payload
        fromUserId = event.fromUserId
        fromName = event.fromName
        toUserId = event.toUserId
        toName = event.toName
        replyToEventId = event.replyToEventId
        sentAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt) / 1000)
        readAt = event.readAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        isOutgoing = event.fromUserId == currentUserId
    }

    var eventType: ResonantEventType? {
        ResonantEventType(serverRawValue: typeRawValue)
    }

    var icon: String {
        if typeRawValue == "encourage" { return "text.bubble.fill" }
        if typeRawValue == "trend_summary" { return "chart.xyaxis.line" }
        return eventType?.icon ?? "heart.circle.fill"
    }

    var displayBody: String {
        if let message, !message.isEmpty { return message }
        if typeRawValue == "trend_summary" {
            return "分享了一份 \(payload["range"] ?? "近期")压力摘要"
        }
        if let eventType {
            return ResonantEventMessage.notificationBody(type: eventType, payload: payload)
        }
        return "一条关怀"
    }

    var formattedTime: String {
        let interval = Date().timeIntervalSince(sentAt)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 86400 * 7 { return "\(Int(interval / 86400)) 天前" }
        return DateFormatter.localizedString(from: sentAt, dateStyle: .short, timeStyle: .none)
    }
}

// MARK: - Friend model

private enum FriendIdentityStore {
    private static func zoneKey(_ zoneID: CKRecordZone.ID) -> String {
        "\(zoneID.ownerName)|\(zoneID.zoneName)"
    }

    static func store(serverUserId: String?, publicId: String?, for zoneID: CKRecordZone.ID) {
        let key = zoneKey(zoneID)
        if let serverUserId, !serverUserId.isEmpty {
            UserDefaults.standard.set(serverUserId, forKey: "friend.serverUserId.\(key)")
        }
        if let publicId, !publicId.isEmpty {
            UserDefaults.standard.set(publicId, forKey: "friend.publicId.\(key)")
        }
    }

    static func serverUserId(for zoneID: CKRecordZone.ID) -> String? {
        UserDefaults.standard.string(forKey: "friend.serverUserId.\(zoneKey(zoneID))")
    }

    static func publicId(for zoneID: CKRecordZone.ID) -> String? {
        UserDefaults.standard.string(forKey: "friend.publicId.\(zoneKey(zoneID))")
    }
}

struct Friend: Identifiable, Hashable {
    let id: String
    let displayName: String
    let stressScore: Int
    let stressLevelRaw: String
    let lastUpdated: Date
    let zoneID: CKRecordZone.ID
    let serverUserId: String?
    let publicId: String?

    init?(record: CKRecord, zoneID: CKRecordZone.ID) {
        self.id = "\(zoneID.zoneName).\(zoneID.ownerName).\(record.recordID.recordName)"
        self.displayName = (record["displayName"] as? String) ?? "好友"
        self.stressScore = Int((record["score"] as? Int64) ?? 0)
        self.stressLevelRaw = (record["level"] as? String) ?? "unknown"
        self.lastUpdated = (record["lastUpdated"] as? Date) ?? .distantPast
        self.zoneID = zoneID
        self.serverUserId = (record[FriendsService.tempoUserIdField] as? String)
            ?? FriendIdentityStore.serverUserId(for: zoneID)
        self.publicId = (record[FriendsService.tempoPublicIdField] as? String)
            ?? FriendIdentityStore.publicId(for: zoneID)
        FriendIdentityStore.store(serverUserId: serverUserId, publicId: publicId, for: zoneID)
    }

    init(server snapshot: ServerFriendStress, fallbackZoneID: CKRecordZone.ID) {
        self.id = snapshot.userId
        self.displayName = snapshot.displayName
        self.stressScore = snapshot.stressScore
        self.stressLevelRaw = snapshot.hasStress ? snapshot.stressLevel : "unknown"
        if let lastUpdated = snapshot.lastUpdated {
            self.lastUpdated = Date(timeIntervalSince1970: TimeInterval(lastUpdated) / 1000)
        } else {
            self.lastUpdated = .distantPast
        }
        self.zoneID = fallbackZoneID
        self.serverUserId = snapshot.userId
        self.publicId = snapshot.publicId
        FriendIdentityStore.store(serverUserId: snapshot.userId, publicId: snapshot.publicId, for: fallbackZoneID)
    }

    var levelDisplay: String {
        switch stressLevelRaw {
        case "calm": "平静"
        case "relaxed": "放松"
        case "mild": "轻度"
        case "high": "较高"
        case "extreme": "极高"
        default: "未知"
        }
    }

    var levelColor: Color {
        switch stressLevelRaw {
        case "calm", "relaxed": TempoTheme.success
        case "mild": TempoTheme.warning
        case "high": Color(hex: "F97316")
        case "extreme": TempoTheme.danger
        default: TempoTheme.tertiaryText
        }
    }

    var formattedLastUpdated: String {
        let interval = Date().timeIntervalSince(lastUpdated)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}

// MARK: - Errors

enum FriendError: LocalizedError {
    case serverIdentityMissing

    var errorDescription: String? {
        switch self {
        case .serverIdentityMissing: return "密友通道需要刷新:请回到「共振设置」下拉刷新后再试"
        }
    }
}

// MARK: - Encourage Presets

enum EncouragePresets {
    static let all: [String] = [
        "深呼吸一下,我陪你 ❤️",
        "今天辛苦了,休息一会儿吧",
        "你做得很好了,放松一下",
        "需要散个步吗?我陪你 🌿",
        "停下来,做组 4-7-8 呼吸",
        "我在,有事随时叫我",
        "记得喝点水 💧",
        "去看看窗外吧 🌅"
    ]
}
