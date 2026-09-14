//
//  ResonantBreathingViews.swift
//  Tempo
//
//  共振呼吸 UI:Lobby(创建房间 / 加入房间)+ Session(同步呼吸训练).
//

import SwiftUI
import Network
import TempoCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Root: Lobby + Session 一体化

struct ResonantBreathingFlow: View {
    @State private var session = ResonantSession()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()

                Group {
                    switch session.status {
                    case .idle, .advertising, .browsing, .connecting:
                        LobbyContent(session: session)
                    case .connected:
                        ConnectedContent(session: session)
                    case .running:
                        ResonantSessionContent(session: session)
                    case .finished:
                        FinishedContent(session: session, onDismiss: { dismiss() })
                    case .error:
                        ErrorContent(session: session)
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("共振呼吸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        session.stopAll()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                session.stopAll()
            }
        }
    }
}

// MARK: - Lobby (idle / advertising / browsing / connecting)

private struct LobbyContent: View {
    let session: ResonantSession

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "8B5CF6").opacity(0.18), Color(hex: "EC4899").opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 30)
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "8B5CF6"), Color(hex: "EC4899")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 6) {
                Text(LocalizedStringKey(headerTitle))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(headerSubtitle))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch session.status {
            case .idle:
                VStack(spacing: 14) {
                    experimentalBanner
                    modePickerButtons
                }
            case .advertising:
                advertisingState
            case .browsing:
                browsingState
            case .connecting:
                connectingState
            default:
                EmptyView()
            }

            Spacer()
        }
    }

    private var experimentalBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flask.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "F97316"))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("实验中功能")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color(hex: "EA580C"))
                Text("部分网络环境下两台手机可能连不上。如握手失败,可改用「共振关怀」从 Profile 远程互相关怀。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "FED7AA").opacity(0.45))
        )
        .padding(.horizontal, 24)
    }

    private var connectingState: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().tint(TempoTheme.accent)
                Text("握手中...")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.secondaryText)
            }
            if let diag = session.lastDiagnostic {
                Text(diag)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            DiagnosticDisclosure()
            Button {
                session.stopAll()
            } label: {
                Text("取消")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.danger)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(TempoTheme.dangerSoft))
            }
            .buttonStyle(.tempoPress)
        }
    }

    private var headerTitle: String {
        switch session.status {
        case .idle: "和好友一起呼吸"
        case .advertising: "等待好友连接"
        case .browsing: "搜索附近设备"
        case .connecting: "正在连接"
        default: ""
        }
    }

    private var headerSubtitle: String {
        switch session.status {
        case .idle: "通过本地网络同步呼吸节奏,适合伴侣 / 朋友放松。"
        case .advertising: "把这个屏幕给对方看,让对方搜索你。"
        case .browsing: "确保对方已开启「等待连接」。"
        case .connecting: "马上就好"
        default: ""
        }
    }

    private var modePickerButtons: some View {
        VStack(spacing: 12) {
            Button {
                session.startHosting()
            } label: {
                actionLabel(
                    icon: "wave.3.right",
                    title: "等待好友连接",
                    subtitle: "我先开,让对方找我",
                    primary: true
                )
            }
            .buttonStyle(.tempoPress)

            Button {
                session.startBrowsing()
            } label: {
                actionLabel(
                    icon: "magnifyingglass",
                    title: "搜索附近设备",
                    subtitle: "对方已开始,我加入",
                    primary: false
                )
            }
            .buttonStyle(.tempoPress)
        }
        .padding(.horizontal, 16)
    }

    private func actionLabel(icon: String, title: String, subtitle: String, primary: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(primary ? .white : Color(hex: "8B5CF6"))
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(primary ? Color(hex: "8B5CF6") : Color(hex: "8B5CF6").opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .tempoCard(radius: 18, padding: 14)
    }

    private var advertisingState: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ProgressView().tint(Color(hex: "8B5CF6"))
                Text("等待邀请中...")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.secondaryText)
            }
            Text("对方搜索后,你会收到加入请求")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)

            DiagnosticDisclosure()

            Button {
                session.stopAll()
            } label: {
                Text("取消")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.danger)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(TempoTheme.dangerSoft))
            }
            .buttonStyle(.tempoPress)
        }
    }

    private var browsingState: some View {
        VStack(spacing: 14) {
            if session.foundPeers.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(Color(hex: "8B5CF6"))
                    Text("搜索附近设备...")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(TempoTheme.secondaryText)
                }
                DiagnosticDisclosure()
            } else {
                VStack(spacing: 10) {
                    Text("找到 \(session.foundPeers.count) 台设备")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                    ForEach(session.foundPeers) { peer in
                        Button {
                            session.connect(to: peer)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "iphone.gen3")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color(hex: "8B5CF6"))
                                Text(peer.displayName)
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(TempoTheme.primaryText)
                                Spacer()
                                Text("连接")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color(hex: "8B5CF6")))
                            }
                            .tempoCard(radius: 16, padding: 12)
                        }
                        .buttonStyle(.tempoPress)
                    }
                }
            }
            Button {
                session.stopAll()
            } label: {
                Text("取消")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.danger)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(TempoTheme.dangerSoft))
            }
            .buttonStyle(.tempoPress)
        }
    }
}

// MARK: - Connected: 等开始

private struct ConnectedContent: View {
    let session: ResonantSession
    @State private var pickedPattern: BreathingPattern = .fourSevenEight

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            HStack(spacing: 32) {
                peerAvatar(name: session.myDeviceName, isMe: true)
                Image(systemName: "wave.3.left.and.wave.3.right")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(TempoTheme.success)
                    .symbolEffect(.pulse, options: .repeating)
                if let other = session.connectedPeerName {
                    peerAvatar(name: other, isMe: false)
                }
            }

            Text("已连接")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(TempoTheme.success)

            if session.role == .host {
                VStack(spacing: 14) {
                    Text("选个呼吸模式")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.tertiaryText)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(BreathingPattern.allPresets) { pattern in
                                let selected = pattern.id == pickedPattern.id
                                Button {
                                    pickedPattern = pattern
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(LocalizedStringKey(pattern.displayName))
                                            .font(.system(size: 14, weight: .heavy))
                                            .foregroundStyle(TempoTheme.primaryText)
                                        Spacer()
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color(hex: "8B5CF6"))
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(selected ? Color(hex: "8B5CF6") : Color.clear, lineWidth: 2)
                                            )
                                    )
                                }
                                .buttonStyle(.tempoPress)
                            }
                        }
                    }
                    .frame(maxHeight: 240)

                    Button {
                        session.startBreathingSession(pattern: pickedPattern)
                    } label: {
                        Text("一起开始")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                Capsule().fill(
                                    LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "EC4899")], startPoint: .leading, endPoint: .trailing)
                                )
                            )
                            .shadow(color: Color(hex: "8B5CF6").opacity(0.35), radius: 14, y: 8)
                    }
                    .buttonStyle(.tempoPress)
                }
                .padding(.horizontal, 4)
            } else {
                VStack(spacing: 8) {
                    ProgressView().tint(Color(hex: "8B5CF6"))
                    Text("等待对方选择呼吸模式...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }

            Spacer()
        }
    }

    private func peerAvatar(name: String, isMe: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isMe
                                ? [Color(hex: "8B5CF6"), Color(hex: "6366F1")]
                                : [Color(hex: "EC4899"), Color(hex: "F97316")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: "person.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
            }
            Text(isMe ? "我" : name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TempoTheme.primaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - Running: 同步呼吸

private struct ResonantSessionContent: View {
    let session: ResonantSession
    @State private var scale: CGFloat = 0.45

    private var phaseColor: Color {
        switch session.sessionPhase {
        case "inhale": return TempoTheme.accent
        case "hold1": return Color(hex: "8B5CF6")
        case "exhale": return Color(hex: "EC4899")
        case "hold2": return Color(hex: "F59E0B")
        default: return TempoTheme.tertiaryText
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, phaseColor.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: session.sessionPhase)

            ResonantCircle(scale: scale, color: phaseColor)

            VStack(spacing: 12) {
                Text(LocalizedStringKey(session.sessionPhaseLabel))
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)

                Text("\(session.sessionRemaining)")
                    .font(.system(size: 96, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }

            VStack {
                Spacer()
                HStack(spacing: 32) {
                    StatTilePair(label: "循环", value: "\(session.sessionCycle)/\(session.sessionTargetCycles)")
                    StatTilePair(label: "搭档", value: session.connectedPeerName ?? "—")
                    StatTilePair(label: "模式", value: session.sessionPattern?.displayName ?? "—")
                }
                .padding(.bottom, 60)
            }
        }
        .onChange(of: session.sessionPhase) { _, new in
            withAnimation(.easeInOut(duration: 0.6)) {
                if new == "inhale" || new == "hold1" {
                    scale = 1.0
                } else if new == "exhale" || new == "hold2" {
                    scale = 0.45
                }
            }
        }
    }
}

struct ResonantCircle: View {
    let scale: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.5))
                .scaleEffect(scale)
                .blur(radius: 30)
            Circle()
                .stroke(color.opacity(0.7), lineWidth: 2)
                .scaleEffect(scale)
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 1)
                .scaleEffect(scale * 1.18)
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 1)
                .scaleEffect(scale * 1.36)
        }
        .frame(width: 280, height: 280)
        .animation(.easeInOut(duration: 0.6), value: scale)
    }
}

struct StatTilePair: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(LocalizedStringKey(label))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Finished

private struct FinishedContent: View {
    let session: ResonantSession
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(TempoTheme.success.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(TempoTheme.success)
            }

            VStack(spacing: 6) {
                Text("一起完成 ✨")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("和 \(session.connectedPeerName ?? "好友") 完成共振呼吸")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
            }

            HStack(spacing: 32) {
                StatTileSummary(label: "循环", value: "\(session.sessionCycle)")
                StatTileSummary(label: "模式", value: session.sessionPattern?.displayName ?? "—")
            }

            Button(action: onDismiss) {
                Text("完成")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(TempoTheme.buttonGradient))
                    .shadow(color: TempoTheme.accent.opacity(0.3), radius: 12, y: 6)
            }
            .buttonStyle(.tempoPress)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }
}

private struct StatTileSummary: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(TempoTheme.primaryText)
            Text(LocalizedStringKey(label))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .frame(width: 90)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        )
    }
}

// MARK: - Error

private struct ErrorContent: View {
    let session: ResonantSession

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(TempoTheme.danger)
            Text("连接出错")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Text(session.lastError ?? "未知错误")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                session.stopAll()
            } label: {
                Text("重试")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(TempoTheme.accent))
            }
            .buttonStyle(.tempoPress)
        }
        .padding(40)
    }
}

// MARK: - Diagnostic Disclosure (帮助连不上的用户排查)

private struct DiagnosticDisclosure: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(TempoTheme.warning)
                    Text("找不到对方?点开看排查")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
            .buttonStyle(.tempoPress)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().padding(.vertical, 8)
                    DiagnosticRow(text: "两台手机都打开 Tempo,进入「共振空间 → 共振呼吸」")
                    DiagnosticRow(text: "一台点「等待好友连接」,另一台点「搜索附近设备」")
                    DiagnosticRow(text: "两台手机连同一个 Wi-Fi,距离 < 10 米")
                    DiagnosticRow(text: "蓝牙都打开")
                    DiagnosticRow(text: "首次连接会弹「允许 Tempo 访问本地网络」,记得点允许")

                    #if canImport(UIKit)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("打开设置 → Tempo → 本地网络")
                                .font(.system(size: 12, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(TempoTheme.accent))
                    }
                    .buttonStyle(.tempoPress)
                    .padding(.top, 6)
                    #endif
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TempoTheme.warningSoft.opacity(0.5))
        )
        .padding(.horizontal, 8)
    }
}

private struct DiagnosticRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
            Text(LocalizedStringKey(text))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
