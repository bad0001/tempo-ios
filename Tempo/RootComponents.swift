//
//  RootComponents.swift
//  Tempo
//
//  App 根层共享的浮层、背景和自定义 tab bar。
//

import Foundation
import SwiftUI

/// 全 App 统一的数据生命周期。页面保留已有内容时，刷新失败进入 cached，
/// 只有完全没有可展示内容时才进入 failed，避免网络波动把页面清空。
enum TempoLoadState: Equatable {
    case idle
    case loading
    case ready(Date)
    case cached(Date?)
    case empty
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isRecoveryState: Bool {
        switch self {
        case .cached, .failed: return true
        default: return false
        }
    }
}

enum TempoErrorCopy {
    static func representsNoData(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("no data available")
            || text.contains("specified predicate")
            || text.contains("no samples")
    }

    static func message(for error: Error, fallback: String = "数据暂时没有加载成功，请稍后重试。") -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty,
           !representsNoData(error) {
            return description
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "网络连接暂时不可用，请检查网络后重试。"
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("not authorized") || text.contains("permission") {
            return "请检查 Apple 健康读取权限后重试。"
        }
        return fallback
    }
}

/// 加载 / 空数据 / 网络错误 / 离线缓存 / 重试的统一呈现。
/// ready 默认不占空间；业务内容继续原位显示，不用为了刷新闪白屏。
struct TempoDataStateView: View {
    let state: TempoLoadState
    var loadingTitle = "正在加载"
    var emptyTitle = "暂无数据"
    var emptyDetail = "有新数据后会自动出现在这里。"
    var cachedTitle = "正在显示上次内容"
    var cachedDetailOverride: String?
    var showsEmpty = true
    var onRetry: (() -> Void)?
    @State private var showsRecoveryConfirmation = false

    var body: some View {
        Group {
            stateContent
        }
        .onChange(of: state) { oldState, newState in
            guard oldState.isRecoveryState, case .ready = newState else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showsRecoveryConfirmation = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsRecoveryConfirmation = false
                }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle:
            EmptyView()
        case .ready:
            if showsRecoveryConfirmation {
                stateCard(
                    icon: "checkmark.circle.fill",
                    color: TempoTheme.success,
                    title: "已恢复更新",
                    detail: "当前内容已经同步到最新状态。",
                    showsProgress: false,
                    showsRetry: false
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        case .loading:
            stateCard(
                icon: "arrow.triangle.2.circlepath",
                color: TempoTheme.accent,
                title: loadingTitle,
                detail: "请稍候，已有内容会继续保留。",
                showsProgress: true,
                showsRetry: false
            )
        case .cached(let updatedAt):
            stateCard(
                icon: "wifi.slash",
                color: TempoTheme.warning,
                title: cachedTitle,
                detail: cachedDetailOverride ?? cachedDetail(updatedAt),
                showsProgress: false,
                showsRetry: true
            )
        case .empty:
            if showsEmpty {
                stateCard(
                    icon: "tray",
                    color: TempoTheme.accent,
                    title: emptyTitle,
                    detail: emptyDetail,
                    showsProgress: false,
                    showsRetry: onRetry != nil
                )
            }
        case .failed(let message):
            stateCard(
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                color: TempoTheme.danger,
                title: "暂时没有加载成功",
                detail: message,
                showsProgress: false,
                showsRetry: true
            )
        }
    }

    private func cachedDetail(_ updatedAt: Date?) -> String {
        guard let updatedAt else {
            return "当前网络不可用，内容来自本机缓存。"
        }
        return "当前网络不可用，显示 \(relativeText(from: updatedAt)) 保存的内容。"
    }

    private func relativeText(from date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 { return "刚刚" }
        if interval < 3_600 { return "(Int(interval / 60)) 分钟前" }
        if interval < 86_400 { return "(Int(interval / 3_600)) 小时前" }
        return "(Int(interval / 86_400)) 天前"
    }

    private func stateCard(
        icon: String,
        color: Color,
        title: String,
        detail: String,
        showsProgress: Bool,
        showsRetry: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                if showsProgress {
                    ProgressView()
                        .tint(color)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(color)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(detail))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if showsRetry, let onRetry {
                Button("重试", action: onRetry)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(color.opacity(0.11)))
                    .buttonStyle(.tempoPress)
                    .accessibilityHint("重新加载当前内容")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 18, padding: 14)
    }
}

struct CarePanelTrigger: Identifiable {
    let id = UUID()
    let friendID: String?
}

struct CareEventToast: Identifiable, Equatable {
    let id: String
    let fromName: String
    let body: String
    let icon: String
}

struct CareEventToastView: View {
    let toast: CareEventToast
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.16))
                        .frame(width: 46, height: 46)
                    Image(systemName: toast.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.pink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.fromName)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(toast.body)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.pink.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.pink.opacity(0.18), radius: 18, y: 8)
            )
        }
        .buttonStyle(.tempoPress)
    }
}

struct BackgroundAura: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(TempoTheme.accent.opacity(0.18))
                    .blur(radius: 80)
                    .frame(width: 400, height: 400)
                    .position(x: proxy.size.width * 0.0, y: proxy.size.height * 0.05)
                Circle()
                    .fill(TempoTheme.success.opacity(0.10))
                    .blur(radius: 80)
                    .frame(width: 300, height: 300)
                    .position(x: proxy.size.width * 1.0, y: proxy.size.height * 0.25)
            }
        }
    }
}

/// 固定在窗口顶部的柔和材质层。滚动内容进入状态栏区域时会逐渐模糊、褪去，
/// 页面停在顶部时则只留下很轻的环境光，不占用布局也不拦截手势。
struct TopScrollFadeLayer: View {
    var tint: Color = TempoTheme.background

    var body: some View {
        GeometryReader { proxy in
            let fadeHeight = proxy.safeAreaInsets.top + 58
            VStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            tint.opacity(0.88),
                            tint.opacity(0.54),
                            tint.opacity(0.10),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.00),
                            .init(color: .black.opacity(0.96), location: 0.40),
                            .init(color: .black.opacity(0.50), location: 0.74),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: fadeHeight)

                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FloatingTabBar: View {
    @Binding var selection: TempoTab

    private struct Item: Hashable {
        let tab: TempoTab
        let symbol: String
        let label: String
    }

    private let items: [Item] = [
        Item(tab: .home,    symbol: "house.fill",                  label: "今日"),
        Item(tab: .trends,  symbol: "chart.line.uptrend.xyaxis",   label: "趋势"),
        Item(tab: .breathe, symbol: "person.2.wave.2.fill",        label: "共振"),
        Item(tab: .profile, symbol: "person.fill",                 label: "我的"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item.tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selection = item.tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        Text(LocalizedStringKey(item.label))
                            .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                    }
                    .foregroundStyle(isSelected ? TempoTheme.accent : TempoTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .fill(TempoTheme.accentSoft)
                            }
                        }
                    )
                }
                .buttonStyle(.tempoPress)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }
}
