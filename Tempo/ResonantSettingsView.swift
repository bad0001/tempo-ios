//
//  ResonantSettingsView.swift
//  Tempo
//
//  共振设置 — 页面状态、网络动作、弹窗和导航集中在这里;
//  卡片 UI 拆到 ResonantSettingsComponents.swift.
//

import CloudKit
import os
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ResonantSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = TempoSession.shared
    @State private var service = FriendsService.shared
    @State private var alertSettings = AlertSettings.shared

    @State private var inputPublicId: String = ""
    @State private var inboxRequests: [FriendRequestInboxResponse.IncomingRequest] = []
    @State private var outgoingRequests: [FriendRequestOutgoingResponse.OutgoingRequest] = []
    @State private var sendingRequest = false
    @State private var refreshingRequests = false
    @State private var actingRequestIDs: Set<String> = []
    @State private var requestErrorText: String?
    @State private var requestSyncErrorText: String?
    @State private var copyHint: String?
    @State private var leaveTarget: Friend?
    @State private var relationshipTarget: Friend?
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var deleteErrorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    settingsContent
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .background(TempoTheme.background)
            .navigationTitle("共振设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await refreshAll() }
            .refreshable { await refreshAll() }
            .onReceive(NotificationCenter.default.publisher(for: .tempoFriendRequestsChanged)) { _ in
                Task {
                    await refreshRequests()
                    await service.refreshFriends()
                }
            }
            .sheet(item: $relationshipTarget) { friend in
                RelationshipPickerSheet(friend: friend)
            }
            .alert(
                "解除与 \(leaveTarget?.displayName ?? "") 的绑定?",
                isPresented: Binding(
                    get: { leaveTarget != nil },
                    set: { if !$0 { leaveTarget = nil } }
                ),
                presenting: leaveTarget
            ) { friend in
                Button("解除", role: .destructive) {
                    Task {
                        await service.leaveShare(with: friend)
                        leaveTarget = nil
                    }
                }
                Button("取消", role: .cancel) { leaveTarget = nil }
            } message: { _ in
                Text("解除后你和 Ta 不再互看 stress、不再收到对方鼓励。可以随时重新添加。")
            }
            .alert("退出登录?", isPresented: $showLogoutConfirm) {
                Button("退出", role: .destructive) {
                    Task { _ = await session.logout() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后你需要重新登录才能添加新密友。已建立的密友关系保留在 Tempo 服务器。")
            }
            .alert("永久删除账号?", isPresented: $showDeleteConfirm) {
                Button("永久删除", role: .destructive) {
                    Task {
                        do {
                            try await TempoAPIClient.shared.deleteAccount()
                            session.clear()
                        } catch {
                            deleteErrorText = "账号仍然保留。请检查网络后重试。\n\(error.localizedDescription)"
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除账号会清除密友关系、推送令牌和用户内容，此操作不可恢复。若有自动续订，删除账号不会取消订阅；你仍可立即删除，并在 Apple 订阅中单独取消续订。")
            }
            .alert(
                "账号删除失败",
                isPresented: Binding(
                    get: { deleteErrorText != nil },
                    set: { if !$0 { deleteErrorText = nil } }
                )
            ) {
                Button("知道了", role: .cancel) { deleteErrorText = nil }
            } message: {
                Text(deleteErrorText ?? "请稍后重试。")
            }
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if session.isLoggedIn {
            ResonantSettingsOverviewCard(
                friendCount: service.friends.count,
                pendingCount: inboxRequests.count + outgoingRequests.count,
                publicId: session.publicId,
                sharingMyStress: service.sharingMyStress
            )
            TempoDataStateView(
                state: settingsDataState,
                loadingTitle: "正在同步账户与邀请",
                emptyTitle: "还没有共振关系",
                emptyDetail: "输入对方的 6 位共振 ID 即可发送邀请。",
                cachedTitle: "正在显示离线共振设置",
                showsEmpty: false,
                onRetry: { Task { await refreshAll() } }
            )
            ResonantSettingsConnectionHubCard(
                publicId: session.publicId,
                copyHint: copyHint,
                inputPublicId: $inputPublicId,
                sendingRequest: sendingRequest,
                requestErrorText: requestErrorText,
                onCopyPublicId: copyPublicId,
                onSendRequest: { Task { await sendRequest() } }
            )
            if !inboxRequests.isEmpty {
                ResonantSettingsInboxCard(
                    requests: inboxRequests,
                    actingRequestIDs: actingRequestIDs,
                    onAccept: { request in Task { await acceptIncoming(request) } },
                    onDecline: { request in Task { await declineIncoming(request) } }
                )
            } else if refreshingRequests || service.pendingFriendRequestCount > 0 {
                HStack(spacing: 12) {
                    ProgressView().tint(Color.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("正在同步密友邀请")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                        Text("收到通知后会优先加载接受按钮")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TempoTheme.secondaryText)
                    }
                    Spacer()
                }
                .tempoCard(radius: 18, padding: 14)
            }
            if !outgoingRequests.isEmpty {
                ResonantSettingsOutgoingCard(
                    requests: outgoingRequests,
                    onCancel: { request in Task { await cancelOutgoing(request) } }
                )
            }
            ResonantSettingsFriendsCard(
                service: service,
                onEditRelationship: { relationshipTarget = $0 },
                onToggleMute: { service.toggleMute($0) },
                onLeave: { leaveTarget = $0 }
            )
            ResonantSettingsSharingCard(
                service: service,
                alertSettings: alertSettings,
                onSetSharing: { service.setSharingMyStress($0) },
                onPauseSharing: { service.pauseStressSharing(forSeconds: $0) },
                onResumeSharing: { service.resumeStressSharing() }
            )
            ResonantSettingsAlertCard(alertSettings: alertSettings)
        } else {
            ResonantSettingsLoginCard {
                Task { await refreshAll() }
            }
        }
    }

    private var settingsDataState: TempoLoadState {
        if refreshingRequests { return .loading }
        if let requestSyncErrorText { return .failed(requestSyncErrorText) }
        return service.friendSyncState
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if session.isLoggedIn {
            ToolbarItem(placement: .topBarLeading) {
                accountMenu
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .buttonStyle(.tempoPress)
            .accessibilityLabel("关闭共振设置")
        }
    }

    private var accountMenu: some View {
        Menu {
            Button {
                showLogoutConfirm = true
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除账号(server 数据)", systemImage: "trash")
            }
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .buttonStyle(.tempoPress)
        .accessibilityLabel("账户")
        .accessibilityHint("退出登录或删除服务器端账号")
    }

    private func copyPublicId() {
        guard let publicId = session.publicId else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = publicId
        #endif
        withAnimation(.easeInOut(duration: 0.15)) {
            copyHint = "已复制"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                copyHint = nil
            }
        }
    }

    private func refreshAll() async {
        async let requests: Void = refreshRequests()
        async let sessionRefresh: Void = session.refreshFromServer()
        async let status: Void = service.checkStatus()
        _ = await (requests, sessionRefresh, status)
    }

    private func refreshRequests() async {
        guard session.isLoggedIn, !refreshingRequests else { return }
        refreshingRequests = true
        defer { refreshingRequests = false }
        requestSyncErrorText = nil
        var firstSyncError: String?
        async let inbox = TempoAPIClient.shared.friendRequestInbox()
        async let outgoing = TempoAPIClient.shared.friendRequestOutgoing()

        do {
            let inboxResp = try await inbox
            inboxRequests = inboxResp.requests
            service.pendingFriendRequestCount = inboxResp.requests.count
        } catch {
            TempoLog.care.debug("inbox refresh failed: \(error)")
            if case APIError.unauthorized = error {
                service.pendingFriendRequestCount = 0
                inboxRequests = []
            } else {
                firstSyncError = TempoErrorCopy.message(for: error)
            }
        }

        do {
            let outgoingResp = try await outgoing
            outgoingRequests = outgoingResp.requests
        } catch {
            TempoLog.care.debug("outgoing refresh failed: \(error)")
            if case APIError.unauthorized = error {
                outgoingRequests = []
            } else {
                firstSyncError = firstSyncError ?? TempoErrorCopy.message(for: error)
            }
        }
        requestSyncErrorText = firstSyncError
    }

    private func sendRequest() async {
        guard inputPublicId.count == 6 else { return }
        sendingRequest = true
        defer { sendingRequest = false }
        requestErrorText = nil

        do {
            _ = try await TempoAPIClient.shared.sendFriendRequest(toPublicId: inputPublicId)
            inputPublicId = ""
            await refreshRequests()
        } catch {
            requestErrorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func acceptIncoming(_ request: FriendRequestInboxResponse.IncomingRequest) async {
        guard !actingRequestIDs.contains(request.requestId) else { return }
        actingRequestIDs.insert(request.requestId)
        defer { actingRequestIDs.remove(request.requestId) }

        do {
            let response = try await TempoAPIClient.shared.acceptFriendRequest(request.requestId)
            let zoneID = CKRecordZone.ID(zoneName: "server.\(response.fromUserId)", ownerName: "_tempoServer")
            service.rememberServerIdentity(
                userId: response.fromUserId,
                publicId: request.fromPublicId,
                for: zoneID
            )
            service.restoreRemovedFriend(
                serverUserId: response.fromUserId,
                publicId: request.fromPublicId,
                zoneID: zoneID
            )
            inboxRequests.removeAll { $0.requestId == request.requestId }
            service.pendingFriendRequestCount = inboxRequests.count
            await service.refreshFriends()
            Task { await service.publishLatestStressSnapshotIfPossible() }
            await refreshRequests()
        } catch {
            requestErrorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func declineIncoming(_ request: FriendRequestInboxResponse.IncomingRequest) async {
        guard !actingRequestIDs.contains(request.requestId) else { return }
        actingRequestIDs.insert(request.requestId)
        defer { actingRequestIDs.remove(request.requestId) }

        do {
            try await TempoAPIClient.shared.declineFriendRequest(request.requestId)
        } catch {
            TempoLog.care.debug("decline failed: \(error)")
        }
        await refreshRequests()
    }

    private func cancelOutgoing(_ request: FriendRequestOutgoingResponse.OutgoingRequest) async {
        guard !actingRequestIDs.contains(request.requestId) else { return }
        actingRequestIDs.insert(request.requestId)
        defer { actingRequestIDs.remove(request.requestId) }

        do {
            try await TempoAPIClient.shared.cancelFriendRequest(request.requestId)
        } catch {
            TempoLog.care.debug("cancel failed: \(error)")
        }
        await refreshRequests()
    }
}
