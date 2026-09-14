import Foundation
import Testing
@testable import TempoCore

@Suite("WatchSnapshot 关怀与刷新契约")
struct WatchSnapshotCareTests {
    @Test("空快照没有伪造更新时间")
    func emptySnapshotHasNoFreshTimestamp() {
        #expect(WatchSnapshot.empty.updatedAt == .distantPast)
        #expect(!WatchSnapshot.empty.isFresh)
    }

    @Test("旧快照没有 careSignal 仍能解码")
    func legacySnapshotStillDecodes() throws {
        let legacy = WatchSnapshot(
            stressValue: 62,
            stressLevelRaw: StressLevel.mild.rawValue,
            latestHR: 78,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let json = try #require(legacy.encodeJSON())
        #expect(!json.contains("careSignal"))

        let decoded = try #require(WatchSnapshot.decodeJSON(json))
        #expect(decoded.stressValue == 62)
        #expect(decoded.careSignal == nil)
    }

    @Test("关怀信号 JSON 往返保持路由字段")
    func careSignalRoundTrip() throws {
        let signal = WatchCareSignal(
            eventID: "evt-1",
            friendUserID: "friend-1",
            senderName: "小满",
            message: "今天辛苦了",
            kind: "encourage",
            sentAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let snapshot = WatchSnapshot(
            stressValue: 71,
            stressLevelRaw: StressLevel.high.rawValue,
            careSignal: signal,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )

        let json = try #require(snapshot.encodeJSON())
        let decoded = try #require(WatchSnapshot.decodeJSON(json))
        #expect(decoded.careSignal == signal)
        #expect(decoded.stressValue == snapshot.stressValue)
    }

    @Test("替换关怀不改健康数据与采集时间")
    func replacingCareKeepsHealthSnapshot() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_300)
        let base = WatchSnapshot(
            stressValue: 44,
            recoveryValue: 82,
            latestHRV: 56,
            updatedAt: updatedAt
        )
        let signal = WatchCareSignal(
            eventID: "evt-2",
            friendUserID: "friend-2",
            senderName: "阿禾",
            message: "抱抱你",
            kind: "heartbeat",
            sentAt: updatedAt
        )

        let merged = base.replacingCareSignal(signal)
        #expect(merged.stressValue == 44)
        #expect(merged.recoveryValue == 82)
        #expect(merged.latestHRV == 56)
        #expect(merged.updatedAt == updatedAt)
        #expect(merged.careSignal == signal)
    }

    @Test("新增 WatchConnectivity key 非空且唯一")
    func watchConnectivityKeysAreUnique() {
        let keys = [
            WCMessageKeys.watchSnapshotJSON,
            WCMessageKeys.watchRequestSnapshot,
            WCMessageKeys.watchCareReplyMessage,
            WCMessageKeys.watchCareFriendUserID,
            WCMessageKeys.watchCareEventID,
            WCMessageKeys.watchCareReplySucceeded,
            WCMessageKeys.watchCareReplyError,
        ]
        #expect(keys.allSatisfy { !$0.isEmpty })
        #expect(Set(keys).count == keys.count)
    }
}
