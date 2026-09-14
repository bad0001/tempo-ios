//
//  ResonantSettingsComponents.swift
//  Tempo
//
//  Smaller cards used by ResonantSettingsView. Keep business actions in the
//  parent view so this file stays layout-only.
//

import SwiftUI
import TempoCore

struct ResonantSettingsOverviewCard: View {
    let friendCount: Int
    let pendingCount: Int
    let publicId: String?
    let sharingMyStress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.pink.opacity(0.95), TempoTheme.breathing.opacity(0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("密友共振")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(friendCount == 0 ? "先建立一个稳定通道,再开始互相关怀。" : "已连接 \(friendCount) 位密友,可互看状态和发送关怀。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                overviewPill(title: "我的 ID", value: publicId ?? "------", color: TempoTheme.accent)
                overviewPill(title: "待处理", value: "\(pendingCount)", color: Color.pink)
                overviewPill(title: "分享", value: sharingMyStress ? "开" : "关", color: sharingMyStress ? TempoTheme.success : TempoTheme.tertiaryText)
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }

    private func overviewPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }
}

struct ResonantSettingsLoginCard: View {
    let onSignedIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "applelogo")
                    .font(.system(size: 16))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("启用共振关怀")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
            }
            Text("用 Apple ID 登录后,你会拿到一个 6 位「共振 ID」。把 ID 告诉家人或最在意的朋友,Ta 输入后即可建立密友关系。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            AppleSignInButton(onSuccess: onSignedIn)
        }
        .tempoCard(radius: 18, padding: 14)
    }
}

struct ResonantSettingsConnectionHubCard: View {
    let publicId: String?
    let copyHint: String?
    @Binding var inputPublicId: String
    let sendingRequest: Bool
    let requestErrorText: String?
    let onCopyPublicId: () -> Void
    let onSendRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.pink)
                Text("建立连接")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                if let hint = copyHint {
                    Text(LocalizedStringKey(hint))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(TempoTheme.success)
                        .transition(.opacity)
                }
            }

            publicIdBlock

            Rectangle()
                .fill(TempoTheme.tertiaryText.opacity(0.14))
                .frame(height: 1)

            addFriendBlock

            if let err = requestErrorText {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("对方接受后,你们才能互看压力摘要和发送关怀通知。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }

    private var publicIdBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我的共振 ID")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(spacing: 10) {
                Text(publicId ?? "------")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(TempoTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(TempoTheme.accentSoft)
                    )

                Button(action: onCopyPublicId) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 54)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TempoTheme.accent))
                }
                .buttonStyle(.tempoPress)
                .accessibilityLabel("复制我的共振 ID")

                if let publicId {
                    ShareLink(item: "我在 Tempo 共振关怀,我的 ID:\(publicId)。在 Tempo → 设置 → 共振设置里输入它就能加我。") {
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TempoTheme.accent)
                            .frame(width: 48, height: 54)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TempoTheme.accentSoft))
                    }
                    .buttonStyle(.tempoPress)
                    .accessibilityLabel("分享我的共振 ID")
                }
            }
        }
    }

    private var addFriendBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("添加对方")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(spacing: 10) {
                TextField("输入 6 位 ID", text: $inputPublicId)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "F8FAFC"))
                    )
                    .onChange(of: inputPublicId) { _, newValue in
                        let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                        inputPublicId = String(filtered.prefix(6))
                    }

                Button(action: onSendRequest) {
                    Group {
                        if sendingRequest {
                            ProgressView().tint(.white)
                        } else {
                            Text("发送")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 68, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(inputPublicId.count == 6 ? Color.pink : TempoTheme.tertiaryText)
                    )
                }
                .buttonStyle(.tempoPress)
                .disabled(inputPublicId.count != 6 || sendingRequest)
                .accessibilityLabel("发送密友请求")
            }
        }
    }
}

struct ResonantSettingsInboxCard: View {
    let requests: [FriendRequestInboxResponse.IncomingRequest]
    let actingRequestIDs: Set<String>
    let onAccept: (FriendRequestInboxResponse.IncomingRequest) -> Void
    let onDecline: (FriendRequestInboxResponse.IncomingRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.pink)
                Text("待处理请求")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("\(requests.count)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.pink))
            }
            ForEach(requests) { request in
                row(for: request)
                if request.id != requests.last?.id {
                    Divider()
                }
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }

    private func row(for request: FriendRequestInboxResponse.IncomingRequest) -> some View {
        let isActing = actingRequestIDs.contains(request.requestId)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.fromName ?? "好友")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                if let publicId = request.fromPublicId {
                    Text("ID:\(publicId)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
            Spacer()
            Button {
                onAccept(request)
            } label: {
                Group {
                    if isActing {
                        ProgressView().tint(.white)
                    } else {
                        Text("接受")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(minWidth: 44)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(TempoTheme.accent.opacity(isActing ? 0.6 : 1.0)))
            }
            .buttonStyle(.tempoPress)
            .disabled(isActing)
            .accessibilityLabel("接受 \(request.fromName ?? "好友") 的密友请求")

            Button {
                onDecline(request)
            } label: {
                Text("拒绝")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.tertiaryText.opacity(isActing ? 0.5 : 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.tempoPress)
            .disabled(isActing)
            .accessibilityLabel("拒绝 \(request.fromName ?? "好友") 的密友请求")
        }
    }
}

struct ResonantSettingsOutgoingCard: View {
    let requests: [FriendRequestOutgoingResponse.OutgoingRequest]
    let onCancel: (FriendRequestOutgoingResponse.OutgoingRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(TempoTheme.tertiaryText)
                Text("已发出的请求")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(TempoTheme.secondaryText)
            }
            ForEach(requests) { request in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.toName ?? "对方")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                        Text("ID:\(request.toPublicId ?? "—")  ·  等待对方接受")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                    Spacer()
                    Button {
                        onCancel(request)
                    } label: {
                        Text("取消")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(TempoTheme.danger)
                    }
                    .buttonStyle(.tempoPress)
                    .accessibilityLabel("取消发给 \(request.toName ?? "") 的请求")
                }
                .padding(.vertical, 4)
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }
}

struct ResonantSettingsFriendsCard: View {
    let service: FriendsService
    let onEditRelationship: (Friend) -> Void
    let onToggleMute: (Friend) -> Void
    let onLeave: (Friend) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.accent)
                Text("我的密友")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                if !service.friends.isEmpty {
                    Text("\(service.friends.count)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
            if service.friends.isEmpty {
                Text("还没绑定密友。在上面输入对方的共振 ID,Ta 接受后就会出现在这里。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .padding(.vertical, 6)
            } else {
                ForEach(service.friends) { friend in
                    friendRow(friend)
                    if friend.id != service.friends.last?.id { Divider() }
                }
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }

    private func friendRow(_ friend: Friend) -> some View {
        let muted = service.isMuted(friend)
        let muteColor = muted ? TempoTheme.tertiaryText : TempoTheme.success
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(friend.levelColor.opacity(0.18))
                    .frame(width: 42, height: 42)
                Text(String(friend.displayName.prefix(1)))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(friend.levelColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(friend.displayName)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if let relationship = service.relationship(for: friend), !relationship.isEmpty {
                        Text(LocalizedStringKey(relationship))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(friend.levelColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(friend.levelColor.opacity(0.12)))
                    }
                }
                Text("压力 \(friend.stressScore) · \(friend.formattedLastUpdated)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
            Button {
                onEditRelationship(friend)
            } label: {
                Image(systemName: "tag.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TempoTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(TempoTheme.accentSoft))
            }
            .buttonStyle(.tempoPress)
            .accessibilityLabel("设置 \(friend.displayName) 的关系标签")

            Button {
                onToggleMute(friend)
            } label: {
                Image(systemName: muted ? "bell.slash.fill" : "bell.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(muteColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(muteColor.opacity(0.12)))
            }
            .buttonStyle(.tempoPress)
            .accessibilityLabel(muted ? "取消静音 \(friend.displayName)" : "静音 \(friend.displayName)")

            Menu {
                Button(role: .destructive) {
                    onLeave(friend)
                } label: {
                    Label("解除绑定", systemImage: "person.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .buttonStyle(.tempoPress)
            .accessibilityLabel("\(friend.displayName) 的更多操作")
            .accessibilityHint("可静音或解除绑定")
        }
        .padding(.vertical, 4)
    }
}

struct ResonantSettingsSharingCard: View {
    let service: FriendsService
    let alertSettings: AlertSettings
    let onSetSharing: (Bool) -> Void
    let onPauseSharing: (TimeInterval) -> Void
    let onResumeSharing: () -> Void

    var body: some View {
        let _ = alertSettings.version
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.accent)
                Text("共享设置")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("分享我的 stress")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(service.sharingMyStress ? "好友能看到你的实时压力和趋势" : "已关闭,好友看不到")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { service.sharingMyStress },
                    set: { onSetSharing($0) }
                ))
                .labelsHidden()
                .tint(TempoTheme.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("分享我的 stress")

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("同步 HRV 摘要")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(service.shareHRVWithServer
                         ? "最近的 HRV 数值与时间会加密上传,用于趋势和密友摘要"
                         : "默认关闭;HRV 记录只在你的设备上处理")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { service.shareHRVWithServer },
                    set: { service.setShareHRVWithServer($0) }
                ))
                .labelsHidden()
                .tint(TempoTheme.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("同步 HRV 摘要到 Tempo 服务器")

            Divider()

            // 分享呼吸 / 冥想训练 session(默认 off)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("分享我的训练")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(service.shareTrainingWithFriends
                         ? "好友能看到「Ta 今天做了 X 次呼吸 / Y 分钟冥想」"
                         : "已关闭,呼吸 / 冥想 session 仅对你可见")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { service.shareTrainingWithFriends },
                    set: { service.setShareTrainingWithFriends($0) }
                ))
                .labelsHidden()
                .tint(TempoTheme.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("分享我的训练给好友")

            pauseControls
        }
        .tempoCard(radius: 18, padding: 14)
    }

    @ViewBuilder
    private var pauseControls: some View {
        if let until = alertSettings.pauseUntil {
            HStack {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.warning)
                Text("已暂停到 \(formatTime(until))")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Button("恢复") { onResumeSharing() }
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.accent)
                    .buttonStyle(.tempoPress)
            }
        } else if service.sharingMyStress {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(TempoTheme.tertiaryText)
                Text("临时暂停")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.secondaryText)
                Spacer()
                Menu {
                    Button("1 小时") { onPauseSharing(3600) }
                    Button("6 小时") { onPauseSharing(6 * 3600) }
                    Button("24 小时") { onPauseSharing(24 * 3600) }
                } label: {
                    HStack(spacing: 3) {
                        Text("选择时长")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.accent)
                }
                .buttonStyle(.tempoPress)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDate(date, inSameDayAs: Date()) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d HH:mm"
        }
        return formatter.string(from: date)
    }
}

struct ResonantSettingsAlertCard: View {
    let alertSettings: AlertSettings
    @State private var recommendations: [HealthAlertMetric: (current: Double, recommended: Double, delta: Double)] = [:]

    var body: some View {
        let _ = alertSettings.version
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.alert)
                Text("告警分享")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
            }
            Text("朋友看不到具体数值,只在异常时收到「需要关注」提醒。默认全部关闭,你必须主动启用。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)

            ForEach(HealthAlertMetric.allCases, id: \.self) { metric in
                metricRow(metric)
                if metric != HealthAlertMetric.allCases.last {
                    Divider()
                }
            }
        }
        .tempoCard(radius: 18, padding: 14)
        .task(id: alertSettings.version) { await loadRecommendations() }
        .onReceive(NotificationCenter.default.publisher(for: .tempoUserProfileChanged)) { _ in
            Task { await loadRecommendations() }
        }
    }

    private func loadRecommendations() async {
        var dict: [HealthAlertMetric: (current: Double, recommended: Double, delta: Double)] = [:]
        for metric in HealthAlertMetric.allCases {
            if let r = await alertSettings.shouldSuggestRecommended(for: metric) {
                dict[metric] = r
            }
        }
        recommendations = dict
    }

    private func metricRow(_ metric: HealthAlertMetric) -> some View {
        let enabled = alertSettings.isEnabled(metric)
        let threshold = alertSettings.threshold(for: metric)
        let recommendation = recommendations[metric]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: metric.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(enabled ? TempoTheme.alert : TempoTheme.tertiaryText)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(metric.label))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(LocalizedStringKey(metric.description))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { alertSettings.isEnabled(metric) },
                        set: { alertSettings.setEnabled($0, for: metric) }
                    )
                )
                .labelsHidden()
                .tint(TempoTheme.alert)
            }
            if enabled {
                HStack(spacing: 10) {
                    Spacer().frame(width: 28)
                    Text("阈值")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                    Text("\(Int(threshold)) \(metric.unit)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                        .monospacedDigit()
                        .frame(minWidth: 60, alignment: .leading)
                    Spacer()
                    Stepper(
                        "",
                        value: Binding(
                            get: { threshold },
                            set: { alertSettings.setThreshold($0, for: metric) }
                        ),
                        in: thresholdRange(for: metric),
                        step: thresholdStep(for: metric)
                    )
                    .labelsHidden()
                }

                if let rec = recommendation, enabled {
                    HStack(spacing: 8) {
                        Spacer().frame(width: 28)
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(TempoTheme.warning)
                        Text("根据您的资料,推荐 \(Int(rec.recommended)) \(metric.unit)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TempoTheme.secondaryText)
                        Spacer()
                        Button("使用") {
                            Task {
                                await alertSettings.applyRecommendedThreshold(for: metric)
                                await loadRecommendations()
                            }
                        }
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(TempoTheme.accent))
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func thresholdRange(for metric: HealthAlertMetric) -> ClosedRange<Double> {
        switch metric {
        case .heartRateHigh: 100...180
        case .heartRateLow: 35...60
        case .spo2Low: 85...96
        }
    }

    private func thresholdStep(for metric: HealthAlertMetric) -> Double.Stride {
        switch metric {
        case .heartRateHigh, .heartRateLow: 5
        case .spo2Low: 1
        }
    }
}
