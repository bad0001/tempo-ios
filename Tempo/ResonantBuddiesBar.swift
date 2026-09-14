//
//  ResonantBuddiesBar.swift
//  Tempo
//
//  HomeView 顶部紧凑卡 — 一眼看完密友当前状态.
//   - 头像横向滚动 + level dot
//   - 点头像 → 弹关怀面板(心跳 / 邀请呼吸 / 邀请冥想 / 写鼓励)
//   - 显示「今日共振时刻」(自动算:你和 Ta 今天都做了呼吸 / 都很平静等)
//

import SwiftUI
import SwiftData
import CloudKit
import TempoCore

/// ResonantBuddiesBar @Query cutoff:今日均值 + 简单对比,7 天够
private let buddiesBarCutoff: Date = Date.now.addingTimeInterval(-7 * 86400)

struct ResonantBuddiesBar: View {
    @State private var service = FriendsService.shared
    @Query(filter: #Predicate<StressEntry> { $0.timestamp > buddiesBarCutoff },
           sort: \StressEntry.timestamp, order: .reverse) private var allEntries: [StressEntry]

    var body: some View {
        if !service.friends.isEmpty {
            content
                .task { await TodayMindfulCache.shared.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let signal = latestUnreadCareSignal {
            unreadCareSignal(signal)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                header
                buddiesScroll
                if let line = todayResonantLine {
                    resonantTodayLine(line)
                }
            }
            .tempoCard(radius: 18, padding: 14)
        }
    }

    private struct CareSignal: Identifiable {
        let id: String
        let eventID: String
        let friend: Friend?
        let fromName: String
        let title: String
        let body: String
        let icon: String
        let color: Color
        let sentAt: Date
    }

    private var latestUnreadCareSignal: CareSignal? {
        var signals: [CareSignal] = []

        for encourage in service.encourages where encourage.isUnread(comparedWith: service.lastEncourageReadAt) {
            let friend = friendFor(serverUserId: encourage.fromUserId, fromName: encourage.fromName, zoneID: encourage.zoneID)
            if let friend, service.isMuted(friend) { continue }
            signals.append(CareSignal(
                id: "enc.\(encourage.id)",
                eventID: encourage.id,
                friend: friend,
                fromName: encourage.fromName,
                title: "给你发了鼓励",
                body: encourage.message,
                icon: "envelope.fill",
                color: Color.pink,
                sentAt: encourage.sentAt
            ))
        }

        for event in service.resonantEvents where event.isUnread(comparedWith: service.lastResonantEventReadAt) {
            let friend = friendFor(serverUserId: event.fromUserId, fromName: event.fromName, zoneID: event.zoneID)
            if let friend, service.isMuted(friend) { continue }
            signals.append(CareSignal(
                id: "evt.\(event.id)",
                eventID: event.id,
                friend: friend,
                fromName: event.fromName,
                title: event.type.label,
                body: ResonantEventMessage.notificationBody(type: event.type, payload: event.payload),
                icon: event.type.icon,
                color: iconColor(for: event.type),
                sentAt: event.sentAt
            ))
        }

        return signals.sorted { $0.sentAt > $1.sentAt }.first
    }

    private func friendFor(serverUserId: String?, fromName: String, zoneID: CKRecordZone.ID) -> Friend? {
        service.friends.first {
            $0.serverUserId == serverUserId
            || $0.zoneID == zoneID
            || $0.displayName == fromName
        }
    }

    private func iconColor(for type: ResonantEventType) -> Color {
        switch type {
        case .heartbeat: Color.pink
        case .breathingInvite: TempoTheme.breathing
        case .meditationInvite: TempoTheme.meditation
        case .sessionCompleted: TempoTheme.success
        }
    }

    private func unreadCareSignal(_ signal: CareSignal) -> some View {
        let friend = signal.friend
        let displayName = friend?.displayName ?? signal.fromName
        let statusText = friend.map(\.levelDisplay) ?? "新关怀"
        let color = friend.map(\.levelColor) ?? signal.color

        return Button {
            Task { await service.markCareEventsRead(eventIDs: [signal.eventID]) }
            var userInfo: [String: Any] = [
                "fromName": signal.fromName,
                "markCareRead": true,
                "eventID": signal.eventID
            ]
            if let friendID = friend?.id {
                userInfo["friendID"] = friendID
            }
            NotificationCenter.default.post(
                name: .tempoOpenCarePanel,
                object: nil,
                userInfo: userInfo
            )
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 5) {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(color.opacity(0.16))
                            .frame(width: 60, height: 60)
                        Text(String(displayName.prefix(1)))
                            .font(.system(size: 23, weight: .heavy))
                            .foregroundStyle(color)
                            .frame(width: 60, height: 60)
                        Circle()
                            .fill(signal.color)
                            .frame(width: 17, height: 17)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                    Text(displayName)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                        .lineLimit(1)
                        .frame(width: 74)
                    Text(statusText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: signal.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(signal.color)
                        Text(signal.title)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                        Spacer(minLength: 0)
                        Text("新")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.pink))
                    }
                    Text(signal.body)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                    Text("点开进入关怀面板")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [signal.color.opacity(0.16), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(signal.color.opacity(0.26), lineWidth: 1)
                    )
                    .shadow(color: signal.color.opacity(0.16), radius: 18, y: 8)
            )
        }
        .buttonStyle(.tempoPress(.medium))
        .accessibilityLabel("\(displayName) \(signal.title),\(signal.body)")
        .accessibilityHint("点击打开关怀面板并标记为已读")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pink)
            Text("密友状态")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Spacer()
            if service.unreadResonantEventsCount > 0 || service.unreadEncouragesCount > 0 {
                let n = service.unreadResonantEventsCount + service.unreadEncouragesCount
                Text("\(n) 条新动态")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.pink))
            }
        }
    }

    private var buddiesScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(service.friends) { friend in
                    buddyAvatar(friend)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func buddyAvatar(_ friend: Friend) -> some View {
        let muted = service.isMuted(friend)
        let color: Color = friend.levelColor
        let alerts = muted ? [] : service.activeAlerts(for: friend)
        return Button {
            NotificationCenter.default.post(
                name: .tempoOpenCarePanel,
                object: nil,
                userInfo: ["friendID": friend.id]
            )
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.18))
                            .frame(width: 56, height: 56)
                        Text(String(friend.displayName.prefix(1)))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(color)
                        Circle()
                            .stroke(color.opacity(0.4), lineWidth: 2)
                            .frame(width: 56, height: 56)
                    }
                    if let topAlert = alerts.first {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(
                                Circle().fill(topAlert.severity == .critical ? TempoTheme.danger : Color(hex: "F97316"))
                            )
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    } else if !muted {
                        Circle()
                            .fill(color)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                }
                Text(friend.displayName)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
                Text(friend.levelDisplay)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
            }
            .frame(width: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.tempoPress)
        .accessibilityLabel("\(friend.displayName),\(friend.levelDisplay)\(muted ? ",已静音提醒" : "")\(alerts.isEmpty ? "" : ",有 \(alerts.count) 条健康告警")")
        .accessibilityHint("点击打开关怀面板")
    }

    // MARK: - Today resonant line(自动算)

    private var todayResonantLine: String? {
        guard let firstFriend = service.friends.first(where: { !service.isMuted($0) }) else { return nil }
        let myToday = todayMyAvgStress
        let theirLevel = firstFriend.stressLevelRaw
        if myToday < 50 && (theirLevel == "calm" || theirLevel == "relaxed") {
            return "你和 \(firstFriend.displayName) 今天都很平静 ☮️"
        }
        if myToday >= 70 && (theirLevel == "high" || theirLevel == "extreme") {
            return "你和 \(firstFriend.displayName) 今天都有些紧张，可以问问 Ta 还好吗。"
        }
        if didMyBreathingToday {
            return "你今天给自己留了休息时间，也可以关心一下 \(firstFriend.displayName)。"
        }
        return nil
    }

    private var todayMyAvgStress: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayEntries = allEntries.filter { $0.timestamp >= today }
        guard !todayEntries.isEmpty else { return 0 }
        let sum = todayEntries.reduce(0) { $0 + $1.scoreValue }
        return sum / todayEntries.count
    }

    private var didMyBreathingToday: Bool {
        // 优先 SwiftData 的 stress entry 当起跑线:如果今天有训练过呼吸 / 冥想,
        // BreathingSession / MeditationSession 在完成时会写 HK mindfulSession + 更新这个时间戳。
        // 双写策略下任一信号 ≥1 都算今天做过。
        let last = UserDefaults.standard.double(forKey: "lastMindfulCompletedAt")
        if last > 0,
           Calendar.current.isDateInToday(Date(timeIntervalSince1970: last)) {
            return true
        }
        // Fallback:同步查 HK 今天的 mindful sessions 计数(只在 UserDefaults 没记到时)。
        // 这里用 cache 避免每次 view body 都打 HK 查询。
        return TodayMindfulCache.shared.didLogToday
    }

    private func resonantTodayLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(TempoTheme.accent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TempoTheme.accentSoft)
        )
    }
}
