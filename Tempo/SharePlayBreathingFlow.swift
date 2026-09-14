//
//  SharePlayBreathingFlow.swift
//  Tempo
//
//  共振呼吸 SharePlay 模式 UI 流程.
//  通过 FaceTime 通话激活 GroupSession,Apple 服务器中继消息,远程也能用.
//

import SwiftUI
import GroupActivities
import TempoCore

struct SharePlayBreathingFlow: View {
    @State private var session = ResonantSharePlaySession()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()

                Group {
                    switch session.status {
                    case .idle, .preparing, .error:
                        SharePlayLobby(session: session)
                    case .joined:
                        SharePlayConnected(session: session)
                    case .running:
                        SharePlayRunning(session: session)
                    case .finished:
                        SharePlayFinished(session: session, onDismiss: { dismiss() })
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("共振呼吸 SharePlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        session.leave()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                session.leave()
            }
        }
    }
}

// MARK: - Lobby

private struct SharePlayLobby: View {
    let session: ResonantSharePlaySession

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "8B5CF6").opacity(0.18), Color(hex: "60A5FA").opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 30)
                Image(systemName: "video.fill")
                    .font(.system(size: 70, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "8B5CF6"), Color(hex: "60A5FA")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 10) {
                Text("先打 FaceTime 通话")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("FaceTime 通话中(可静音),点下方按钮启动 SharePlay")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            stepsHint

            if let error = session.lastError {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Button {
                Task { await session.activate() }
            } label: {
                HStack(spacing: 8) {
                    if session.status == .preparing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "shareplay")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(LocalizedStringKey(session.status == .preparing ? "启动中..." : "开始 SharePlay"))
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(hex: "8B5CF6"), Color(hex: "60A5FA")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .shadow(color: Color(hex: "8B5CF6").opacity(0.35), radius: 14, y: 8)
            }
            .buttonStyle(.tempoPress)
            .disabled(session.status == .preparing)
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private var stepsHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            HintRow(num: "1", text: "在 FaceTime 中给好友打通话(可静音视频)")
            HintRow(num: "2", text: "通话中,双方都打开 Tempo,点这里「开始 SharePlay」")
            HintRow(num: "3", text: "iOS 弹窗,双方都点接受 → 进入连接")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        )
    }
}

private struct HintRow: View {
    let num: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(hex: "8B5CF6")))
            Text(LocalizedStringKey(text))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Connected (选模式 / 等开始)

private struct SharePlayConnected: View {
    let session: ResonantSharePlaySession
    @State private var pickedPattern: BreathingPattern = .fourSevenEight

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            HStack(spacing: 18) {
                ForEach(0..<session.participantCount, id: \.self) { _ in
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "8B5CF6"), Color(hex: "60A5FA")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }

            VStack(spacing: 6) {
                Text("已加入 SharePlay")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.success)
                Text("当前 \(session.participantCount) 人在线 · \(session.isLeader ? "你来选" : "等对方选")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }

            if session.isLeader {
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
                    session.startBreathing(pattern: pickedPattern)
                } label: {
                    Text("一起开始")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Capsule().fill(
                                LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "60A5FA")], startPoint: .leading, endPoint: .trailing)
                            )
                        )
                        .shadow(color: Color(hex: "8B5CF6").opacity(0.35), radius: 14, y: 8)
                }
                .buttonStyle(.tempoPress)
            } else {
                VStack(spacing: 8) {
                    ProgressView().tint(Color(hex: "8B5CF6"))
                    Text("等待对方选呼吸模式...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Running

private struct SharePlayRunning: View {
    let session: ResonantSharePlaySession
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
                    StatTilePair(label: "在线", value: "\(session.participantCount) 人")
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

// MARK: - Finished

private struct SharePlayFinished: View {
    let session: ResonantSharePlaySession
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
                Text("通过 SharePlay 和 \(session.participantCount) 人共振")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
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
