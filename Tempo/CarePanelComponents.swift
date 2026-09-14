//
//  CarePanelComponents.swift
//  Tempo
//
//  UI sections for CarePanelView. Actions stay injected from the parent so
//  sending, read-state and sheet presentation remain easy to audit.
//

import SwiftUI
import TempoCore
#if canImport(UIKit)
import UIKit
#endif

enum CarePanelSendButton: Hashable {
    case presence
    case breathingInvite
    case meditationInvite
    case encourage
}

struct CarePanelActionCard: View {
    let friend: Friend
    let displayName: String
    let isMuted: Bool
    @Binding var customMessage: String
    let activeButton: CarePanelSendButton?
    let onHeartbeat: () -> Void
    let onCheckLater: () -> Void
    let onBreathingInvite: () -> Void
    let onMeditationInvite: () -> Void
    let onSendEncourage: (String) -> Void

    private var isBusy: Bool {
        activeButton != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("关怀 \(displayName)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                if isMuted {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 9))
                        Text("已静音")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(TempoTheme.tertiaryText)
                }
            }

            HStack(spacing: 10) {
                CarePanelQuickButton(
                    icon: "heart.circle.fill",
                    title: "我在",
                    subtitle: activeButton == .presence ? "发送中" : "轻轻拍一下",
                    color: .pink,
                    isSending: activeButton == .presence,
                    disabled: isBusy,
                    action: onHeartbeat
                )
                .accessibilityLabel("告诉 \(displayName) 我在")
                .accessibilityHint("给 \(displayName) 发一个低打扰关怀")

                CarePanelQuickButton(
                    icon: "clock.badge.checkmark.fill",
                    title: "稍后关心",
                    subtitle: "提醒我回看",
                    color: TempoTheme.accent,
                    isSending: false,
                    disabled: isBusy,
                    action: onCheckLater
                )
                .accessibilityLabel("稍后关心 \(displayName)")
                .accessibilityHint("设置本地提醒,稍后回来看 \(displayName) 的状态")

                CarePanelQuickButton(
                    icon: "bubble.left.and.text.bubble.right.fill",
                    title: "说句话",
                    subtitle: "更像真的陪伴",
                    color: TempoTheme.alert,
                    isSending: false,
                    disabled: isBusy,
                    action: {}
                )
                .accessibilityLabel("写一句话给 \(displayName)")
                .accessibilityHint("在下方输入关心的话")
            }

            HStack(spacing: 10) {
                TextField("写句话给 \(displayName)", text: $customMessage)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                Button {
                    onSendEncourage(customMessage)
                } label: {
                    Group {
                        if activeButton == .encourage {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.pink.opacity(isBusy && activeButton != .encourage ? 0.45 : 1)))
                }
                .buttonStyle(.tempoPress)
                .disabled(customMessage.isEmpty || isBusy)
                .accessibilityLabel("发送鼓励")
                .accessibilityHint("把这句话发给 \(displayName)")
            }

            DisclosureGroup("常用鼓励语") {
                VStack(spacing: 8) {
                    ForEach(EncouragePresets.all, id: \.self) { message in
                        Button {
                            onSendEncourage(message)
                        } label: {
                            HStack {
                                Text(message)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(TempoTheme.primaryText)
                                Spacer()
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.pink)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(TempoTheme.background)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.tempoPress)
                        .disabled(isBusy)
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(TempoTheme.secondaryText)

            DisclosureGroup("低频练习邀请") {
                HStack(spacing: 10) {
                    CarePanelQuickButton(
                        icon: "wind.circle.fill",
                        title: "邀请呼吸",
                        subtitle: activeButton == .breathingInvite ? "发送中" : "对方自选",
                        color: TempoTheme.breathing,
                        isSending: activeButton == .breathingInvite,
                        disabled: isBusy,
                        action: onBreathingInvite
                    )
                    .accessibilityLabel("邀请呼吸训练")
                    .accessibilityHint("邀请 \(displayName) 做一段呼吸训练")

                    CarePanelQuickButton(
                        icon: "leaf.circle.fill",
                        title: "邀请冥想",
                        subtitle: activeButton == .meditationInvite ? "发送中" : "对方自选",
                        color: TempoTheme.meditation,
                        isSending: activeButton == .meditationInvite,
                        disabled: isBusy,
                        action: onMeditationInvite
                    )
                    .accessibilityLabel("邀请冥想")
                    .accessibilityHint("邀请 \(displayName) 做一段冥想")
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(TempoTheme.tertiaryText)
        }
        .tempoCard(radius: 18, padding: 14)
    }
}

private struct CarePanelQuickButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isSending: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(color)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }
                .frame(height: 28)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TempoTheme.background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.tempoPress)
        .disabled(disabled)
    }
}

struct CarePanelSendStatusView: View {
    let icon: String
    let color: Color
    let title: String
    let message: String?
    let isLoading: Bool
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 34, height: 34)
                if isLoading {
                    ProgressView()
                        .tint(color)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            if let onRetry {
                Button(action: onRetry) {
                    Text("重试")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(color))
                }
                .buttonStyle(.tempoPress)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.tempoPress)
                .accessibilityLabel("关闭发送状态")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 14, y: 4)
        )
    }
}

struct CarePanelIncomingItem: Identifiable {
    let id: String
    let icon: String
    let iconColor: Color
    let title: String
    let body: String?
    let timeText: String
    let isUnread: Bool
    let sentAt: Date
}

struct CarePanelIncomingCard: View {
    let items: [CarePanelIncomingItem]
    let unreadCount: Int
    let onMarkAllRead: () -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header
                rows
                if items.count > 8 {
                    Text("还有 \(items.count - 8) 条")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .padding(.top, 8)
                }
            }
            .tempoCard(radius: 18, padding: 14)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.pink)
            Text("收到的关怀")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.pink))
            }
            Spacer()
            if unreadCount > 0 {
                Button(action: onMarkAllRead) {
                    Text("全部标已读")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(TempoTheme.accent)
                }
                .buttonStyle(.tempoPress)
            }
        }
    }

    private var rows: some View {
        let visibleItems = Array(items.prefix(8))
        return VStack(spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < visibleItems.count - 1 {
                    Rectangle()
                        .fill(TempoTheme.tertiaryText.opacity(0.15))
                        .frame(height: 0.5)
                        .padding(.leading, 30)
                }
            }
        }
    }

    private func row(_ item: CarePanelIncomingItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 16))
                .foregroundStyle(item.iconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(item.title))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if item.isUnread {
                        Circle()
                            .fill(Color.pink)
                            .frame(width: 7, height: 7)
                    }
                    Spacer()
                    Text(item.timeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                if let body = item.body {
                    Text(body)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct CarePanelTimelineItem: Identifiable {
    let id: String
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
    let timeText: String
    let statusText: String
    let isOutgoing: Bool
    let isUnread: Bool
    let isReply: Bool
    let canReply: Bool
    let trendSummary: CarePanelTrendSummary?
}

struct CarePanelTrendSummary: Equatable {
    let range: String
    let average: Int
    let peak: Int
    let highStressMinutes: Int
    let stressLoad: Int
    let confidence: Int
    let dominant: String
    let hrvText: String
    let episodeCount: Int
    let calmPercent: Int
    let mildPercent: Int
    let highPercent: Int
    let trendPercent: Int?
    let peakLabel: String
}

struct CarePanelTimelineCard: View {
    let friendName: String
    let items: [CarePanelTimelineItem]
    let isRefreshing: Bool
    let onReply: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.care)
                Text("最近互动")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(TempoTheme.care)
                        .accessibilityLabel("正在同步最近互动")
                } else {
                    Text("最近 30 天")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }

            if items.isEmpty {
                HStack(spacing: 10) {
                    SoftIconBubble(systemName: "heart.text.square", color: TempoTheme.care, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("还没有互动")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                        Text("关怀会在这里留下记录。")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TempoTheme.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(12).enumerated()), id: \.element.id) { index, item in
                        timelineRow(item)
                        if index < min(items.count, 12) - 1 {
                            Rectangle()
                                .fill(TempoTheme.tertiaryText.opacity(0.13))
                                .frame(height: 0.5)
                                .padding(.leading, 34)
                        }
                    }
                }
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }

    private func timelineRow(_ item: CarePanelTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(item.iconColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(item.iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(item.title))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if item.isReply {
                        Text("回应")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(TempoTheme.care)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TempoTheme.care.opacity(0.10)))
                    }
                    if item.isUnread {
                        Circle().fill(Color.pink).frame(width: 7, height: 7)
                    }
                    Spacer()
                    Text(item.timeText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }

                if let summary = item.trendSummary {
                    CareTimelineTrendSummaryCard(summary: summary)
                } else {
                    Text(item.body)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if item.isOutgoing {
                        Label(
                            item.statusText,
                            systemImage: item.statusText == "已查看" ? "checkmark.circle.fill" : "checkmark"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.statusText == "已查看" ? TempoTheme.success : TempoTheme.tertiaryText)
                    } else if item.canReply {
                        Button {
                            onReply(item.id)
                        } label: {
                            Label("回应", systemImage: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(TempoTheme.care)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(TempoTheme.care.opacity(0.10)))
                        }
                        .buttonStyle(.tempoPress)
                        .accessibilityLabel("回应 \(friendName) 的关怀")
                    }
                }
            }
        }
        .padding(.vertical, 9)
    }
}

private struct CareTimelineTrendSummaryCard: View {
    let summary: CarePanelTrendSummary
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(summary.range, systemImage: "calendar")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(TempoTheme.care)
                Spacer()
                Text("可信度 \(summary.confidence)%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }

            HStack(spacing: 7) {
                metric("平均", "\(summary.average)", "/100")
                metric("峰值", "\(summary.peak)", "/100")
                metric("高压", "\(summary.highStressMinutes)", "min")
                metric("负荷", "\(summary.stressLoad)", "")
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(TempoTheme.tertiaryText.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [TempoTheme.success, TempoTheme.warning, TempoTheme.danger],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(min(max(summary.average, 0), 100)) / 100)
                }
            }
            .frame(height: 6)

            distributionBar

            HStack(alignment: .top, spacing: 7) {
                Label("\(summary.episodeCount) 个高压片段", systemImage: "bolt.heart.fill")
                Spacer(minLength: 4)
                if let trend = summary.trendPercent {
                    Text("今日均值 \(trend >= 0 ? "+" : "")\(trend)%")
                        .foregroundStyle(trend > 5 ? TempoTheme.danger : trend < -5 ? TempoTheme.success : TempoTheme.secondaryText)
                }
            }
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(TempoTheme.secondaryText)

            Text("主要状态 · \(summary.dominant)   \(summary.hrvText)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TempoTheme.secondaryText)
                .lineLimit(2)

            if !summary.peakLabel.isEmpty {
                Text(summary.peakLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(2)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TempoTheme.care.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TempoTheme.care.opacity(0.13), lineWidth: 0.8)
                )
        )
        .opacity(appeared ? 1 : 0.35)
        .scaleEffect(appeared ? 1 : 0.97)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var distributionBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                let total = max(summary.calmPercent + summary.mildPercent + summary.highPercent, 1)
                HStack(spacing: 2) {
                    if summary.calmPercent > 0 {
                        Capsule()
                            .fill(TempoTheme.success)
                            .frame(width: max(3, proxy.size.width * CGFloat(summary.calmPercent) / CGFloat(total)))
                    }
                    if summary.mildPercent > 0 {
                        Capsule()
                            .fill(TempoTheme.warning)
                            .frame(width: max(3, proxy.size.width * CGFloat(summary.mildPercent) / CGFloat(total)))
                    }
                    if summary.highPercent > 0 {
                        Capsule()
                            .fill(TempoTheme.danger)
                            .frame(width: max(3, proxy.size.width * CGFloat(summary.highPercent) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 6)

            HStack(spacing: 9) {
                distributionLabel("低压", summary.calmPercent, TempoTheme.success)
                distributionLabel("轻压", summary.mildPercent, TempoTheme.warning)
                distributionLabel("高压", summary.highPercent, TempoTheme.danger)
            }
        }
    }

    private func distributionLabel(_ title: String, _ percent: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(title) \(percent)%")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                if !unit.isEmpty {
                    Text(LocalizedStringKey(unit))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.75)))
    }
}

struct CareReplySheet: View {
    let friendName: String
    let originalBody: String
    let onSend: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSending = false
    @State private var errorText: String?

    private let presets = [
        "我看到啦,谢谢你惦记我 ❤️",
        "收到你的心跳啦,我也在想你",
        "我现在还好,晚点和你说",
    ]

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("回应 \(friendName)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(TempoTheme.primaryText)
                        Text("“\(originalBody)”")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TempoTheme.secondaryText)
                            .lineLimit(3)
                    }

                    VStack(spacing: 8) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                message = preset
                            } label: {
                                HStack {
                                    Text(LocalizedStringKey(preset))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(TempoTheme.primaryText)
                                    Spacer()
                                    Image(systemName: message == preset ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(message == preset ? TempoTheme.care : TempoTheme.tertiaryText)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(message == preset ? TempoTheme.care.opacity(0.10) : Color.white)
                                )
                            }
                            .buttonStyle(.tempoPress)
                        }
                    }

                    TextField("也可以写一句自己的话", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TempoTheme.danger)
                    }

                    Button {
                        Task { await send() }
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().tint(.white)
                            } else {
                                Label("发送回应", systemImage: "paperplane.fill")
                                    .font(.system(size: 14, weight: .heavy))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(TempoTheme.buttonGradient))
                    }
                    .buttonStyle(.tempoPress(.medium))
                    .disabled(trimmedMessage.isEmpty || isSending)
                }
                .padding(20)
            }
            .background(TempoTheme.background)
            .navigationTitle("回应关怀")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .buttonStyle(.tempoPress)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        guard !trimmedMessage.isEmpty, !isSending else { return }
        isSending = true
        errorText = nil
        do {
            try await onSend(trimmedMessage)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            dismiss()
        } catch {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            errorText = error.localizedDescription
            isSending = false
        }
    }
}

struct CarePanelSelfCareCard: View {
    let onBreathing: () -> Void
    let onMeditation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.accent)
                Text("自我关怀")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
            }
            Text("也给自己留一点安静的时间。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(spacing: 10) {
                selfCareButton(
                    icon: "wind",
                    title: "立即呼吸",
                    subtitle: "共振 5.5 BPM",
                    colors: [TempoTheme.breathing, TempoTheme.care],
                    accessibilityLabel: "立即开始共振呼吸",
                    accessibilityHint: "以 5.5 次每分钟节奏呼吸,放松心率",
                    action: onBreathing
                )
                selfCareButton(
                    icon: "leaf.fill",
                    title: "立即冥想",
                    subtitle: "5-20 分钟",
                    colors: [TempoTheme.meditation, TempoTheme.meditationDark],
                    accessibilityLabel: "立即开始冥想",
                    accessibilityHint: "可选 5 到 20 分钟,写入 Apple Health 正念时长",
                    action: onMeditation
                )
            }
        }
        .tempoCard(radius: 18, padding: 14)
    }

    private func selfCareButton(
        icon: String,
        title: String,
        subtitle: String,
        colors: [Color],
        accessibilityLabel: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.tempoPress)
    }
}

struct CarePanelSentToastView: View {
    let kind: CarePanelView.SentKind

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(TempoTheme.success)
            Text(LocalizedStringKey(label))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(TempoTheme.success)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Capsule().fill(TempoTheme.successSoft))
    }

    private var label: String {
        switch kind {
        case .heartbeat: "我在已发送 ❤️"
        case .encourage: "鼓励已发送 ✨"
        case .breathingInvite: "呼吸邀请已发送 🌬️"
        case .meditationInvite: "冥想邀请已发送 🧘"
        case .checkLater: "已提醒你稍后回看"
        }
    }
}

struct FriendHeroCard: View {
    let friend: Friend
    let relationship: String?
    let isMuted: Bool
    let activeAlertCount: Int
    var onEditRelationship: () -> Void

    @State private var pulse = false

    private var ringColor: Color {
        friend.levelColor
    }

    private var hasAlert: Bool { activeAlertCount > 0 }

    var body: some View {
        VStack(spacing: 12) {
            avatarAura
                .frame(height: 260)
                .padding(.top, 22)

            nameBlock
            stressBlock
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: hasAlert ? 1.4 : 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var avatarAura: some View {
        ZStack {
            Circle()
                .fill(ringColor.opacity(hasAlert ? 0.30 : 0.15))
                .frame(width: 220, height: 220)
                .blur(radius: 32)
                .opacity(pulse ? 1.0 : 0.66)
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: 1)
                .frame(width: 180, height: 180)
            Circle()
                .stroke(ringColor.opacity(0.4), lineWidth: 1)
                .frame(width: 150, height: 150)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [ringColor.opacity(0.85), ringColor.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 110, height: 110)
                .shadow(color: ringColor.opacity(0.4), radius: 18, y: 6)
                .opacity(pulse ? 1.0 : 0.92)
            Text(String(friend.displayName.prefix(1)))
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            if hasAlert {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(Circle().fill(TempoTheme.danger))
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .offset(x: 36, y: -36)
            }
        }
    }

    private var nameBlock: some View {
        VStack(spacing: 4) {
            Text(friend.displayName)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Button(action: onEditRelationship) {
                if let relationship, !relationship.isEmpty {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(relationship))
                            .font(.system(size: 11, weight: .heavy))
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(ringColor.opacity(0.85)))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 9))
                        Text("设置关系")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(TempoTheme.tertiaryText.opacity(0.10)))
                }
            }
            .buttonStyle(.tempoPress)
            .accessibilityLabel(relationship?.isEmpty == false ? "关系:\(relationship ?? "")" : "设置关系标签")
            .accessibilityHint("点击选择对 Ta 的称呼,如妈妈、宝贝")
        }
    }

    private var stressBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(ringColor).frame(width: 8, height: 8)
                Text(LocalizedStringKey(friend.levelDisplay))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TempoTheme.secondaryText)
                    .kerning(0.6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
            )

            HStack(alignment: .bottom, spacing: 2) {
                Text("\(friend.stressScore)")
                    .font(.system(size: 70, weight: .black, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                    .contentTransition(.numericText())
                Text("/100")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .padding(.bottom, 10)
            }
            Text(friend.formattedLastUpdated)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
    }
}

struct FriendPlaceholderHero: View {
    var addFriendAction: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            emptyStateHero
                .frame(height: 260)
                .padding(.top, 22)

            intro
            actionsPreview
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var emptyStateHero: some View {
        ZStack {
            Circle()
                .fill(TempoTheme.accent.opacity(0.15))
                .frame(width: 220, height: 220)
                .blur(radius: 32)
                .opacity(pulse ? 1.0 : 0.66)
            Circle()
                .stroke(TempoTheme.accent.opacity(0.2), lineWidth: 1)
                .frame(width: 180, height: 180)
            Circle()
                .stroke(TempoTheme.accent.opacity(0.4), lineWidth: 1)
                .frame(width: 150, height: 150)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.pink, TempoTheme.breathing],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 110, height: 110)
                .shadow(color: Color.pink.opacity(0.4), radius: 18, y: 6)
                .opacity(pulse ? 1.0 : 0.92)
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white)
        }
    }

    private var intro: some View {
        VStack(spacing: 6) {
            Text("还没绑定密友")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Text("绑定家人 / 朋友后,Ta 状态不好你立刻知道 — 轻轻拍一下、写句话、稍后回看。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
            Button(action: addFriendAction) {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("立即添加密友")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.pink, TempoTheme.breathing],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .shadow(color: Color.pink.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.tempoPress)
            .accessibilityLabel("添加密友")
            .accessibilityHint("打开共振设置,输入对方共振 ID")
            .padding(.top, 6)
        }
    }

    private var actionsPreview: some View {
        VStack(spacing: 8) {
            Text("绑定后,可对 Ta 做")
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(spacing: 10) {
                sampleActionPreview(icon: "heart.circle.fill", title: "我在", color: .pink)
                sampleActionPreview(icon: "clock.badge.checkmark.fill", title: "回看", color: TempoTheme.accent)
                sampleActionPreview(icon: "bubble.left.fill", title: "说句话", color: TempoTheme.alert)
                sampleActionPreview(icon: "envelope.fill", title: "写鼓励", color: TempoTheme.alert)
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 8)
    }

    private func sampleActionPreview(icon: String, title: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color.opacity(0.6))
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TempoTheme.tertiaryText.opacity(0.06))
        )
    }
}
