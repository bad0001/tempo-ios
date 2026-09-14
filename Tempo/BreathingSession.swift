//
//  BreathingSession.swift
//  Tempo
//

import SwiftUI
import TempoCore
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Engine

@Observable
@MainActor
final class BreathingSession {
    enum Phase: String, Equatable {
        case idle
        case inhale
        case hold1
        case exhale
        case hold2

        var displayName: String {
            switch self {
            case .idle: "准备"
            case .inhale: "吸气"
            case .hold1: "屏住"
            case .exhale: "呼气"
            case .hold2: "屏住"
            }
        }
    }

    enum SessionState: Equatable {
        case idle
        case running
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var remainingSeconds: Int = 0
    private(set) var completedCycles: Int = 0
    private(set) var targetCycles: Int = 0
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var circleScale: CGFloat = 0.45
    private(set) var state: SessionState = .idle

    private var task: Task<Void, Never>?
    private var pattern: BreathingPattern?

    #if canImport(ActivityKit)
    private var activity: Activity<BreathingActivityAttributes>?
    #endif

    var elapsedSeconds: Int {
        guard let startedAt else { return 0 }
        let end = finishedAt ?? Date()
        return Int(end.timeIntervalSince(startedAt))
    }

    var formattedElapsed: String {
        let s = elapsedSeconds
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    func start(pattern: BreathingPattern, targetCycles: Int) {
        guard state != .running else { return }
        self.pattern = pattern
        self.targetCycles = targetCycles
        self.completedCycles = 0
        self.startedAt = Date()
        self.finishedAt = nil
        self.state = .running

        startLiveActivity(pattern: pattern, targetCycles: targetCycles)

        task = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if state == .running {
            finishedAt = Date()
            state = .finished
        }
        phase = .idle
        circleScale = 0.45

        endLiveActivity(finished: false)
    }

    private func run() async {
        guard let pattern else { return }
        while completedCycles < targetCycles {
            await runPhase(.inhale, duration: pattern.inhale, targetScale: 1.0)
            if Task.isCancelled { return }

            if pattern.hold1 > 0 {
                await runPhase(.hold1, duration: pattern.hold1, targetScale: 1.0)
                if Task.isCancelled { return }
            }

            await runPhase(.exhale, duration: pattern.exhale, targetScale: 0.45)
            if Task.isCancelled { return }

            if pattern.hold2 > 0 {
                await runPhase(.hold2, duration: pattern.hold2, targetScale: 0.45)
                if Task.isCancelled { return }
            }

            completedCycles += 1
        }
        finishedAt = Date()
        state = .finished
        phase = .idle

        endLiveActivity(finished: true)

        if let started = startedAt, let ended = finishedAt {
            let minutes = ended.timeIntervalSince(started) / 60
            let prev = UserDefaults.standard.double(forKey: "totalMindfulMinutes")
            UserDefaults.standard.set(prev + minutes, forKey: "totalMindfulMinutes")

            try? await HealthKitService.shared.writeMindfulSession(start: started, end: ended)
            TodayMindfulCache.shared.markCompletedNow(minutes: Int(minutes.rounded()))

            // Phase 2:上传 session 到 server(自己 history + 朋友查看,后者由 server 端 prefs 控制是否暴露)
            // 始终上传到自己 history(用于 AI 分析、daily_summary 聚合);朋友能不能看由 server-side prefs 判定
            if TempoSession.shared.isLoggedIn, minutes >= 0.5 {
                let patternKey = pattern.id
                Task.detached(priority: .background) {
                    try? await TempoAPIClient.shared.uploadBreathingSession(
                        pattern: patternKey,
                        minutes: Int(minutes.rounded()),
                        completedAt: ended
                    )
                }
            }
        }
    }

    private func runPhase(_ newPhase: Phase, duration: Double, targetScale: CGFloat) async {
        self.phase = newPhase
        self.circleScale = targetScale
        self.remainingSeconds = Int(duration.rounded(.up))

        await updateLiveActivity()

        let totalDuration = duration
        let start = Date()
        var lastSecond = self.remainingSeconds
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= totalDuration {
                self.remainingSeconds = 0
                return
            }
            let remaining = Int((totalDuration - elapsed).rounded(.up))
            self.remainingSeconds = remaining
            if remaining != lastSecond {
                lastSecond = remaining
                await updateLiveActivity()
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity(pattern: BreathingPattern, targetCycles: Int) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = BreathingActivityAttributes(
            patternId: pattern.id,
            patternName: pattern.displayName,
            targetCycles: targetCycles
        )
        let initial = BreathingActivityAttributes.ContentState(
            phase: "idle",
            phaseLabel: "准备",
            remainingSeconds: Int(pattern.cycleDuration),
            completedCycles: 0,
            isFinished: false
        )
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: initial, staleDate: nil)
            )
        } catch {
            activity = nil
        }
        #endif
    }

    private func updateLiveActivity() async {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let liveState = BreathingActivityAttributes.ContentState(
            phase: phase.rawValue,
            phaseLabel: phase.displayName,
            remainingSeconds: remainingSeconds,
            completedCycles: completedCycles,
            isFinished: false
        )
        await activity.update(.init(state: liveState, staleDate: nil))
        #endif
    }

    private func endLiveActivity(finished: Bool) {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let policy: ActivityUIDismissalPolicy = finished ? .default : .immediate
        let finalState = BreathingActivityAttributes.ContentState(
            phase: "idle",
            phaseLabel: finished ? "完成" : "已结束",
            remainingSeconds: 0,
            completedCycles: completedCycles,
            isFinished: finished
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: policy)
        }
        self.activity = nil
        #endif
    }
}

// MARK: - Session View

struct BreathingSessionView: View {
    let pattern: BreathingPattern

    @Environment(\.dismiss) private var dismiss
    @State private var session = BreathingSession()
    @State private var showExitConfirm = false

    private var phaseColor: Color {
        switch session.phase {
        case .inhale: .mint
        case .hold1: .yellow
        case .exhale: .blue
        case .hold2: .indigo
        case .idle: .gray
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, phaseColor.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: session.phase)

            BreathingCircle(scale: session.circleScale, color: phaseColor)

            if session.state != .finished {
                VStack(spacing: 12) {
                    Text(LocalizedStringKey(session.phase.displayName))
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)

                    Text("\(session.remainingSeconds)")
                        .font(.system(size: 96, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                }
            }

            VStack {
                Spacer()
                if session.state == .finished {
                    FinishedSummary(session: session, pattern: pattern, onDone: { dismiss() })
                } else {
                    HStack(spacing: 32) {
                        StatTile(label: "已完成", value: "\(session.completedCycles)")
                        StatTile(label: "目标", value: "\(session.targetCycles)")
                        StatTile(label: "时长", value: session.formattedElapsed)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showExitConfirm = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.title2)
                }
            }
        }
        .confirmationDialog("结束训练?", isPresented: $showExitConfirm) {
            Button("结束", role: .destructive) {
                session.stop()
                dismiss()
            }
            Button("继续", role: .cancel) {}
        }
        .onAppear {
            session.start(pattern: pattern, targetCycles: 6)
        }
        .onDisappear {
            session.stop()
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .statusBarHidden()
    }
}

// MARK: - Pieces

struct BreathingCircle: View {
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

struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct FinishedSummary: View {
    let session: BreathingSession
    let pattern: BreathingPattern
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("训练完成")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 32) {
                StatTile(label: "循环数", value: "\(session.completedCycles)")
                StatTile(label: "总时长", value: session.formattedElapsed)
                StatTile(label: "模式", value: pattern.displayName)
            }

            Button {
                onDone()
            } label: {
                Text("完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
}

#Preview {
    NavigationStack {
        BreathingSessionView(pattern: .fourSevenEight)
    }
}
