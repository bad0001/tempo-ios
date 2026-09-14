//
//  TempoAPIClient.swift
//  Tempo
//
//  与 Tempo API server (https://tempo.tiyicard.cn) 通信.
//  - Sign in with Apple 验证 → 拿 sessionToken
//  - 注册 APNs device token
//  - 创建 / 接受密友请求、同步压力摘要、路由关怀事件
//
//  ⚠️ 域名说明:
//   - 主域名 tiyicard.com 在做 ICP 备案,期间会停止解析(2026-04 ~ 5 月)
//   - 临时使用 .cn 域名(已实名 + 海外解析,新加坡服务器)
//   - server 端 nginx 同时响应 .com 和 .cn,等 .com 备案完成后会切回或保留双域
//

import Foundation
import TempoCore

@MainActor
final class TempoAPIClient {
    static let shared = TempoAPIClient()

    private let baseURL = URL(string: "https://tempo.tiyicard.cn")!

    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }

    // MARK: - Generic request

    private func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: Encodable? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let url: URL
        if path.contains("?"), let composed = URL(string: path, relativeTo: baseURL) {
            url = composed.absoluteURL
        } else {
            url = baseURL.appendingPathComponent(path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token = TempoSession.shared.sessionToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport
        }
        if http.statusCode == 401 {
            TempoSession.shared.clear()
            throw APIError.unauthorized
        }
        if http.statusCode >= 400 {
            let parsed = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            let msg = parsed?.error ?? "HTTP \(http.statusCode)"
            throw APIError.server(message: msg, status: http.statusCode, code: parsed?.code)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(error)
        }
    }

    // MARK: - Endpoints

    func authenticateApple(idToken: String, displayName: String?) async throws -> AuthResponse {
        try await request("POST", "/v1/auth/apple",
                          body: AuthRequest(idToken: idToken, displayName: displayName),
                          authenticated: false)
    }

    func getMe() async throws -> UserResponse {
        try await request("GET", "/v1/me")
    }

    func updateMe(displayName: String) async throws -> UserResponse {
        try await request("PATCH", "/v1/me", body: UpdateMeRequest(displayName: displayName))
    }

    func updateStressSnapshot(score: Int, level: String, displayName: String) async throws {
        let _: StressSnapshotResponse = try await request(
            "PUT",
            "/v1/me/stress",
            body: UpdateStressSnapshotBody(score: score, level: level, displayName: displayName)
        )
    }

    func deleteStressSnapshot() async throws {
        let _: OkResponse = try await request("DELETE", "/v1/me/stress")
    }

    func registerDevice(deviceId: String, apnsToken: String) async throws {
        let _: OkResponse = try await request("POST", "/v1/devices",
                                              body: DeviceRequest(deviceId: deviceId, apnsToken: apnsToken))
    }

    func unregisterDevice(deviceId: String) async throws {
        let encoded = deviceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceId
        let _: OkResponse = try await request("DELETE", "/v1/devices/\(encoded)")
    }

    func deleteAccount() async throws {
        let _: OkResponse = try await request("DELETE", "/v1/me")
    }

    // MARK: - Friend requests (server public_id 双向关系)

    func lookupUser(byPublicId id: String) async throws -> LookupUserResponse {
        try await request("GET", "/v1/users/by-public-id/\(id)")
    }

    func sendFriendRequest(toPublicId: String, shareUrl: String = "", isReverse: Bool = false) async throws -> FriendRequestCreatedResponse {
        try await request("POST", "/v1/friend-requests",
                          body: SendFriendRequestBody(toPublicId: toPublicId, shareUrl: shareUrl, isReverse: isReverse))
    }

    func friendRequestInbox() async throws -> FriendRequestInboxResponse {
        try await request("GET", "/v1/friend-requests/inbox")
    }

    func friendRequestOutgoing() async throws -> FriendRequestOutgoingResponse {
        try await request("GET", "/v1/friend-requests/outgoing")
    }

    func acceptFriendRequest(_ requestId: String) async throws -> FriendRequestAcceptResponse {
        try await request("POST", "/v1/friend-requests/\(requestId)/accept",
                          body: EmptyRequest())
    }

    func declineFriendRequest(_ requestId: String) async throws {
        let _: OkResponse = try await request("POST", "/v1/friend-requests/\(requestId)/decline",
                                              body: EmptyRequest())
    }

    func cancelFriendRequest(_ requestId: String) async throws {
        let _: OkResponse = try await request("POST", "/v1/friend-requests/\(requestId)/cancel",
                                              body: EmptyRequest())
    }

    func friends() async throws -> ServerFriendsResponse {
        try await request("GET", "/v1/friends")
    }

    func friendStressSnapshots() async throws -> FriendStressResponse {
        try await request("GET", "/v1/friends/stress")
    }

    func removeFriend(userId: String) async throws {
        let _: OkResponse = try await request("DELETE", "/v1/friends/\(userId)")
    }

    func setFriendMuted(userId: String, muted: Bool) async throws {
        let method = muted ? "PUT" : "DELETE"
        let _: OkResponse = try await request(method, "/v1/friends/\(userId)/mute")
    }

    func sendCareEvent(
        toUserId: String,
        type: String,
        message: String? = nil,
        payload: [String: String] = [:],
        replyToEventId: String? = nil
    ) async throws -> CareEventCreatedResponse {
        try await request("POST", "/v1/care-events",
                          body: SendCareEventBody(
                            toUserId: toUserId,
                            type: type,
                            message: message,
                            payload: payload,
                            replyToEventId: replyToEventId
                          ))
    }

    func careEventInbox() async throws -> CareEventInboxResponse {
        try await request("GET", "/v1/care-events/inbox")
    }

    func careEventTimeline(friendUserId: String? = nil) async throws -> CareEventInboxResponse {
        let suffix: String
        if let friendUserId {
            let encoded = friendUserId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? friendUserId
            suffix = "?friendUserId=\(encoded)"
        } else {
            suffix = ""
        }
        return try await request("GET", "/v1/care-events/timeline\(suffix)")
    }

    func markCareEventsRead(eventIds: [String]? = nil) async throws -> CareEventsReadResponse {
        try await request("POST", "/v1/care-events/read", body: MarkCareEventsReadBody(eventIds: eventIds))
    }

    func deleteCareEvent(_ eventId: String) async throws {
        let _: OkResponse = try await request("DELETE", "/v1/care-events/\(eventId)")
    }

    // MARK: - Stress bottles

    func createStressBottle(
        stressScore: Int?,
        stressLevel: String?,
        moodTag: String,
        message: String,
        anonymous: Bool
    ) async throws -> BottleCreatedResponse {
        try await request(
            "POST",
            "/v1/bottles",
            body: CreateBottleBody(
                stressScore: stressScore,
                stressLevel: stressLevel,
                moodTag: moodTag,
                message: message,
                anonymous: anonymous
            )
        )
    }

    func seaBottles(limit: Int = 8) async throws -> BottleListResponse {
        try await request("GET", "/v1/bottles/sea?limit=\(limit)")
    }

    func myBottles(limit: Int = 20) async throws -> BottleListResponse {
        try await request("GET", "/v1/bottles/mine?limit=\(limit)")
    }

    func replyToBottle(_ bottleId: String, message: String) async throws -> BottleReplyCreatedResponse {
        try await request("POST", "/v1/bottles/\(bottleId)/reply", body: BottleReplyBody(message: message))
    }

    func reportBottle(_ bottleId: String, reason: String) async throws {
        let _: OkResponse = try await request("POST", "/v1/bottles/\(bottleId)/report", body: BottleReportBody(reason: reason))
    }

    func reportBottleReply(_ bottleId: String, reason: String) async throws {
        let _: OkResponse = try await request("POST", "/v1/bottles/\(bottleId)/reply/report", body: BottleReportBody(reason: reason))
    }

    func blockBottleAuthor(_ bottleId: String) async throws {
        let _: OkResponse = try await request("POST", "/v1/bottles/\(bottleId)/block-author", body: EmptyRequest())
    }

    func blockBottleReplier(_ bottleId: String) async throws {
        let _: OkResponse = try await request("POST", "/v1/bottles/\(bottleId)/reply/block-author", body: EmptyRequest())
    }

    func deleteBottle(_ bottleId: String) async throws {
        let _: OkResponse = try await request("DELETE", "/v1/bottles/\(bottleId)")
    }

    // MARK: - Phase 2: 全量数据上传 / 朋友共享

    /// stress 上传(每次 stress 更新 append 一条 history)
    /// algorithmVersion 标记此 score 来自哪个版本算法,server 按版本分线展示。
    func appendStressHistory(score: Int, level: String, recordedAt: Date = Date(), algorithmVersion: Int = AlgorithmVersion.current) async throws {
        let _: OkResponse = try await request("POST", "/v1/me/stress/history",
            body: StressHistoryBody(
                score: score,
                level: level,
                recordedAt: Int64(recordedAt.timeIntervalSince1970 * 1000),
                algorithmVersion: algorithmVersion
            ))
    }

    func myStressHistory(days: Int = 30) async throws -> StressHistoryResponse {
        try await request("GET", "/v1/me/stress/history?days=\(days)")
    }

    func friendStressHistory(userId: String, days: Int = 7) async throws -> FriendStressHistoryResponse {
        try await request("GET", "/v1/friends/\(userId)/stress/history?days=\(days)")
    }

    /// HRV 批量上传
    func uploadHRVSamples(_ samples: [HRVSampleUpload]) async throws -> Int {
        let resp: HRVUploadResponse = try await request("POST", "/v1/me/hrv",
            body: HRVUploadBody(samples: samples))
        return resp.accepted
    }

    func myHRVHistory(days: Int = 7) async throws -> HRVHistoryResponse {
        try await request("GET", "/v1/me/hrv?days=\(days)")
    }

    /// 训练 session 上传
    func uploadBreathingSession(sessionId: String = UUID().uuidString, pattern: String, minutes: Int, completedAt: Date = Date()) async throws {
        let _: SessionCreatedResponse = try await request("POST", "/v1/me/sessions",
            body: SessionUploadBody(type: "breathing", sessionId: sessionId, pattern: pattern,
                                    minutes: minutes, completedAt: Int64(completedAt.timeIntervalSince1970 * 1000)))
    }

    func uploadMeditationSession(sessionId: String = UUID().uuidString, minutes: Int, completedAt: Date = Date()) async throws {
        let _: SessionCreatedResponse = try await request("POST", "/v1/me/sessions",
            body: SessionUploadBody(type: "meditation", sessionId: sessionId, pattern: nil,
                                    minutes: minutes, completedAt: Int64(completedAt.timeIntervalSince1970 * 1000)))
    }

    func mySessions(days: Int = 7) async throws -> SessionsResponse {
        try await request("GET", "/v1/me/sessions?days=\(days)")
    }

    func friendSessions(userId: String, days: Int = 7) async throws -> SessionsResponse {
        try await request("GET", "/v1/friends/\(userId)/sessions?days=\(days)")
    }

    /// daily_summary
    func upsertMyDailySummary(date: String, payload: DailySummaryBody) async throws {
        var body = payload
        body.date = date
        let _: OkResponse = try await request("POST", "/v1/me/daily-summary", body: body)
    }

    func myDailySummary(from: String, to: String) async throws -> DailySummaryListResponse {
        try await request("GET", "/v1/me/daily-summary?from=\(from)&to=\(to)")
    }

    func friendDailySummary(userId: String, from: String, to: String) async throws -> FriendDailySummaryResponse {
        try await request("GET", "/v1/friends/\(userId)/daily-summary?from=\(from)&to=\(to)")
    }

    /// 共享偏好
    func sharePrefs() async throws -> SharePrefsResponse {
        try await request("GET", "/v1/me/share-prefs")
    }

    func updateSharePrefs(shareStress: Bool? = nil, shareTraining: Bool? = nil, shareHRV: Bool? = nil) async throws -> SharePrefsResponse {
        try await request("PUT", "/v1/me/share-prefs",
            body: SharePrefsUpdateBody(shareStress: shareStress, shareTraining: shareTraining, shareHRV: shareHRV))
    }
}

// MARK: - Friend request models

struct LookupUserResponse: Decodable {
    let user: LookupedUser
    struct LookupedUser: Decodable {
        let userId: String
        let publicId: String
        let displayName: String?
    }
}

struct SendFriendRequestBody: Encodable {
    let toPublicId: String
    let shareUrl: String
    let isReverse: Bool
}

struct FriendRequestCreatedResponse: Decodable {
    let requestId: String
    let expiresAt: Int64
    let isReverse: Bool?
    let target: TargetSummary
    struct TargetSummary: Decodable {
        let publicId: String
        let displayName: String?
    }
}

struct FriendRequestInboxResponse: Decodable {
    let requests: [IncomingRequest]
    struct IncomingRequest: Decodable, Identifiable {
        let requestId: String
        let fromUserId: String
        let fromName: String?
        let fromPublicId: String?
        let isReverse: Bool?
        let createdAt: Int64
        let expiresAt: Int64
        var id: String { requestId }
    }
}

struct FriendRequestOutgoingResponse: Decodable {
    let requests: [OutgoingRequest]
    struct OutgoingRequest: Decodable, Identifiable {
        let requestId: String
        let toUserId: String
        let toName: String?
        let toPublicId: String?
        let isReverse: Bool?
        let createdAt: Int64
        let expiresAt: Int64
        var id: String { requestId }
    }
}

struct FriendRequestAcceptResponse: Decodable {
    let ok: Bool
    let shareUrl: String
    let fromUserId: String
}

struct ServerFriendsResponse: Decodable {
    let friends: [ServerFriendSummary]
}

struct ServerFriendSummary: Decodable, Identifiable {
    let userId: String
    let publicId: String?
    let displayName: String?
    var id: String { userId }
}

struct FriendStressResponse: Codable {
    let friends: [ServerFriendStress]
}

struct ServerFriendStress: Codable, Identifiable {
    let userId: String
    let publicId: String?
    let displayName: String
    let stressScore: Int
    let stressLevel: String
    let lastUpdated: Int64?
    let friendshipCreatedAt: Int64?
    let hasStress: Bool

    var id: String { userId }
}

struct SendCareEventBody: Encodable {
    let toUserId: String
    let type: String
    let message: String?
    let payload: [String: String]
    let replyToEventId: String?
}

struct MarkCareEventsReadBody: Encodable {
    let eventIds: [String]?
}

struct CareEventCreatedResponse: Decodable {
    let ok: Bool
    let mutedByRecipient: Bool?
    let event: ServerCareEvent
}

struct CareEventsReadResponse: Decodable {
    let ok: Bool
    let updated: Int
    let readAt: Int64
}

struct CareEventInboxResponse: Decodable {
    let events: [ServerCareEvent]
}

struct ServerCareEvent: Decodable, Identifiable {
    let eventId: String
    let type: String
    let message: String?
    let payload: [String: String]
    let fromUserId: String
    let fromPublicId: String?
    let fromName: String
    let toUserId: String?
    let toPublicId: String?
    let toName: String?
    let replyToEventId: String?
    let createdAt: Int64
    let readAt: Int64?

    var id: String { eventId }
}

// MARK: - Bottle models

struct CreateBottleBody: Encodable {
    let stressScore: Int?
    let stressLevel: String?
    let moodTag: String
    let message: String
    let anonymous: Bool
}

struct BottleReplyBody: Encodable {
    let message: String
}

struct BottleReportBody: Encodable {
    let reason: String
}

struct BottleCreatedResponse: Decodable {
    let ok: Bool
    let bottle: StressBottle
}

struct BottleListResponse: Decodable {
    let bottles: [StressBottle]
}

struct BottleReplyCreatedResponse: Decodable {
    let ok: Bool
    let reply: StressBottleReply
}

struct StressBottle: Codable, Identifiable, Hashable {
    let bottleId: String
    let authorUserId: String?
    let authorName: String
    let moodTag: String
    let stressScore: Int?
    let stressLevel: String?
    let message: String
    let anonymous: Bool
    let status: String
    let createdAt: Int64
    let expiresAt: Int64?
    let reply: StressBottleReply?

    var id: String { bottleId }

    var createdDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1000)
    }

    var formattedTime: String {
        let interval = Date().timeIntervalSince(createdDate)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}

struct StressBottleReply: Codable, Identifiable, Hashable {
    let replyId: String
    let fromUserId: String?
    let fromName: String
    let message: String
    let createdAt: Int64

    var id: String { replyId }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case transport
    case unauthorized
    case server(message: String, status: Int, code: String?)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .transport: return "网络异常,请稍后再试"
        case .unauthorized: return "请重新登录"
        case .server(let msg, _, _): return msg
        case .decode: return "服务器返回数据无法解析"
        }
    }

    /// server 返回的错误 code(用来识别 self_harm / blocked_term 等)
    var serverCode: String? {
        if case .server(_, _, let code) = self { return code }
        return nil
    }
}

private struct APIErrorBody: Decodable {
    let error: String
    let code: String?
}

// MARK: - Request / Response models

struct AuthRequest: Encodable {
    let idToken: String
    let displayName: String?
}

struct AuthResponse: Decodable {
    let sessionToken: String
    let user: APIUser
}

struct APIUser: Decodable {
    let userId: String
    let displayName: String?
    let publicId: String?
    let hasEmail: Bool
}

struct UserResponse: Decodable { let user: APIUser }

struct UpdateMeRequest: Encodable { let displayName: String }

struct UpdateStressSnapshotBody: Encodable {
    let score: Int
    let level: String
    let displayName: String
}

struct StressSnapshotResponse: Decodable {
    let ok: Bool
    let snapshot: ServerFriendStress
}

struct DeviceRequest: Encodable {
    let deviceId: String
    let apnsToken: String
}

struct OkResponse: Decodable { let ok: Bool }
struct EmptyRequest: Encodable {}

// MARK: - Phase 2 models

struct StressHistoryBody: Encodable {
    let score: Int
    let level: String
    let recordedAt: Int64
    let algorithmVersion: Int
}

struct StressHistoryEntry: Decodable, Identifiable, Hashable {
    let historyId: Int
    let score: Int
    let level: String
    let recordedAt: Int64
    let algorithmVersion: Int?
    var id: Int { historyId }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(recordedAt) / 1000) }
}

struct StressHistoryResponse: Decodable {
    let history: [StressHistoryEntry]
}

struct FriendStressHistoryResponse: Decodable {
    let shared: Bool
    let history: [StressHistoryEntry]
}

struct HRVSampleUpload: Encodable {
    let valueMs: Double
    let measuredAt: Int64
    let source: String?
}

struct HRVUploadBody: Encodable {
    let samples: [HRVSampleUpload]
}

struct HRVUploadResponse: Decodable {
    let ok: Bool
    let accepted: Int
}

struct HRVSampleEntry: Decodable, Identifiable, Hashable {
    let sampleId: Int
    let valueMs: Double
    let source: String?
    let measuredAt: Int64
    var id: Int { sampleId }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(measuredAt) / 1000) }
}

struct HRVHistoryResponse: Decodable {
    let samples: [HRVSampleEntry]
}

struct SessionUploadBody: Encodable {
    let type: String
    let sessionId: String
    let pattern: String?
    let minutes: Int
    let completedAt: Int64
}

struct SessionCreatedResponse: Decodable {
    let ok: Bool
    let sessionId: String
}

struct BreathingSessionEntry: Decodable, Identifiable, Hashable {
    let sessionId: String
    let pattern: String
    let minutes: Int
    let completedAt: Int64
    var id: String { sessionId }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(completedAt) / 1000) }
}

struct MeditationSessionEntry: Decodable, Identifiable, Hashable {
    let sessionId: String
    let minutes: Int
    let completedAt: Int64
    var id: String { sessionId }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(completedAt) / 1000) }
}

struct SessionsResponse: Decodable {
    let shared: Bool?
    let breathing: [BreathingSessionEntry]
    let meditation: [MeditationSessionEntry]
}

struct DailySummaryBody: Encodable {
    var date: String?       // server 端会从 query 拿,这里其实只用于 POST
    let stressAvg: Double?
    let stressMax: Int?
    let stressMin: Int?
    let stressHighMinutes: Int?
    let hrvAvg: Double?
    let breathingCount: Int?
    let breathingMinutes: Int?
    let meditationCount: Int?
    let meditationMinutes: Int?
}

struct DailySummaryEntry: Decodable, Identifiable, Hashable {
    let date: String
    let stressAvg: Double?
    let stressMax: Int?
    let stressMin: Int?
    let stressHighMinutes: Int?
    let hrvAvg: Double?
    let breathingCount: Int?
    let breathingMinutes: Int?
    let meditationCount: Int?
    let meditationMinutes: Int?
    let updatedAt: Int64?
    var id: String { date }
}

struct DailySummaryListResponse: Decodable {
    let summaries: [DailySummaryEntry]
}

struct FriendDailySummaryResponse: Decodable {
    let summaries: [DailySummaryEntry]
    let prefs: SharePrefs
}

struct SharePrefs: Decodable, Hashable {
    let shareStress: Bool
    let shareTraining: Bool
    let shareHRV: Bool
}

struct SharePrefsResponse: Decodable {
    let prefs: SharePrefs
}

struct SharePrefsUpdateBody: Encodable {
    let shareStress: Bool?
    let shareTraining: Bool?
    let shareHRV: Bool?
}

// MARK: - AnyEncodable helper

private struct AnyEncodable: Encodable {
    let wrapped: Encodable
    init(_ wrapped: Encodable) { self.wrapped = wrapped }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}
