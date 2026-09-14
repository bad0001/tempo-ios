//
//  FriendsListView.swift
//  Tempo
//
//  共振关怀 — 日常视图,只用来「看密友状态 + 一键发鼓励」.
//  所有管理操作(添加 / 解绑 / 静音 / 共享 toggle / 阈值 / 暂停)都搬到 ResonantSettingsView.
//
//  入口:
//   - 共振空间(首页)→ 共振关怀卡 → 这个 view
//   - 设置 → 共振设置 → ResonantSettingsView(管理)
//

import SwiftUI
import CloudKit
import TempoCore

struct FriendsListView: View {
    @State private var service = FriendsService.shared
    @State private var session = TempoSession.shared
    @State private var encourageTarget: Friend?
    @AppStorage("friends.guideCollapsed") private var guideCollapsed: Bool = false
    @State private var showSettings: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    statusBanner
                    if !session.isLoggedIn {
                        loginNudgeCard
                    } else {
                        usageGuideCard
                        incomingEncouragesCard
                        if service.friends.isEmpty {
                            emptyStateCard
                        } else {
                            friendsList
                        }
                    }
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("共振关怀")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TempoTheme.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showSettings) {
                ResonantSettingsView()
            }
            .sheet(item: $encourageTarget) { friend in
                EncourageSheet(friend: friend)
            }
            .task {
                await service.checkStatus()
                await service.loadEncourages()
                await service.loadFriendAlerts()
            }
            .refreshable {
                await service.refreshFriends()
                await service.loadEncourages()
                await service.loadFriendAlerts()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink, Color(hex: "8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                Image(systemName: "heart.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("共振关怀")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("和密友互看 stress · 一键发鼓励")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Tempo server sync state

    @ViewBuilder
    private var statusBanner: some View {
        TempoDataStateView(
            state: service.friendSyncState,
            loadingTitle: "正在同步密友状态",
            emptyTitle: "还没有密友",
            emptyDetail: "从共振设置发送邀请，接受后双方会同时出现在列表里。",
            cachedTitle: "正在显示离线密友状态",
            showsEmpty: false,
            onRetry: {
                Task {
                    await service.refreshFriends()
                    await service.loadEncourages()
                    await service.loadFriendAlerts()
                }
            }
        )
    }

    // MARK: - Login nudge

    private var loginNudgeCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink, Color(hex: "8B5CF6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 16)
            Text("还没启用共振关怀")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Text("请先到「设置 → 共振设置」用 Apple ID 登录,然后用对方的共振 ID 添加密友。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showSettings = true
            } label: {
                Text("打开共振设置")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(TempoTheme.buttonGradient))
            }
            .buttonStyle(.tempoPress)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .tempoCard(radius: 18, padding: 14)
    }

    // MARK: - Usage guide(可折叠)

    private var usageGuideCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    guideCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(TempoTheme.accent)
                    Text("怎么用?")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .rotationEffect(.degrees(guideCollapsed ? 0 : 180))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.tempoPress)
            if !guideCollapsed {
                VStack(alignment: .leading, spacing: 12) {
                    bulletRow("1", "在「设置 → 共振设置」获取你的共振 ID")
                    bulletRow("2", "把 ID 给对方,Ta 在自己 Tempo 里输入 → 发请求给你")
                    bulletRow("3", "你在「待处理请求」里接受 → 双方互看 stress + 收发鼓励")
                    Text("密友绑定、压力摘要和关怀通知通过 Tempo 服务同步；Apple 健康原始记录只保留在你的设备里。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .padding(.top, 4)
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }

    private func bulletRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color.pink).frame(width: 22, height: 22)
                Text(num)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Empty state

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink, Color(hex: "8B5CF6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 16)
            Text("还没绑定密友")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Text("到「设置 → 共振设置」用对方的共振 ID 发请求,接受后双方就能互相关怀。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { showSettings = true } label: {
                Text("打开共振设置")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(TempoTheme.accent))
            }
            .buttonStyle(.tempoPress)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .tempoCard(radius: 18, padding: 14)
    }

    // MARK: - Friends list(只读 + 鼓励)

    private var friendsList: some View {
        VStack(spacing: 10) {
            ForEach(service.friends) { friend in
                friendCard(friend)
            }
        }
    }

    private func friendCard(_ friend: Friend) -> some View {
        let muted = service.isMuted(friend)
        let displayColor: Color = muted ? TempoTheme.tertiaryText : friend.levelColor
        let alerts = muted ? [] : service.activeAlerts(for: friend)
        let topAlert = alerts.first
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(displayColor.opacity(muted ? 0.10 : 0.15))
                    .frame(width: 50, height: 50)
                Text(String(friend.displayName.prefix(1)))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(displayColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(friend.displayName)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    } else {
                        Circle()
                            .fill(displayColor)
                            .frame(width: 8, height: 8)
                        Text(LocalizedStringKey(friend.levelDisplay))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(displayColor)
                    }
                }
                if let alert = topAlert {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(LocalizedStringKey(alert.metric.label))
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            alert.severity == .critical ? TempoTheme.danger : Color(hex: "F97316")
                        )
                    )
                }
                HStack(spacing: 6) {
                    if muted {
                        Text("已静音")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    } else {
                        Text("压力 \(friend.stressScore)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TempoTheme.secondaryText)
                        Text("·")
                            .foregroundStyle(TempoTheme.tertiaryText)
                        Text(friend.formattedLastUpdated)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
            }
            Spacer()
            Button {
                NotificationCenter.default.post(
                    name: .tempoOpenCarePanel,
                    object: nil,
                    userInfo: ["friendID": friend.id]
                )
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                    Text("关怀")
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.pink))
            }
            .buttonStyle(.tempoPress)
        }
        .tempoCard(radius: 18, padding: 14)
    }

    // MARK: - Incoming encourages

    @ViewBuilder
    private var incomingEncouragesCard: some View {
        if !service.encourages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.pink)
                    Text("收到的鼓励")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if service.unreadEncouragesCount > 0 {
                        Text("\(service.unreadEncouragesCount)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.pink))
                    }
                    Spacer()
                    if service.unreadEncouragesCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                service.markAllEncouragesRead()
                            }
                        } label: {
                            Text("全部标已读")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(TempoTheme.accent)
                        }
                        .buttonStyle(.tempoPress)
                    }
                }
                VStack(spacing: 0) {
                    let displayed = Array(service.encourages.prefix(5))
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { idx, e in
                        encourageRow(e)
                        if idx < displayed.count - 1 {
                            Rectangle()
                                .fill(TempoTheme.tertiaryText.opacity(0.15))
                                .frame(height: 0.5)
                                .padding(.leading, 18)
                        }
                    }
                    if service.encourages.count > 5 {
                        Text("还有 \(service.encourages.count - 5) 条")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                            .padding(.top, 8)
                    }
                }
            }
            .tempoCard(radius: 18, padding: 14)
        }
    }

    private func encourageRow(_ e: Encourage) -> some View {
        let isUnread = e.isUnread(comparedWith: service.lastEncourageReadAt)
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isUnread ? Color.pink : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(e.fromName)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Spacer()
                    Text(e.formattedTime)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Text(e.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button(role: .destructive) {
                Task { await service.deleteEncourage(e) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - Care Panel Sheet(关怀面板 — 一站式互助)

struct EncourageSheet: View {
    let friend: Friend
    @Environment(\.dismiss) private var dismiss
    @State private var customMessage: String = ""
    @State private var sending = false
    @State private var sent: SentKind?
    @State private var sendError: String?
    @State private var showBreathingPicker: Bool = false
    @State private var showMeditationPicker: Bool = false
    @State private var heartbeatPulses: Int = 0

    enum SentKind { case heartbeat, encourage, breathingInvite, meditationInvite }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    quickActionsSection
                    customEncourageSection
                    presetEncouragesSection
                    if let sent {
                        sentToast(sent)
                    }
                    if let err = sendError {
                        Text(err)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TempoTheme.danger)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 30)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("关怀")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
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
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(friend.levelColor.opacity(0.15))
                    .frame(width: 60, height: 60)
                Text(String(friend.displayName.prefix(1)))
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(friend.levelColor)
                ForEach(0..<heartbeatPulses, id: \.self) { _ in
                    Circle()
                        .stroke(Color.pink, lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .scaleEffect(1.6)
                        .opacity(0)
                        .animation(.easeOut(duration: 0.8), value: heartbeatPulses)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("关怀 \(friend.displayName)")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("Ta 现在 \(friend.levelDisplay) · 压力 \(friend.stressScore)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
        }
    }

    // MARK: - Quick actions(3 大快捷)

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷关怀")
                .font(.system(size: 12, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(spacing: 10) {
                quickButton(
                    title: "心跳",
                    subtitle: "1 秒到达",
                    icon: "heart.circle.fill",
                    color: Color.pink
                ) {
                    Task { await sendHeartbeat() }
                }
                quickButton(
                    title: "邀请呼吸",
                    subtitle: "推送一段",
                    icon: "wind.circle.fill",
                    color: Color(hex: "8B5CF6")
                ) {
                    showBreathingPicker = true
                }
                quickButton(
                    title: "邀请冥想",
                    subtitle: "推送一段",
                    icon: "leaf.circle.fill",
                    color: Color(hex: "10B981")
                ) {
                    showMeditationPicker = true
                }
            }
        }
    }

    private func quickButton(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(color)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.tempoPress)
        .disabled(sending)
    }

    // MARK: - Custom encourage

    private var customEncourageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("写一句话")
                .font(.system(size: 12, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(spacing: 10) {
                TextField("发点什么暖心的话", text: $customMessage)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                Button {
                    Task { await sendEncourage(message: customMessage) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.pink))
                }
                .buttonStyle(.tempoPress)
                .disabled(customMessage.isEmpty || sending)
            }
        }
    }

    // MARK: - Preset encourages

    private var presetEncouragesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常用鼓励")
                .font(.system(size: 12, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            VStack(spacing: 8) {
                ForEach(EncouragePresets.all, id: \.self) { msg in
                    Button {
                        Task { await sendEncourage(message: msg) }
                    } label: {
                        HStack {
                            Text(msg)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(TempoTheme.primaryText)
                            Spacer()
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.pink)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tempoPress)
                    .disabled(sending)
                }
            }
        }
    }

    private func sentToast(_ kind: SentKind) -> some View {
        let label: String = {
            switch kind {
            case .heartbeat: "心跳已发送 ❤️"
            case .encourage: "鼓励已发送 ✨"
            case .breathingInvite: "呼吸邀请已发送 🌬️"
            case .meditationInvite: "冥想邀请已发送 🧘"
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(TempoTheme.success)
            Text(LocalizedStringKey(label))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(TempoTheme.success)
        }
    }

    // MARK: - Actions

    private func sendHeartbeat() async {
        sending = true
        sendError = nil
        defer { sending = false }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
        withAnimation { heartbeatPulses += 1 }
        do {
            try await FriendsService.shared.sendResonantEvent(to: friend, type: .heartbeat)
            withAnimation { sent = .heartbeat }
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            sendError = "心跳发送失败: \(error.localizedDescription)"
        }
    }

    private func sendBreathingInvite(minutes: Int) async {
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            try await FriendsService.shared.sendResonantEvent(
                to: friend,
                type: .breathingInvite,
                payload: ["minutes": "\(minutes)"]
            )
            withAnimation { sent = .breathingInvite }
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            sendError = "邀请发送失败: \(error.localizedDescription)"
        }
    }

    private func sendMeditationInvite(minutes: Int) async {
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            try await FriendsService.shared.sendResonantEvent(
                to: friend,
                type: .meditationInvite,
                payload: ["minutes": "\(minutes)"]
            )
            withAnimation { sent = .meditationInvite }
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            sendError = "邀请发送失败: \(error.localizedDescription)"
        }
    }

    private func sendEncourage(message: String) async {
        guard !message.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            try await FriendsService.shared.sendEncourage(to: friend, message: message)
            withAnimation { sent = .encourage }
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            sendError = "发送失败: \(error.localizedDescription)"
        }
    }
}
