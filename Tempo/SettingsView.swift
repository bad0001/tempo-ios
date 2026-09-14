//
//  SettingsView.swift
//  Tempo
//
//  "我的"页主视图。
//

import SwiftUI
import SwiftData
import TempoCore
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif

/// SettingsView @Query 引用的 streak cutoff: file-level let 才能被 #Predicate 接受。
private let settingsStreakWindowCutoff: Date = Date(timeIntervalSinceNow: -365 * 86_400)

struct SettingsView: View {
    @AppStorage("continuousMonitoring") private var continuousMonitoring = false
    @AppStorage("smartRemindersEnabled") private var smartRemindersEnabled = false
    @AppStorage("totalMindfulMinutes") private var totalMindfulMinutes: Double = 0
    @AppStorage("user.hasAppleMusic") private var hasAppleMusic = false
    @AppStorage("tempo.apnsToken") private var apnsToken = ""
    @AppStorage("push.registrationFailed") private var pushRegistrationFailed = false
    @AppStorage(TempoAppLanguage.storageKey) private var selectedLanguage = TempoAppLanguage.system.rawValue
    @State private var showPaywall = false
    @State private var showPersonalInfo = false
    @State private var showFriends = false
    @State private var showCarePanel = false
    @State private var showPreferences = false
    @State private var showLanguage = false
    @State private var showPrivacy = false
    @State private var showHelp = false
    @State private var showWakeup = false
    @State private var showMentalHealth = false
    @State private var showResonantSpace = false
    @State private var purchase = PurchaseManager.shared
    @State private var streakDays: Int = 0
    @State private var friendsService = FriendsService.shared
    @State private var session = TempoSession.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRefreshingDiagnostics = false
    @State private var diagnosticsMessage: String?
    @State private var showLogoutConfirm = false
    @State private var isLoggingOut = false
    // 只拉最近一年的 StressEntry 用来算 streak / 显示总计,避免长期用户拉全表卡顿。
    // streak 算法不会跨过 365 天,所以 365 天 window 完全够用。
    @Query(filter: #Predicate<StressEntry> { entry in
        entry.timestamp >= settingsStreakWindowCutoff
    }, sort: \StressEntry.timestamp, order: .reverse) private var allEntries: [StressEntry]

    private var resonantBadge: Int {
        friendsService.pendingFriendRequestCount
        + friendsService.unreadEncouragesCount
        + friendsService.unreadResonantEventsCount
    }

    private var mindfulHours: String {
        let hours = totalMindfulMinutes / 60
        return String(format: "%.1f", hours)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("我的")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    SettingsDiagnosticsCard(
                        session: session,
                        friendsService: friendsService,
                        hasAppleMusic: hasAppleMusic,
                        apnsToken: apnsToken,
                        pushRegistrationFailed: pushRegistrationFailed,
                        notificationStatus: notificationStatus,
                        syncInProgress: isRefreshingDiagnostics,
                        syncMessage: diagnosticsMessage,
                        onSync: {
                            Task { await refreshDiagnostics() }
                        },
                        onPushAction: {
                            Task { await handlePushAction() }
                        }
                    )

                    if purchase.isPro {
                        ProActiveCard()
                    } else {
                        Button { showPaywall = true } label: { ProUpsellCard() }
                            .buttonStyle(.tempoPress)
                    }

                    sectionTitle("通用")

                    VStack(spacing: 0) {
                        Button {
                            showLanguage = true
                        } label: {
                            SettingsNavigationRow(
                                icon: "globe.asia.australia.fill",
                                iconColor: TempoTheme.accent,
                                title: String(localized: "语言", locale: activeLanguage.locale),
                                subtitle: activeLanguage.localizedName
                            )
                        }
                        .buttonStyle(.tempoPress)
                    }
                    .settingsPanel()

                    sectionTitle("账号")

                    VStack(spacing: 0) {
                        SettingsRow(icon: "person.text.rectangle.fill", iconColor: Color.pink, title: "个人信息") {
                            showPersonalInfo = true
                        }
                    }
                    .settingsPanel()

                    sectionTitle("Apple Watch 与数据")

                    VStack(spacing: 0) {
                        SettingsRow(icon: "gearshape.fill", iconColor: TempoTheme.accent, title: "偏好设置") {
                            showPreferences = true
                        }
                        Divider().padding(.leading, 68)
                        SettingsRow(icon: "shield.lefthalf.filled", iconColor: TempoTheme.success, title: "隐私与数据") {
                            showPrivacy = true
                        }
                    }
                    .settingsPanel()

                    sectionTitle("共振与通知")

                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "heart.text.square.fill",
                            iconColor: Color(hex: "EC4899"),
                            title: "共振设置",
                            badge: resonantBadge
                        ) {
                            showFriends = true
                        }
                    }
                    .settingsPanel()

                    sectionTitle("健康记录")

                    HStack(spacing: 12) {
                        StatBoxCard(value: "\(streakDays)", unit: "天", title: "连续记录")
                        StatBoxCard(value: mindfulHours, unit: "h", title: "正念时长")
                    }

                    sectionTitle("更多")

                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "brain.head.profile",
                            iconColor: Color.purple,
                            title: "心理健康自评"
                        ) {
                            showMentalHealth = true
                        }
                        Divider().padding(.leading, 68)
                        SettingsRow(
                            icon: "person.2.wave.2.fill",
                            iconColor: Color(hex: "8B5CF6"),
                            title: "共振空间",
                            iconSize: 38,
                            titleSize: 16,
                            verticalPadding: 14
                        ) {
                            showResonantSpace = true
                        }
                        Divider().padding(.leading, 68)
                        SettingsRow(
                            icon: "sunrise.fill",
                            iconColor: Color(hex: "F97316"),
                            title: "节奏唤醒",
                            iconSize: 38,
                            titleSize: 16,
                            verticalPadding: 14
                        ) {
                            showWakeup = true
                        }
                        Divider().padding(.leading, 68)
                        SettingsRow(icon: "questionmark.circle.fill", iconColor: TempoTheme.warning, title: "帮助与支持") {
                            showHelp = true
                        }
                    }
                    .settingsPanel()

                    if session.isLoggedIn {
                        Button {
                            guard !isLoggingOut else { return }
                            showLogoutConfirm = true
                        } label: {
                            Text(LocalizedStringKey(isLoggingOut ? "正在退出" : "退出当前账号"))
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(TempoTheme.danger)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(TempoTheme.dangerSoft.opacity(0.6))
                                )
                        }
                        .buttonStyle(.tempoPress)
                        .disabled(isLoggingOut)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showPersonalInfo) { PersonalInfoView() }
            .sheet(isPresented: $showFriends) { ResonantSettingsView() }
            .sheet(isPresented: $showCarePanel) { CarePanelView() }
            .sheet(isPresented: $showPreferences) {
                PreferencesView(
                    continuousMonitoring: $continuousMonitoring,
                    smartRemindersEnabled: $smartRemindersEnabled
                )
            }
            .sheet(isPresented: $showLanguage) {
                LanguageSettingsView()
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyDataView(allEntries: allEntries)
            }
            .sheet(isPresented: $showWakeup) { WakeupSettingsView() }
            .sheet(isPresented: $showMentalHealth) { MentalHealthHubView() }
            .sheet(isPresented: $showResonantSpace) { ResonantSpaceHubView() }
            .sheet(isPresented: $showHelp) {
                HelpSupportView()
            }
            .alert("退出当前 Tempo 账号?", isPresented: $showLogoutConfirm) {
                Button("退出", role: .destructive) {
                    Task { await logoutCurrentSession() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只退出这台 iPhone。服务器上的密友关系和健康摘要不会被删除。")
            }
            .onAppear {
                streakDays = Self.computeStreak(from: allEntries)
            }
            .onChange(of: allEntries.count) { _, _ in
                streakDays = Self.computeStreak(from: allEntries)
            }
            .task {
                await refreshSettingsContext()
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(TempoTheme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    private var activeLanguage: TempoAppLanguage {
        TempoAppLanguage(rawValue: selectedLanguage) ?? .system
    }

    @MainActor
    private func logoutCurrentSession() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        let deviceDetached = await session.logout()
        isLoggingOut = false
        diagnosticsMessage = deviceDetached
            ? "已退出当前账号,这台 iPhone 的推送已解绑。"
            : "已退出当前账号。下次登录时会重新绑定这台 iPhone 的推送。"
    }

    @MainActor
    private func refreshSettingsContext() async {
        await refreshNotificationStatus()
        guard session.isLoggedIn else {
            await friendsService.refreshPendingFriendRequests()
            return
        }
        await session.refreshFromServer()
        await uploadLatestStressSnapshotIfPossible()
        await friendsService.refreshPendingFriendRequests()
        await friendsService.refreshFriends()
        await friendsService.loadResonantEvents()
        await friendsService.loadEncourages()
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    @MainActor
    private func refreshDiagnostics() async {
        guard !isRefreshingDiagnostics else { return }
        isRefreshingDiagnostics = true
        diagnosticsMessage = nil
        defer { isRefreshingDiagnostics = false }

        await refreshNotificationStatus()
        guard session.isLoggedIn else {
            diagnosticsMessage = "需要先通过 Apple 登录,才能同步密友、压力摘要和关怀通知。"
            return
        }

        await session.refreshFromServer()
        await uploadLatestStressSnapshotIfPossible()
        var pushProblem: String?
        if let token = APNsTokenStore.shared.token, !token.isEmpty {
            do {
                try await TempoAPIClient.shared.registerDevice(
                    deviceId: session.deviceId,
                    apnsToken: token
                )
                UserDefaults.standard.set(false, forKey: "push.registrationFailed")
            } catch {
                pushProblem = "推送注册失败:\(error.localizedDescription)"
            }
        } else if pushRegistrationFailed {
            pushProblem = "APNs 注册失败,请检查系统通知权限"
        }

        await friendsService.refreshPendingFriendRequests()
        await friendsService.refreshFriends()
        await friendsService.loadResonantEvents()
        await friendsService.loadEncourages()
        await refreshNotificationStatus()

        let unread = friendsService.unreadEncouragesCount + friendsService.unreadResonantEventsCount
        if let pushProblem {
            diagnosticsMessage = "\(pushProblem)。密友 \(friendsService.friends.count) 位已刷新。"
        } else {
            diagnosticsMessage = "已刷新密友 \(friendsService.friends.count) 位、待处理 \(friendsService.pendingFriendRequestCount) 条、未读关怀 \(unread) 条。"
        }
    }

    @MainActor
    private func uploadLatestStressSnapshotIfPossible() async {
        guard let latest = allEntries.first else { return }
        await friendsService.updateMyStress(score: latest.scoreValue, level: latest.levelRaw)
    }

    @MainActor
    private func handlePushAction() async {
        await refreshNotificationStatus()
        if notificationStatus == .denied {
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            #endif
            return
        }

        _ = await NotificationManager.shared.requestAuthorization()
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
        await refreshNotificationStatus()
        await refreshDiagnostics()
    }

    private static func computeStreak(from entries: [StressEntry]) -> Int {
        let calendar = Calendar.current
        let days: Set<Date> = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        if !days.contains(checkDate) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            checkDate = yesterday
        }

        while days.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }
}
