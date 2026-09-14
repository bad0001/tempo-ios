//
//  ResonantSharePlay.swift
//  Tempo
//
//  共振呼吸 SharePlay 实现 — 通过 FaceTime 通话中的 GroupSession 同步呼吸节奏.
//  优势:Apple 服务器中继,任何网络都行;不依赖本地 P2P / Bonjour / AWDL.
//  限制:需要双方在 FaceTime 通话中(可静音).
//

import Foundation
import Combine
import GroupActivities
import SwiftUI
import TempoCore

// MARK: - Group Activity

struct BreathingGroupActivity: GroupActivity {
    static let activityIdentifier = "com.ayipocket.tempo.resonant-breathing"

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "共振呼吸"
        meta.subtitle = "和好友同步呼吸节奏"
        meta.type = .generic
        return meta
    }
}

// MARK: - Session

@MainActor
@Observable
final class ResonantSharePlaySession {
    enum Status: Equatable {
        case idle, preparing, joined, running, finished, error
    }

    typealias Message = ResonantSession.Message

    @ObservationIgnored
    private var groupSession: GroupSession<BreathingGroupActivity>?
    @ObservationIgnored
    private var messenger: GroupSessionMessenger?
    @ObservationIgnored
    private var observerTask: Task<Void, Never>?
    @ObservationIgnored
    private var stateTask: Task<Void, Never>?
    @ObservationIgnored
    private var participantsTask: Task<Void, Never>?
    @ObservationIgnored
    private var messagesTask: Task<Void, Never>?
    @ObservationIgnored
    private var phaseTask: Task<Void, Never>?

    var status: Status = .idle
    var lastError: String?
    var lastDiagnostic: String?
    var participantCount: Int = 1
    var isLeader: Bool = false

    // 同步呼吸状态
    var sessionPattern: BreathingPattern?
    var sessionPhase: String = "idle"
    var sessionPhaseLabel: String = "准备"
    var sessionRemaining: Int = 0
    var sessionCycle: Int = 0
    var sessionTargetCycles: Int = 6

    private var startedAt: Date?
    private var finishedAt: Date?

    init() {
        observeIncomingSessions()
    }

    deinit {
        observerTask?.cancel()
        stateTask?.cancel()
        participantsTask?.cancel()
        messagesTask?.cancel()
        phaseTask?.cancel()
    }

    private func observeIncomingSessions() {
        observerTask = Task { [weak self] in
            for await session in BreathingGroupActivity.sessions() {
                await self?.attach(to: session)
            }
        }
    }

    // MARK: - Activate (initiator)

    func activate() async {
        status = .preparing
        lastError = nil
        let activity = BreathingGroupActivity()
        do {
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                let activated = try await activity.activate()
                if !activated {
                    lastError = "未能激活 SharePlay,请确认在 FaceTime 通话中"
                    status = .error
                }
            case .activationDisabled:
                lastError = "SharePlay 不可用,先打 FaceTime 通话再试"
                status = .error
            case .cancelled:
                lastError = "已取消"
                status = .idle
            @unknown default:
                lastError = "未知错误"
                status = .error
            }
        } catch {
            lastError = error.localizedDescription
            status = .error
        }
    }

    // MARK: - Attach to GroupSession

    private func attach(to session: GroupSession<BreathingGroupActivity>) async {
        groupSession = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger

        // 监听 state
        stateTask = Task { [weak self] in
            for await state in session.$state.values {
                Task { @MainActor [weak self] in
                    self?.handleSessionState(state)
                }
            }
        }

        // 监听 participants
        participantsTask = Task { [weak self] in
            for await participants in session.$activeParticipants.values {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.participantCount = participants.count
                    // leader 是最早加入的(localParticipant 是自己)
                    // 简化:第一个 join 的认为是自己 → 自己是 leader
                    self.isLeader = participants.count == 1 ||
                        (participants.first?.id == session.localParticipant.id)
                    self.lastDiagnostic = "已连接 \(participants.count) 人"
                }
            }
        }

        // 监听 messages
        messagesTask = Task { [weak self] in
            for await (msg, _) in messenger.messages(of: Message.self) {
                Task { @MainActor [weak self] in
                    self?.handleReceive(msg)
                }
            }
        }

        session.join()
    }

    private func handleSessionState(_ state: GroupSession<BreathingGroupActivity>.State) {
        switch state {
        case .joined:
            status = .joined
            lastDiagnostic = "已加入 SharePlay"
        case .invalidated(let reason):
            lastError = reason.localizedDescription
            status = .error
        default:
            break
        }
    }

    // MARK: - Breathing control

    func startBreathing(pattern: BreathingPattern, targetCycles: Int = 6) {
        sessionPattern = pattern
        sessionTargetCycles = targetCycles
        sessionCycle = 0
        startedAt = Date()
        status = .running

        send(.startSession(patternId: pattern.id, targetCycles: targetCycles))

        phaseTask = Task { [weak self] in
            await self?.runPhases()
        }
    }

    private func runPhases() async {
        guard let pattern = sessionPattern else { return }

        while sessionCycle < sessionTargetCycles {
            await runPhase("inhale", label: "吸气", duration: pattern.inhale)
            if Task.isCancelled { return }

            if pattern.hold1 > 0 {
                await runPhase("hold1", label: "屏住", duration: pattern.hold1)
                if Task.isCancelled { return }
            }

            await runPhase("exhale", label: "呼气", duration: pattern.exhale)
            if Task.isCancelled { return }

            if pattern.hold2 > 0 {
                await runPhase("hold2", label: "屏住", duration: pattern.hold2)
                if Task.isCancelled { return }
            }

            sessionCycle += 1
        }

        finishedAt = Date()
        status = .finished
        sessionPhase = "idle"
        sessionPhaseLabel = "完成"
        send(.endSession)
        accumulateMindful()
    }

    private func runPhase(_ phase: String, label: String, duration: Double) async {
        sessionPhase = phase
        sessionPhaseLabel = label
        sessionRemaining = Int(duration.rounded(.up))
        send(.phaseChange(phase: phase, phaseLabel: label, remaining: sessionRemaining, cycle: sessionCycle))

        let start = Date()
        var lastSecond = sessionRemaining
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= duration {
                sessionRemaining = 0
                return
            }
            let remaining = Int((duration - elapsed).rounded(.up))
            sessionRemaining = remaining
            if remaining != lastSecond {
                lastSecond = remaining
                send(.phaseChange(phase: phase, phaseLabel: label, remaining: remaining, cycle: sessionCycle))
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: - Messaging

    private func send(_ message: Message) {
        guard let messenger else { return }
        Task {
            try? await messenger.send(message)
        }
    }

    private func handleReceive(_ message: Message) {
        switch message {
        case .startSession(let patternId, let targetCycles):
            sessionPattern = BreathingPattern.allPresets.first(where: { $0.id == patternId })
            sessionTargetCycles = targetCycles
            sessionCycle = 0
            startedAt = Date()
            status = .running
        case .phaseChange(let phase, let label, let remaining, let cycle):
            sessionPhase = phase
            sessionPhaseLabel = label
            sessionRemaining = remaining
            sessionCycle = cycle
        case .endSession:
            finishedAt = Date()
            status = .finished
            sessionPhase = "idle"
            sessionPhaseLabel = "完成"
            accumulateMindful()
        }
    }

    private func accumulateMindful() {
        guard let started = startedAt, let ended = finishedAt else { return }
        let minutes = ended.timeIntervalSince(started) / 60
        let prev = UserDefaults.standard.double(forKey: "totalMindfulMinutes")
        UserDefaults.standard.set(prev + minutes, forKey: "totalMindfulMinutes")
    }

    // MARK: - Leave

    func leave() {
        phaseTask?.cancel()
        phaseTask = nil
        messagesTask?.cancel()
        messagesTask = nil
        participantsTask?.cancel()
        participantsTask = nil
        stateTask?.cancel()
        stateTask = nil
        groupSession?.leave()
        groupSession = nil
        messenger = nil
        sessionPattern = nil
        sessionPhase = "idle"
        sessionPhaseLabel = "准备"
        sessionRemaining = 0
        sessionCycle = 0
        startedAt = nil
        finishedAt = nil
        status = .idle
        lastError = nil
        lastDiagnostic = nil
    }
}
