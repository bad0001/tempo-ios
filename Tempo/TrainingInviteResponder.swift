//
//  TrainingInviteResponder.swift
//  Tempo
//
//  接收方收到密友的呼吸 / 冥想邀请后,点击通知 → 弹这个 sheet:
//   ① 显示邀请人 + 时长
//   ② 「现在开始」→ 进入实际训练 view
//   ③ 训练完成 → 自动给邀请方发 sessionCompleted 事件(回执)
//

import SwiftUI
import os
import TempoCore

struct PendingTrainingInvite: Identifiable, Hashable {
    let id = UUID()
    let type: ResonantEventType
    let minutes: Int
    let fromName: String
    let eventID: String
}

struct TrainingInviteResponderSheet: View {
    let invite: PendingTrainingInvite
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .ready
    @State private var sessionCompleted: Bool = false

    enum Phase {
        case ready
        case running
    }

    var body: some View {
        Group {
            switch phase {
            case .ready: readyView
            case .running: runningView
            }
        }
        .background(TempoTheme.background)
    }

    private var readyView: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer().frame(height: 12)
                ZStack {
                    Circle()
                        .fill(typeColor.opacity(0.18))
                        .blur(radius: 24)
                        .frame(width: 200, height: 200)
                    Image(systemName: invite.type.icon)
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: typeGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                VStack(spacing: 8) {
                    Text("\(invite.fromName) 邀请你")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                    Text(invitePromptText)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                        .multilineTextAlignment(.center)
                    Text(inviteSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(spacing: 10) {
                    Button {
                        withAnimation { phase = .running }
                    } label: {
                        Text("现在开始")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: typeGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            )
                            .shadow(color: typeColor.opacity(0.35), radius: 14, y: 8)
                    }
                    .buttonStyle(.tempoPress)
                    Button {
                        dismiss()
                    } label: {
                        Text("稍后再说")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(TempoTheme.tertiaryText)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.tempoPress)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationTitle("收到邀请")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var runningView: some View {
        switch invite.type {
        case .breathingInvite:
            BreathingSessionView(pattern: .resonant)
                .interactiveDismissDisabled(false)
                .onDisappear {
                    if !sessionCompleted {
                        sessionCompleted = true
                        Task { await sendCompletion() }
                    }
                    dismiss()
                }
        case .meditationInvite:
            MeditationFlow()
                .onDisappear {
                    if !sessionCompleted {
                        sessionCompleted = true
                        Task { await sendCompletion() }
                    }
                    dismiss()
                }
        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var typeGradient: [Color] {
        switch invite.type {
        case .breathingInvite: [Color(hex: "8B5CF6"), Color(hex: "EC4899")]
        case .meditationInvite: [Color(hex: "10B981"), Color(hex: "059669")]
        default: [TempoTheme.accent, TempoTheme.accentLight]
        }
    }

    private var typeColor: Color {
        typeGradient.first ?? TempoTheme.accent
    }

    private var invitePromptText: String {
        switch invite.type {
        case .breathingInvite: "做 \(invite.minutes) 分钟呼吸"
        case .meditationInvite: "坐 \(invite.minutes) 分钟冥想"
        default: "训练"
        }
    }

    private var inviteSubtitle: String {
        switch invite.type {
        case .breathingInvite: "跟 Ta 一起放松,不用同时开始,什么时候做都可以"
        case .meditationInvite: "找一个安静的地方,跟 Ta 一起静一下"
        default: ""
        }
    }

    /// 训练完成后,给邀请人发回执
    private func sendCompletion() async {
        let inviterName = invite.fromName
        // 反查 friend(按 displayName 匹配)
        guard let inviterFriend = FriendsService.shared.friends.first(where: { $0.displayName == inviterName }) else {
            TempoLog.care.debug("no matching friend for completion receipt: \(inviterName)")
            return
        }
        let kind = invite.type == .breathingInvite ? "breathing" : "meditation"
        try? await FriendsService.shared.sendResonantEvent(
            to: inviterFriend,
            type: .sessionCompleted,
            payload: [
                "kind": kind,
                "minutes": "\(invite.minutes)",
                "originalEventID": invite.eventID,
            ]
        )
        TempoLog.care.debug("sent completion receipt to \(inviterName)")
    }
}
