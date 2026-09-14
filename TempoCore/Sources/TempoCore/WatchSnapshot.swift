//
//  WatchSnapshot.swift
//  TempoCore
//
//  Phone → Watch 推送的「派生指标快照」。
//  Watch 屏幕小、电池有限,不在 Watch 端跑 28 天 baseline 扫描,
//  而是 Phone 算好后通过 WCSession.updateApplicationContext 推。
//

import Foundation

/// Phone -> Watch 的一条未读关怀摘要。
/// 只带展示与回复路由所需字段，不包含 HealthKit 原始数据。
public struct WatchCareSignal: Codable, Hashable, Sendable {
    public let eventID: String
    public let friendUserID: String
    public let senderName: String
    public let message: String
    public let kind: String
    public let sentAt: Date

    public init(
        eventID: String,
        friendUserID: String,
        senderName: String,
        message: String,
        kind: String,
        sentAt: Date
    ) {
        self.eventID = eventID
        self.friendUserID = friendUserID
        self.senderName = senderName
        self.message = message
        self.kind = kind
        self.sentAt = sentAt
    }
}

public struct WatchSnapshot: Codable, Hashable, Sendable {
    // Stress
    public let stressValue: Int?
    public let stressLevelRaw: String?

    // Recovery
    public let recoveryValue: Int?
    public let recoveryLevelRaw: String?
    public let recoveryHasElevatedTemp: Bool

    // Strain
    public let strainValue: Double?
    public let strainLevelRaw: String?

    // Vitals
    public let latestHR: Double?
    public let latestHRV: Double?
    public let restingHR: Double?

    // Sleep
    public let deepSleepHours: Double?
    public let remSleepHours: Double?
    public let totalAsleepHours: Double?

    // Temperature
    public let wristTempZScore: Double?

    // Resonance care
    public let careSignal: WatchCareSignal?

    // Algorithm version + freshness
    public let algorithmVersion: Int
    public let updatedAt: Date

    public init(
        stressValue: Int? = nil,
        stressLevelRaw: String? = nil,
        recoveryValue: Int? = nil,
        recoveryLevelRaw: String? = nil,
        recoveryHasElevatedTemp: Bool = false,
        strainValue: Double? = nil,
        strainLevelRaw: String? = nil,
        latestHR: Double? = nil,
        latestHRV: Double? = nil,
        restingHR: Double? = nil,
        deepSleepHours: Double? = nil,
        remSleepHours: Double? = nil,
        totalAsleepHours: Double? = nil,
        wristTempZScore: Double? = nil,
        careSignal: WatchCareSignal? = nil,
        algorithmVersion: Int = AlgorithmVersion.current,
        updatedAt: Date = .now
    ) {
        self.stressValue = stressValue
        self.stressLevelRaw = stressLevelRaw
        self.recoveryValue = recoveryValue
        self.recoveryLevelRaw = recoveryLevelRaw
        self.recoveryHasElevatedTemp = recoveryHasElevatedTemp
        self.strainValue = strainValue
        self.strainLevelRaw = strainLevelRaw
        self.latestHR = latestHR
        self.latestHRV = latestHRV
        self.restingHR = restingHR
        self.deepSleepHours = deepSleepHours
        self.remSleepHours = remSleepHours
        self.totalAsleepHours = totalAsleepHours
        self.wristTempZScore = wristTempZScore
        self.careSignal = careSignal
        self.algorithmVersion = algorithmVersion
        self.updatedAt = updatedAt
    }

    public var stressLevel: StressLevel? {
        stressLevelRaw.flatMap { StressLevel(rawValue: $0) }
    }

    public var recoveryLevel: RecoveryLevel? {
        recoveryLevelRaw.flatMap { RecoveryLevel(rawValue: $0) }
    }

    public var strainLevel: StrainLevel? {
        strainLevelRaw.flatMap { StrainLevel(rawValue: $0) }
    }

    /// 数据是否「新鲜」(2h 内)
    public var isFresh: Bool {
        Date().timeIntervalSince(updatedAt) < 2 * 3600
    }

    // MARK: - Codable JSON helpers(WC payload)

    public func encodeJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeJSON(_ s: String) -> WatchSnapshot? {
        guard let data = s.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchSnapshot.self, from: data)
    }

    /// 保留所有健康指标，只替换手表关怀卡。
    public func replacingCareSignal(_ signal: WatchCareSignal?) -> WatchSnapshot {
        WatchSnapshot(
            stressValue: stressValue,
            stressLevelRaw: stressLevelRaw,
            recoveryValue: recoveryValue,
            recoveryLevelRaw: recoveryLevelRaw,
            recoveryHasElevatedTemp: recoveryHasElevatedTemp,
            strainValue: strainValue,
            strainLevelRaw: strainLevelRaw,
            latestHR: latestHR,
            latestHRV: latestHRV,
            restingHR: restingHR,
            deepSleepHours: deepSleepHours,
            remSleepHours: remSleepHours,
            totalAsleepHours: totalAsleepHours,
            wristTempZScore: wristTempZScore,
            careSignal: signal,
            algorithmVersion: algorithmVersion,
            updatedAt: updatedAt
        )
    }

    /// 空快照没有真实采集时间，避免 UI 把它误报成“刚刚”。
    public static let empty = WatchSnapshot(updatedAt: .distantPast)
}
