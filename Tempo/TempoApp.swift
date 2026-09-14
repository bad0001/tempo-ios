//
//  TempoApp.swift
//  Tempo
//
//  Created by 刘辰奕 on 2026/4/26.
//

import SwiftUI
import SwiftData
import TempoCore

@main
struct TempoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(TempoAppLanguage.storageKey) private var selectedLanguage = TempoAppLanguage.system.rawValue
    let sharedModelContainer: ModelContainer = TempoSharedStore.makeModelContainer()

    init() {
        PhoneSessionManager.shared.activate()
        PhoneSessionManager.shared.modelContainer = sharedModelContainer
        // 给 Task 闭包用的 local 副本,避免 capture self
        let container = sharedModelContainer
        Task { @MainActor in
            // v2 算法:启动先 reload 用户画像 + 预热 28d baseline stats
            UserProfileStore.shared.reload()
            _ = await StressBaselineService.shared.currentStats(container: container)
            _ = try? await HealthKitService.shared.requestAuthorization()
            NotificationsHandler.shared.registerCategories()
            // 已登录的老用户:从 server 拉一次最新 user 数据(拿 publicId 等新字段)
            if TempoSession.shared.isLoggedIn && TempoSession.shared.publicId == nil {
                await TempoSession.shared.refreshFromServer()
            }
            // 已登录:加载朋友 + 待处理请求(让首页 badge 准确)
            if TempoSession.shared.isLoggedIn {
                await FriendsService.shared.checkStatus()
                await FriendsService.shared.loadEncourages()
                await FriendsService.shared.loadResonantEvents()
                await FriendsService.shared.loadFriendAlerts()
                await FriendsService.shared.refreshPendingFriendRequests()
                PhoneSessionManager.shared.pushCachedSnapshotToWatch()
                // Phase 2: 同步共享偏好(server 为准,跨设备一致)
                await FriendsService.shared.syncSharePrefsFromServer()
                // Phase 2: 启动时上传过去 24h HRV samples 给 server 做趋势 / AI 分析
                await FriendsService.shared.uploadRecentHRVIfPossible(daysBack: 1)
            }
        }
        // Phase 2: 每小时上传一次最近 HRV(后台 task,不依赖 user 主动操作)
        Task.detached(priority: .background) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                let loggedIn = await MainActor.run { TempoSession.shared.isLoggedIn }
                if loggedIn {
                    await FriendsService.shared.uploadRecentHRVIfPossible(daysBack: 1)
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, activeLanguage.locale)
                .id(selectedLanguage)
        }
        .modelContainer(sharedModelContainer)
    }

    private var activeLanguage: TempoAppLanguage {
        TempoAppLanguage(rawValue: selectedLanguage) ?? .system
    }
}
