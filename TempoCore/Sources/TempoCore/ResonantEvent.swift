//
//  ResonantEvent.swift
//  TempoCore
//
//  共振事件 — 密友之间的异步互助信号.
//  替代过去的 P2P 同步呼吸/冥想(那种"必须同时在场"的高门槛设计).
//
//  事件类型:
//   - heartbeat:一次心跳关怀(瞬时,长按友卡片即可发)
//   - breathingInvite:邀请对方做呼吸训练(payload: { mode: ".coherent" | ".box" | "478", minutes: Int })
//   - meditationInvite:邀请对方做冥想(payload: { minutes: Int })
//   - sessionCompleted:被邀请者完成训练后的回执(payload: { kind: "breathing" | "meditation", minutes: Int })
//

import Foundation

public enum ResonantEventType: String, Codable, CaseIterable, Sendable {
    case heartbeat
    case breathingInvite = "breathing_invite"
    case meditationInvite = "meditation_invite"
    case sessionCompleted = "session_completed"

    public var label: String {
        switch self {
        case .heartbeat: "心跳"
        case .breathingInvite: "邀请呼吸"
        case .meditationInvite: "邀请冥想"
        case .sessionCompleted: "训练完成"
        }
    }

    public var icon: String {
        switch self {
        case .heartbeat: "heart.circle.fill"
        case .breathingInvite: "wind.circle.fill"
        case .meditationInvite: "leaf.circle.fill"
        case .sessionCompleted: "checkmark.seal.fill"
        }
    }
}

/// 推送给接收方的本地通知文案(标题 + 正文)
public enum ResonantEventMessage {
    public static func notificationTitle(type: ResonantEventType, fromName: String) -> String {
        switch type {
        case .heartbeat: "\(fromName) 给你发了一次心跳 ❤️"
        case .breathingInvite: "\(fromName) 想邀你呼吸"
        case .meditationInvite: "\(fromName) 想邀你冥想"
        case .sessionCompleted: "\(fromName) 跟你完成了训练 ✨"
        }
    }

    public static func notificationBody(type: ResonantEventType, payload: [String: String]) -> String {
        switch type {
        case .heartbeat:
            return "我想你啦"
        case .breathingInvite:
            let minutes = payload["minutes"] ?? "5"
            return "试一下 \(minutes) 分钟呼吸,跟 Ta 一起放松"
        case .meditationInvite:
            let minutes = payload["minutes"] ?? "10"
            return "坐 \(minutes) 分钟,跟 Ta 一起静一下"
        case .sessionCompleted:
            let kind = payload["kind"] == "meditation" ? "冥想" : "呼吸"
            let minutes = payload["minutes"] ?? "?"
            return "Ta 完成了你建议的 \(minutes) 分钟\(kind)"
        }
    }
}
