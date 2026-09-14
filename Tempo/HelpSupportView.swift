//
//  HelpSupportView.swift
//  Tempo
//
//  帮助、支持与诊断信息。
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copiedDiagnostics = false

    private var diagnosticsText: String {
        let session = TempoSession.shared
        let friends = FriendsService.shared
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return [
            "Tempo \(version) (\(build))",
            "LoggedIn: \(session.isLoggedIn)",
            "PublicId: \(session.publicId ?? "-")",
            "Friends: \(friends.friends.count)",
            "Pending: \(friends.pendingFriendRequestCount)",
            "SharingStress: \(friends.sharingMyStress)"
        ].joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsSheetHeader(
                        icon: "questionmark.circle.fill",
                        color: TempoTheme.warning,
                        title: "帮助与支持",
                        subtitle: "联系、诊断和常见问题"
                    )

                    VStack(spacing: 0) {
                        if let mailURL = URL(string: "mailto:ursgu@outlook.com") {
                            Link(destination: mailURL) {
                                SettingsNavigationRow(
                                    icon: "envelope.fill",
                                    iconColor: TempoTheme.accent,
                                    title: "发邮件",
                                    subtitle: "ursgu@outlook.com"
                                )
                            }
                            .buttonStyle(.tempoPress)
                        }

                        Divider().padding(.leading, 68)

                        Button {
                            copyDiagnostics()
                        } label: {
                            SettingsNavigationRow(
                                icon: copiedDiagnostics ? "checkmark.circle.fill" : "doc.on.doc.fill",
                                iconColor: copiedDiagnostics ? TempoTheme.success : TempoTheme.warning,
                                title: copiedDiagnostics ? "已复制诊断信息" : "复制诊断信息",
                                subtitle: "登录、密友、版本"
                            )
                        }
                        .buttonStyle(.tempoPress)
                    }
                    .settingsPanel()

                    VStack(spacing: 10) {
                        HelpFAQCard(
                            icon: "applewatch.watchface",
                            color: TempoTheme.accent,
                            title: "Apple Watch 没数据",
                            answer: "确认 Watch 上已安装 Tempo,并在 iPhone 的健康权限里允许读取心率、HRV、睡眠和正念。"
                        )
                        HelpFAQCard(
                            icon: "heart.text.square.fill",
                            color: Color.pink,
                            title: "密友看不到压力",
                            answer: "先在「我的」页点刷新共振状态。若仍为空,让双方都打开一次 Tempo,服务器会同步最近压力摘要。"
                        )
                        HelpFAQCard(
                            icon: "bell.slash.fill",
                            color: TempoTheme.warning,
                            title: "静音后还会收到吗",
                            answer: "会接收进关怀面板,但首页提醒、气泡、震动和系统推送都会停止。"
                        )
                        HelpFAQCard(
                            icon: "lock.shield.fill",
                            color: TempoTheme.success,
                            title: "这不是医疗诊断",
                            answer: "Tempo 用于日常压力觉察和关怀提醒,不能替代医生、诊断或治疗建议。"
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("帮助与支持")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func copyDiagnostics() {
        #if canImport(UIKit)
        UIPasteboard.general.string = diagnosticsText
        #endif
        withAnimation(.easeInOut(duration: 0.16)) {
            copiedDiagnostics = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.16)) {
                copiedDiagnostics = false
            }
        }
    }
}

private struct HelpFAQCard: View {
    let icon: String
    let color: Color
    let title: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
            }
            Text(LocalizedStringKey(answer))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tempoCard(radius: 18, padding: 14)
    }
}
