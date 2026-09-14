//
//  ContentView.swift
//  Tempo
//

import Foundation
import SwiftUI
import TempoCore

struct EchoOpenRequest: Identifiable, Equatable {
    let id = UUID()
    let bottleID: String?
    let replyID: String?

    static var generic: EchoOpenRequest {
        EchoOpenRequest(bottleID: nil, replyID: nil)
    }
}

/// 通知点击可能早于 ContentView 完成订阅,因此同时持久化一次性跳转。
enum BottleDeepLinkStore {
    private static let bottleKey = "bottles.pendingOpen.bottleId"
    private static let replyKey = "bottles.pendingOpen.replyId"

    static func save(bottleID: String?, replyID: String?) {
        guard let bottleID, !bottleID.isEmpty else { return }
        UserDefaults.standard.set(bottleID, forKey: bottleKey)
        if let replyID, !replyID.isEmpty {
            UserDefaults.standard.set(replyID, forKey: replyKey)
        } else {
            UserDefaults.standard.removeObject(forKey: replyKey)
        }
    }

    static func request(from userInfo: [AnyHashable: Any]?) -> EchoOpenRequest? {
        guard let bottleID = userInfo?["bottleId"] as? String, !bottleID.isEmpty else { return nil }
        return EchoOpenRequest(
            bottleID: bottleID,
            replyID: userInfo?["replyId"] as? String
        )
    }

    static func consume() -> EchoOpenRequest? {
        guard let bottleID = UserDefaults.standard.string(forKey: bottleKey), !bottleID.isEmpty else {
            return nil
        }
        let request = EchoOpenRequest(
            bottleID: bottleID,
            replyID: UserDefaults.standard.string(forKey: replyKey)
        )
        clear()
        return request
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bottleKey)
        UserDefaults.standard.removeObject(forKey: replyKey)
    }
}

// MARK: - Root

struct ContentView: View {
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var showOnboarding = false
    @State private var selectedTab: TempoTab = .home
    @State private var pendingInvite: PendingTrainingInvite?
    @State private var pendingCarePanel: CarePanelTrigger?
    @State private var pendingResonantSettings: Bool = false
    @State private var pendingBreathing: Bool = false
    @State private var pendingEcho: EchoOpenRequest?
    @State private var careToast: CareEventToast?

    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景
            TempoTheme.background
                .ignoresSafeArea()

            // 装饰光晕
            BackgroundAura()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // 只创建当前页面。旧实现用 opacity 同时保留四页,会让不可见的趋势/共振页
            // 也参与首帧布局并启动 HealthKit/网络任务,复杂图表可直接拖成白屏。
            activeTabContent
            .environment(\.switchToTab) { tab in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    selectedTab = tab
                }
            }

            // 所有主页面共用:滚动内容进入状态栏时柔和模糊并渐隐。
            TopScrollFadeLayer()
                .zIndex(5)

            // 浮动 Tab Bar
            FloatingTabBar(selection: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            if let toast = careToast {
                CareEventToastView(toast: toast) {
                    Task { await FriendsService.shared.markCareEventsRead(eventIDs: [toast.id]) }
                    careToast = nil
                    let friendID = FriendsService.shared.friends.first(where: { $0.displayName == toast.fromName })?.id
                    pendingCarePanel = CarePanelTrigger(friendID: friendID)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .sheet(item: $pendingInvite) { invite in
            TrainingInviteResponderSheet(invite: invite)
        }
        .sheet(item: $pendingCarePanel) { trig in
            CarePanelView(initialFriendID: trig.friendID)
        }
        .sheet(isPresented: $pendingResonantSettings) {
            ResonantSettingsView()
        }
        .sheet(isPresented: $pendingBreathing) {
            BreathingView()
        }
        .onAppear {
            if !onboardingCompleted {
                showOnboarding = true
            }
            if let request = BottleDeepLinkStore.consume() {
                openEcho(request)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoTrainingInvite)) { notif in
            guard let info = notif.userInfo,
                  let typeRaw = info["type"] as? String,
                  let type = ResonantEventType(rawValue: typeRaw),
                  let minutes = info["minutes"] as? Int,
                  let fromName = info["fromName"] as? String else { return }
            let eventID = (info["eventID"] as? String) ?? ""
            pendingInvite = PendingTrainingInvite(type: type, minutes: minutes, fromName: fromName, eventID: eventID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoOpenCarePanel)) { notif in
            let info = notif.userInfo ?? [:]
            if info["markCareRead"] as? Bool == true,
               let eventID = info["eventID"] as? String,
               !eventID.isEmpty {
                Task { await FriendsService.shared.markCareEventsRead(eventIDs: [eventID]) }
            }
            let friendID = info["friendID"] as? String
            let fromName = info["fromName"] as? String
            let resolvedID = friendID ?? FriendsService.shared.friends.first(where: { $0.displayName == fromName })?.id
            pendingCarePanel = CarePanelTrigger(friendID: resolvedID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoOpenResonantSettings)) { _ in
            // “添加密友”是明确的用户导航，优先级高于尚未消费的漂流瓶 deep link。
            // 先清理旧回声请求，避免切到共振页时 fullScreenCover 抢在设置 sheet 前出现。
            pendingEcho = nil
            BottleDeepLinkStore.clear()
            pendingResonantSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoOpenBreathing)) { _ in
            pendingBreathing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoOpenBottleSea)) { notification in
            let request = BottleDeepLinkStore.request(from: notification.userInfo)
                ?? BottleDeepLinkStore.consume()
                ?? .generic
            BottleDeepLinkStore.clear()
            openEcho(request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoCareEventReceived)) { notif in
            guard let info = notif.userInfo else { return }
            let toast = CareEventToast(
                id: (info["eventID"] as? String) ?? UUID().uuidString,
                fromName: (info["fromName"] as? String) ?? "密友",
                body: (info["body"] as? String) ?? "发来一条关怀",
                icon: (info["icon"] as? String) ?? "heart.circle.fill"
            )
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                careToast = toast
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                if careToast?.id == toast.id {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        careToast = nil
                    }
                }
            }
        }
    }

    private func openEcho(_ request: EchoOpenRequest) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedTab = .breathe
        }
        pendingEcho = request
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .trends:
            HistoryView()
        case .breathe:
            ResonanceView(openEcho: $pendingEcho)
        case .profile:
            SettingsView()
        }
    }
}


#Preview {
    ContentView()
}
