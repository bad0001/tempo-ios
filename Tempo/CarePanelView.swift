//
//  CarePanelView.swift
//  Tempo
//
//  关怀面板 — Tempo 的核心情感页.
//   - 顶部:大 hero 卡(头像光晕 + 大压力分 + 关系标签),横向滑动切换密友
//   - 中部:对当前密友的关怀操作(心跳 / 邀请呼吸 / 邀请冥想 / 写一句话)
//   - 下部:收到的关怀(模块) + 自我关怀(模块)
//   - 没密友时:空状态 hero 引导用户:看到 demo 卡 → 加密友才有真实体验
//

import SwiftUI
import CloudKit
import UserNotifications
import TempoCore
#if canImport(UIKit)
import UIKit
#endif

struct CarePanelView: View {
    var initialFriend: Friend? = nil
    var initialFriendID: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var service = FriendsService.shared
    @State private var session = TempoSession.shared

    @State private var selectedFriendID: String? = nil
    @State private var customMessage: String = ""
    @State private var activeSendAction: CareSendAction?
    @State private var failedSendAction: CareSendAction?
    @State private var sentToast: SentKind?
    @State private var sendError: String?
    @State private var showBreathingPicker: Bool = false
    @State private var showMeditationPicker: Bool = false
    @State private var showCheckLaterPicker: Bool = false
    @State private var replyTarget: CareInteraction?

    @State private var relationshipTarget: Friend?
    @State private var showSelfBreathing: Bool = false
    @State private var showSelfMeditation: Bool = false

    private let heroPagerHeight: CGFloat = 532

    enum SentKind { case heartbeat, encourage, breathingInvite, meditationInvite, checkLater }

    private enum CareSendAction: Equatable {
        case heartbeat(friendID: String)
        case breathingInvite(friendID: String, minutes: Int)
        case meditationInvite(friendID: String, minutes: Int)
        case encourage(friendID: String, message: String)

        var button: CarePanelSendButton {
            switch self {
            case .heartbeat: .presence
            case .breathingInvite: .breathingInvite
            case .meditationInvite: .meditationInvite
            case .encourage: .encourage
            }
        }

        var sentKind: SentKind {
            switch self {
            case .heartbeat: .heartbeat
            case .breathingInvite: .breathingInvite
            case .meditationInvite: .meditationInvite
            case .encourage: .encourage
            }
        }

        var friendID: String {
            switch self {
            case .heartbeat(let friendID),
                 .breathingInvite(let friendID, _),
                 .meditationInvite(let friendID, _),
                 .encourage(let friendID, _):
                friendID
            }
        }

        var sendingTitle: String {
            switch self {
            case .heartbeat: "正在发送「我在」"
            case .breathingInvite(_, let minutes): "正在发送 \(minutes) 分钟呼吸邀请"
            case .meditationInvite(_, let minutes): "正在发送 \(minutes) 分钟冥想邀请"
            case .encourage: "正在发送鼓励"
            }
        }

        var icon: String {
            switch self {
            case .heartbeat: "heart.circle.fill"
            case .breathingInvite: "wind.circle.fill"
            case .meditationInvite: "leaf.circle.fill"
            case .encourage: "envelope.fill"
            }
        }

        var color: Color {
            switch self {
            case .heartbeat: .pink
            case .breathingInvite: TempoTheme.breathing
            case .meditationInvite: TempoTheme.meditation
            case .encourage: TempoTheme.alert
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    titleHeader
                    heroPager
                    if !service.friends.isEmpty, let friend = currentFriend {
                        CarePanelActionCard(
                            friend: friend,
                            displayName: displayNameWithRelationship(friend),
                            isMuted: service.isMuted(friend),
                            customMessage: $customMessage,
                            activeButton: activeSendAction?.button,
                            onHeartbeat: {
                                Task { await performSend(.heartbeat(friendID: friend.id)) }
                            },
                            onCheckLater: { showCheckLaterPicker = true },
                            onBreathingInvite: { showBreathingPicker = true },
                            onMeditationInvite: { showMeditationPicker = true },
                            onSendEncourage: { message in
                                Task {
                                    await performSend(.encourage(friendID: friend.id, message: message))
                                }
                            }
                        )
                        if let status = sendStatusView {
                            status
                        }
                    }
                    if let friend = currentFriend {
                        CarePanelTimelineCard(
                            friendName: displayNameWithRelationship(friend),
                            items: timelineItems,
                            isRefreshing: service.isCareTimelineRefreshing,
                            onReply: { eventID in
                                replyTarget = service.careTimeline.first { $0.eventId == eventID }
                            }
                        )
                    }
                    CarePanelSelfCareCard(
                        onBreathing: { showSelfBreathing = true },
                        onMeditation: { showSelfMeditation = true }
                    )
                    if let toast = sentToast {
                        CarePanelSentToastView(kind: toast).padding(.top, 4)
                    }
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)   // 键盘上滑收起,避免外层 scroll 自动跳到 TextField 造成 jitter
            .scrollBounceBehavior(.basedOnSize)
            .background(TempoTheme.background)
            .navigationTitle("关怀")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                    .buttonStyle(.tempoPress)
                    .accessibilityLabel("关闭关怀面板")
                }
            }
            .task {
                if selectedFriendID == nil {
                    selectedFriendID = initialFriendID ?? initialFriend?.id ?? service.friends.first?.id
                }
                if selectedFriendID == nil {
                    selectedFriendID = service.friends.first?.id
                }
                async let timeline: Void = loadAndViewCurrentTimeline()
                async let encourages: Void = service.loadEncourages()
                async let events: Void = service.loadResonantEvents()
                async let alerts: Void = service.loadFriendAlerts()
                _ = await (timeline, encourages, events, alerts)
            }
            .refreshable {
                await service.refreshFriends()
                await service.loadEncourages()
                await service.loadResonantEvents()
                await loadAndViewCurrentTimeline()
            }
            .sheet(isPresented: $showSelfBreathing) {
                BreathingSessionView(pattern: .resonant)
            }
            .sheet(isPresented: $showSelfMeditation) {
                MeditationFlow()
            }
            .sheet(item: $relationshipTarget) { friend in
                RelationshipPickerSheet(friend: friend)
            }
            .sheet(item: $replyTarget) { interaction in
                if let friend = currentFriend {
                    CareReplySheet(
                        friendName: displayNameWithRelationship(friend),
                        originalBody: interaction.displayBody,
                        onSend: { message in
                            try await service.replyToCareEvent(interaction, for: friend, message: message)
                            await service.loadCareTimeline(for: friend)
                        }
                    )
                }
            }
            .onChange(of: selectedFriendID) { oldValue, newValue in
                guard oldValue != newValue else { return }
                Task { await loadAndViewCurrentTimeline() }
            }
            .confirmationDialog("邀请 Ta 呼吸多久?", isPresented: $showBreathingPicker, titleVisibility: .visible) {
                Button("3 分钟") { Task { await sendBreathingInvite(minutes: 3) } }
                Button("5 分钟") { Task { await sendBreathingInvite(minutes: 5) } }
                Button("10 分钟") { Task { await sendBreathingInvite(minutes: 10) } }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("邀请 Ta 冥想多久?", isPresented: $showMeditationPicker, titleVisibility: .visible) {
                Button("5 分钟") { Task { await sendMeditationInvite(minutes: 5) } }
                Button("10 分钟") { Task { await sendMeditationInvite(minutes: 10) } }
                Button("15 分钟") { Task { await sendMeditationInvite(minutes: 15) } }
                Button("20 分钟") { Task { await sendMeditationInvite(minutes: 20) } }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("多久后提醒你回看?", isPresented: $showCheckLaterPicker, titleVisibility: .visible) {
                Button("30 分钟后") { Task { await scheduleCareFollowUp(minutes: 30) } }
                Button("1 小时后") { Task { await scheduleCareFollowUp(minutes: 60) } }
                Button("2 小时后") { Task { await scheduleCareFollowUp(minutes: 120) } }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var currentFriend: Friend? {
        guard let id = selectedFriendID else { return service.friends.first }
        return service.friends.first { $0.id == id }
    }

    /// 关怀面板自己也是 sheet,直接 .sheet(showResonantSettings) 会触发"only one sheet at a time"警告。
    /// 改成:先 dismiss 当前面板,稍后通知 ContentView 在 root 层弹共振设置 —— 同一时刻只有一个 sheet。
    private func requestOpenResonantSettings() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .tempoOpenResonantSettings, object: nil, userInfo: [:])
        }
    }

    // MARK: - Title

    private var titleHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink, TempoTheme.breathing],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("让重要的人知道你在")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                if !service.friends.isEmpty {
                    Text("和 \(service.friends.count) 位密友保持联系")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                } else {
                    Text("添加密友后，彼此的状态会出现在这里")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                }
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Hero pager(横向滑动切换密友)

    @ViewBuilder
    private var heroPager: some View {
        if service.friends.isEmpty {
            FriendPlaceholderHero(addFriendAction: requestOpenResonantSettings)
                .frame(height: heroPagerHeight)
        } else {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(service.friends) { friend in
                            FriendHeroCard(
                                friend: friend,
                                relationship: service.relationship(for: friend),
                                isMuted: service.isMuted(friend),
                                activeAlertCount: service.activeAlerts(for: friend).count,
                                onEditRelationship: { relationshipTarget = friend }
                            )
                            .frame(width: proxy.size.width, height: heroPagerHeight, alignment: .top)
                            .id(friend.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedFriendID)
            }
            .frame(height: heroPagerHeight)

            // 自定义 page indicator
            if service.friends.count > 1 {
                HStack(spacing: 6) {
                    ForEach(service.friends) { friend in
                        Capsule()
                            .fill(friend.id == selectedFriendID ? TempoTheme.accent : TempoTheme.tertiaryText.opacity(0.3))
                            .frame(width: friend.id == selectedFriendID ? 18 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: selectedFriendID)
                    }
                }
            }
        }
    }

    private func displayNameWithRelationship(_ friend: Friend) -> String {
        if let rel = service.relationship(for: friend), !rel.isEmpty {
            return rel
        }
        return friend.displayName
    }

    private var timelineItems: [CarePanelTimelineItem] {
        service.careTimeline.map { interaction in
            let color: Color
            if interaction.typeRawValue == "encourage" {
                color = .pink
            } else if let type = interaction.eventType {
                color = iconColor(for: type)
            } else {
                color = TempoTheme.care
            }
            return CarePanelTimelineItem(
                id: interaction.eventId,
                icon: interaction.icon,
                iconColor: color,
                title: interaction.isOutgoing ? "你发给 \(currentFriend?.displayName ?? "密友")" : "\(interaction.fromName) 发给你",
                body: interaction.displayBody,
                timeText: interaction.formattedTime,
                statusText: interaction.readAt == nil ? "已发送" : "已查看",
                isOutgoing: interaction.isOutgoing,
                isUnread: !interaction.isOutgoing && interaction.readAt == nil,
                isReply: interaction.replyToEventId != nil,
                canReply: !interaction.isOutgoing,
                trendSummary: trendSummary(for: interaction)
            )
        }
    }

    private func trendSummary(for interaction: CareInteraction) -> CarePanelTrendSummary? {
        guard interaction.typeRawValue == "trend_summary" else { return nil }
        let payload = interaction.payload
        return CarePanelTrendSummary(
            range: payload["range"] ?? "近期",
            average: Int(payload["average"] ?? "") ?? 0,
            peak: Int(payload["peak"] ?? "") ?? 0,
            highStressMinutes: Int(payload["highStressMinutes"] ?? "") ?? 0,
            stressLoad: Int(payload["stressLoad"] ?? "") ?? 0,
            confidence: Int(payload["confidence"] ?? "") ?? 0,
            dominant: payload["dominant"] ?? "未知",
            hrvText: payload["hrvText"] ?? "HRV 暂无足够数据",
            episodeCount: Int(payload["episodeCount"] ?? "") ?? 0,
            calmPercent: Int(payload["calmPercent"] ?? "") ?? 0,
            mildPercent: Int(payload["mildPercent"] ?? "") ?? 0,
            highPercent: Int(payload["highPercent"] ?? "") ?? 0,
            trendPercent: Int(payload["trendPercent"] ?? ""),
            peakLabel: payload["peakLabel"] ?? ""
        )
    }

    private func iconColor(for type: ResonantEventType) -> Color {
        switch type {
        case .heartbeat: .pink
        case .breathingInvite: TempoTheme.breathing
        case .meditationInvite: TempoTheme.meditation
        case .sessionCompleted: TempoTheme.success
        }
    }

    private func loadAndViewCurrentTimeline() async {
        guard let friend = currentFriend else {
            service.careTimeline = []
            return
        }
        await service.loadCareTimeline(for: friend)
        let unreadIDs = service.careTimeline
            .filter { !$0.isOutgoing && $0.readAt == nil }
            .map(\.eventId)
        await service.markCareEventsRead(eventIDs: unreadIDs)
    }

    private var sendStatusView: CarePanelSendStatusView? {
        if let action = activeSendAction {
            return CarePanelSendStatusView(
                icon: action.icon,
                color: action.color,
                title: action.sendingTitle,
                message: "正在通过 Tempo 后端发送给密友",
                isLoading: true,
                onRetry: nil,
                onDismiss: nil
            )
        } else if failedSendAction != nil {
            return CarePanelSendStatusView(
                icon: "exclamationmark.triangle.fill",
                color: TempoTheme.danger,
                title: "没发出去",
                message: sendError,
                isLoading: false,
                onRetry: {
                    Task { await retryFailedSend() }
                },
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        failedSendAction = nil
                        sendError = nil
                    }
                }
            )
        }
        return nil
    }

    // MARK: - Actions

    private func performSend(_ action: CareSendAction) async {
        guard activeSendAction == nil else { return }
        activeSendAction = action
        sendError = nil
        failedSendAction = nil
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: hapticStyle(for: action.button)).impactOccurred()
        #endif
        defer { activeSendAction = nil }

        do {
            try await send(action)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            if case .encourage = action {
                customMessage = ""
            }
            withAnimation {
                sentToast = action.sentKind
            }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { sentToast = nil }
        } catch {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            withAnimation(.easeInOut(duration: 0.16)) {
                failedSendAction = action
                sendError = friendlyError(error)
            }
        }
    }

    private func sendBreathingInvite(minutes: Int) async {
        guard let friend = currentFriend else { return }
        await performSend(.breathingInvite(friendID: friend.id, minutes: minutes))
    }

    private func sendMeditationInvite(minutes: Int) async {
        guard let friend = currentFriend else { return }
        await performSend(.meditationInvite(friendID: friend.id, minutes: minutes))
    }

    private func retryFailedSend() async {
        guard let failedSendAction else { return }
        await performSend(failedSendAction)
    }

    private func scheduleCareFollowUp(minutes: Int) async {
        guard let friend = currentFriend else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        do {
            try await NotificationManager.shared.scheduleCareFollowUp(
                friendName: friend.displayName,
                minutes: minutes
            )
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            withAnimation {
                sentToast = .checkLater
            }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { sentToast = nil }
        } catch {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            withAnimation(.easeInOut(duration: 0.16)) {
                sendError = "提醒设置失败:\(error.localizedDescription)"
            }
        }
    }

    private func send(_ action: CareSendAction) async throws {
        guard let friend = service.friends.first(where: { $0.id == action.friendID }) else {
            throw FriendError.serverIdentityMissing
        }
        switch action {
        case .heartbeat:
            try await service.sendResonantEvent(to: friend, type: .heartbeat)
        case .breathingInvite(_, let minutes):
            try await service.sendResonantEvent(
                to: friend,
                type: .breathingInvite,
                payload: ["minutes": "\(minutes)"]
            )
        case .meditationInvite(_, let minutes):
            try await service.sendResonantEvent(
                to: friend,
                type: .meditationInvite,
                payload: ["minutes": "\(minutes)"]
            )
        case .encourage(_, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            try await service.sendEncourage(to: friend, message: trimmed)
        }
    }

    #if canImport(UIKit)
    private func hapticStyle(for button: CarePanelSendButton) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch button {
        case .presence: .heavy
        case .breathingInvite, .meditationInvite: .medium
        case .encourage: .light
        }
    }
    #endif

    /// 把网络 / 旧 CloudKit 兜底错误转成用户能懂的文案。
    private func friendlyError(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:
                return "登录已过期,请到共振设置重新登录"
            case .transport:
                return "网络异常,稍后再试"
            case .server(let message, _, _):
                return message
            case .decode:
                return "服务器返回异常,稍后再试"
            }
        }
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                return "请先登录 iCloud:设置 → Apple ID → iCloud"
            case .permissionFailure:
                return "权限未生效:请双方都重新进入「关怀面板」让 share 权限刷新,或重启 app 再试"
            case .networkUnavailable, .networkFailure:
                return "网络不稳,稍后再试"
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud 服务器繁忙,稍后再试"
            case .serverRejectedRequest, .serverResponseLost:
                return "iCloud 服务器拒绝,稍后再试"
            case .quotaExceeded:
                return "iCloud 容量不足,清理后再试"
            default:
                break
            }
        }
        let desc = error.localizedDescription
        let lower = desc.lowercased()
        if lower.contains("unauthorized") || desc.contains("登录") {
            return "登录已过期,请到共振设置重新登录"
        }
        if lower.contains("not permitted") || lower.contains("create operation") || desc.contains("权限") {
            return "权限未生效,请双方都重新打开 Tempo 再试"
        }
        if lower.contains("network") || lower.contains("internet") || desc.contains("网络") {
            return "网络不稳,稍后再试"
        }
        if lower.contains("rejected") || desc.contains("拒绝") {
            return "服务器拒绝,稍后再试"
        }
        return "发送失败:\(desc)"
    }
}
