//
//  SettingsDiagnosticsView.swift
//  Tempo
//
//  设置页里的关键链路状态面板。它不是技术日志,而是给用户 / QA 一眼确认:
//  登录、Public ID、推送、压力共享、Apple Music、密友同步是否正常。
//

import SwiftUI
import UserNotifications

struct SettingsDiagnosticsCard: View {
    @Environment(\.locale) private var locale
    let session: TempoSession
    let friendsService: FriendsService
    let hasAppleMusic: Bool
    let apnsToken: String
    let pushRegistrationFailed: Bool
    let notificationStatus: UNAuthorizationStatus
    let syncInProgress: Bool
    let syncMessage: String?
    let onSync: () -> Void
    let onPushAction: () -> Void

    private var isNotificationAllowed: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            true
        default:
            false
        }
    }

    private var notificationLabel: String {
        if pushRegistrationFailed { return "注册失败" }
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return apnsToken.isEmpty ? "等待令牌" : "已连接"
        case .denied:
            return "已关闭"
        case .notDetermined:
            return "未开启"
        @unknown default:
            return "待确认"
        }
    }

    private var notificationColor: Color {
        if pushRegistrationFailed { return TempoTheme.danger }
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return apnsToken.isEmpty ? TempoTheme.warning : TempoTheme.success
        case .denied:
            return TempoTheme.danger
        case .notDetermined:
            return TempoTheme.warning
        @unknown default:
            return TempoTheme.warning
        }
    }

    private var pushActionTitle: String? {
        if notificationStatus == .denied { return "去系统设置" }
        if notificationStatus == .notDetermined { return "开启通知" }
        if pushRegistrationFailed || (isNotificationAllowed && apnsToken.isEmpty) { return "重新注册" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: session.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(session.isLoggedIn ? TempoTheme.accent : TempoTheme.tertiaryText)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    if let displayName = session.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                            .lineLimit(1)
                    } else {
                        Text("登录 Tempo")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                    }
                    if let publicId = session.publicId {
                        Text("共振 ID  \(publicId)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    } else {
                        Text("同步密友与关怀通知")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }

                Spacer(minLength: 8)

                ConnectionBadge(
                    title: session.isLoggedIn ? "已登录" : "未登录",
                    color: session.isLoggedIn ? TempoTheme.success : TempoTheme.warning
                )
            }

            Divider()

            HStack(spacing: 0) {
                compactStatus(title: "密友", value: friendCountText, color: friendsService.friends.isEmpty ? TempoTheme.tertiaryText : Color.pink)
                compactStatus(title: "通知", value: notificationLabel, color: notificationColor)
                compactStatus(title: "压力共享", value: friendsService.sharingMyStress ? "开启" : "暂停", color: friendsService.sharingMyStress ? TempoTheme.success : TempoTheme.warning)
            }

            if let syncMessage {
                Text(syncMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(syncMessage.contains("失败") ? TempoTheme.danger : TempoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pushActionTitle {
                Button(action: onPushAction) {
                    Text(LocalizedStringKey(pushActionTitle))
                        .font(.system(size: 13, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.tempoPress)
                .disabled(syncInProgress)
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private var friendCountText: String {
        if locale.tempoUsesEnglish {
            let count = friendsService.friends.count
            return "\(count) \(count == 1 ? "friend" : "friends")"
        }
        return "\(friendsService.friends.count) 位"
    }

    private func compactStatus(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(LocalizedStringKey(value))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

private struct DiagnosticStatusPill: View {
    let title: String
    let value: String
    let systemName: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                Text(LocalizedStringKey(value))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "F8FAFC"))
        )
    }
}
