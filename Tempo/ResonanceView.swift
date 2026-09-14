//
//  ResonanceView.swift
//  Tempo
//
//  共振主入口:熟人关怀是主任务,回声海岸是低频补充。
//

import SwiftUI

struct ResonanceView: View {
    @Binding var openEcho: EchoOpenRequest?

    @State private var service = FriendsService.shared
    @State private var session = TempoSession.shared
    @State private var showEcho = false
    @State private var showSettings = false
    @State private var activeEchoRequest: EchoOpenRequest?
    @State private var isRefreshing = false

    private var unreadCount: Int {
        service.unreadEncouragesCount + service.unreadResonantEventsCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    TempoDataStateView(
                        state: service.friendSyncState,
                        loadingTitle: "正在同步共振关系",
                        emptyTitle: "还没有密友连接",
                        emptyDetail: "添加密友后，双方的压力摘要和关怀会出现在这里。",
                        cachedTitle: "正在显示离线关系状态",
                        showsEmpty: false,
                        onRetry: { Task { await refresh() } }
                    )
                    if service.friends.isEmpty {
                        carePrimaryCard
                    } else {
                        ResonantBuddiesBar()
                        carePrimaryCard
                    }

                    echoCoastCard
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .refreshable { await refresh() }
            .task { await refresh() }
            .onAppear { openEchoIfNeeded() }
            .onChange(of: openEcho) { _, _ in openEchoIfNeeded() }
            .fullScreenCover(isPresented: $showEcho, onDismiss: {
                activeEchoRequest = nil
            }) {
                EchoFullScreenView(request: activeEchoRequest)
            }
            .sheet(isPresented: $showSettings) {
                ResonantSettingsView()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("共振")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("看见彼此的状态")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TempoTheme.secondaryText)
            }
            Spacer(minLength: 12)
            Button {
                openFriendSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TempoTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.tempoPress)
            .accessibilityLabel("共振设置")
        }
        .padding(.top, 4)
    }

    private var carePrimaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: service.friends.isEmpty ? "person.badge.plus" : "heart.text.square.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(TempoTheme.care)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(service.friends.isEmpty ? "添加密友" : "关怀动态"))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(LocalizedStringKey(careSubtitle))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if unreadCount > 0 {
                    Text("\(unreadCount) 条新关怀")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(TempoTheme.care))
                }
            }

            Button {
                if service.friends.isEmpty {
                    openFriendSettings()
                } else {
                    NotificationCenter.default.post(
                        name: .tempoOpenCarePanel,
                        object: nil,
                        userInfo: [:]
                    )
                }
            } label: {
                Label(
                    service.friends.isEmpty ? (session.isLoggedIn ? "添加密友" : "登录并添加密友") : "打开关怀",
                    systemImage: service.friends.isEmpty ? "person.badge.plus.fill" : "heart.text.square.fill"
                )
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(service.friends.isEmpty ? TempoTheme.accent : TempoTheme.care)
                )
            }
            .buttonStyle(.tempoPress(.medium))
        }
        .tempoCard(radius: 24, padding: 18)
    }

    private var careSubtitle: String {
        if service.friends.isEmpty {
            return "和重要的人共享压力状态。"
        }
        if unreadCount > 0 {
            return "有 \(unreadCount) 条关怀等你回应。"
        }
        return "需要时，发一句话让对方知道你在。"
    }

    private var echoCoastCard: some View {
        Button {
            activeEchoRequest = nil
            showEcho = true
        } label: {
            ZStack(alignment: .leading) {
                Image("EchoCoastBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 156)
                    .clipped()

                LinearGradient(
                    colors: [.white.opacity(0.92), .white.opacity(0.50), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("回声海岸")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: "164E63"))
                    Text("把这一刻放进海里。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "155E75").opacity(0.82))
                        .frame(maxWidth: 230, alignment: .leading)
                    HStack(spacing: 6) {
                        Text("去海边")
                            .font(.system(size: 12, weight: .heavy))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color(hex: "0E7490"))
                    .padding(.top, 3)
                }
                .padding(20)
            }
            .frame(height: 156)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: Color(hex: "0E7490").opacity(0.10), radius: 18, y: 8)
        }
        .buttonStyle(.tempoPress(.light))
        .frame(height: 156)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityLabel("回声海岸")
        .accessibilityHint("进入压力漂流瓶页面")
    }

    private var principleCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TempoTheme.success)
            Text("熟人关怀优先,陌生人回声保持克制。回声只允许一次回复,不会变成长时间聊天。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TempoTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func compactMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                if !unit.isEmpty {
                    Text(LocalizedStringKey(unit))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(TempoTheme.accentSoft.opacity(0.68))
        )
    }

    private func openEchoIfNeeded() {
        guard let request = openEcho else { return }
        activeEchoRequest = request
        showEcho = true
        openEcho = nil
    }

    private func openFriendSettings() {
        // 本地直接呈现，避免再绕 NotificationCenter；同时让用户这次点击覆盖陈旧回声请求。
        openEcho = nil
        activeEchoRequest = nil
        showEcho = false
        BottleDeepLinkStore.clear()
        showSettings = true
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await service.refreshFriends()
        await service.loadEncourages()
        await service.loadResonantEvents()
        await service.refreshPendingFriendRequests()
    }
}

private struct EchoFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let request: EchoOpenRequest?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                TempoTheme.background.ignoresSafeArea()
                DriftBottleView(
                    initialBottleID: request?.bottleID,
                    initialReplyID: request?.replyID
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(x: dragOffset)
                .shadow(
                    color: .black.opacity(dragOffset > 0 ? 0.12 : 0),
                    radius: 24,
                    x: -10
                )
                .contentShape(Rectangle())
                .simultaneousGesture(edgeDismissGesture(screenWidth: proxy.size.width))

                TopScrollFadeLayer()
            }
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    private func edgeDismissGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard value.startLocation.x <= 34,
                      value.translation.width > 0,
                      abs(value.translation.height) < 80 else { return }
                dragOffset = min(screenWidth, value.translation.width)
            }
            .onEnded { value in
                let shouldDismiss = value.startLocation.x <= 34
                    && value.translation.width > max(92, screenWidth * 0.24)
                    && abs(value.translation.height) < 110
                if shouldDismiss {
                    withAnimation(.easeOut(duration: 0.18)) {
                        dragOffset = screenWidth
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        dismiss()
                    }
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }
}

#Preview {
    ResonanceView(openEcho: .constant(nil))
}
