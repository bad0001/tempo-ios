//
//  PendingFriendRequestBanner.swift
//  Tempo
//
//  首页 / 顶部显眼提醒卡 — 收到密友邀请时显示,点击直跳「共振设置 → 待处理请求」.
//  不打扰、有未读才出现.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PendingFriendRequestBanner: View {
    @State private var service = FriendsService.shared

    var body: some View {
        if service.pendingFriendRequestCount > 0 {
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                NotificationCenter.default.post(
                    name: .tempoOpenResonantSettings,
                    object: nil,
                    userInfo: [:]
                )
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 44, height: 44)
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                            .offset(x: 14, y: -14)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("收到 \(service.pendingFriendRequestCount) 条密友邀请")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                        Text("点击查看,接受后双方互相关怀")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.pink, TempoTheme.breathing],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.pink.opacity(0.35), radius: 14, y: 8)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.tempoPress(.medium))
            .accessibilityLabel("收到 \(service.pendingFriendRequestCount) 条密友邀请")
            .accessibilityHint("点击进入共振设置查看并接受")
        }
    }
}
