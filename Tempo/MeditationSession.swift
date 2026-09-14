//
//  MeditationSession.swift
//  Tempo
//
//  共振冥想 MVP — 独自冥想模式(不依赖 P2P).
//   - 选时长(5 / 10 / 15 / 20 分钟)
//   - 全屏圆环倒计时
//   - 完成后写入 Apple Health Mindful Session + 累计正念时长
//

import SwiftUI
import Combine

struct MeditationFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .picker
    @State private var selectedMinutes: Int = 10
    @State private var startedAt: Date?
    @State private var endsAt: Date?
    @State private var remainingSeconds: Int = 0
    @State private var timer: AnyCancellable?

    @AppStorage("totalMindfulMinutes") private var totalMindfulMinutes: Double = 0

    enum Phase {
        case picker
        case running
        case done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "10B981").opacity(0.18),
                        Color(hex: "059669").opacity(0.06),
                        TempoTheme.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                content
            }
            .navigationTitle("共振冥想")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if phase == .running {
                        Button("结束") { stop(saveSession: true) }
                            .foregroundStyle(TempoTheme.danger)
                    } else {
                        Button("关闭") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(phase == .running)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .picker: pickerView
        case .running: runningView
        case .done: doneView
        }
    }

    // MARK: - Picker

    private var pickerView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)
            ZStack {
                Circle()
                    .fill(TempoTheme.success.opacity(0.16))
                    .blur(radius: 24)
                    .frame(width: 200, height: 200)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 70, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "10B981"), Color(hex: "059669")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(spacing: 8) {
                Text("静坐冥想")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("选择一段时间,把心放下来")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }

            VStack(spacing: 14) {
                Text("时长")
                    .font(.system(size: 12, weight: .heavy))
                    .kerning(0.5)
                    .foregroundStyle(TempoTheme.tertiaryText)

                HStack(spacing: 10) {
                    ForEach([5, 10, 15, 20], id: \.self) { min in
                        Button {
                            selectedMinutes = min
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(min)")
                                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                                Text("分钟")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(selectedMinutes == min ? .white : TempoTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(selectedMinutes == min
                                          ? AnyShapeStyle(LinearGradient(
                                              colors: [Color(hex: "10B981"), Color(hex: "059669")],
                                              startPoint: .topLeading,
                                              endPoint: .bottomTrailing))
                                          : AnyShapeStyle(Color.white))
                            )
                        }
                        .buttonStyle(.tempoPress)
                    }
                }
            }
            .padding(.top, 8)

            Spacer()

            Button {
                start()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("开始")
                }
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(hex: "10B981"), Color(hex: "059669")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .shadow(color: Color(hex: "10B981").opacity(0.35), radius: 14, y: 8)
            }
            .buttonStyle(.tempoPress)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Running

    private var runningView: some View {
        let totalSeconds = selectedMinutes * 60
        let progress = totalSeconds > 0 ? 1.0 - Double(remainingSeconds) / Double(totalSeconds) : 0
        return VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(TempoTheme.success.opacity(0.15), lineWidth: 14)
                    .frame(width: 240, height: 240)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "10B981"), Color(hex: "059669")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 240, height: 240)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)
                VStack(spacing: 4) {
                    Text(formatTime(remainingSeconds))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("剩余")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
            VStack(spacing: 6) {
                Text("感受呼吸")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("注意一吸一呼,念头来了不要追,让它过去")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
            .padding(.horizontal, 30)
            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(TempoTheme.success.opacity(0.18))
                    .blur(radius: 24)
                    .frame(width: 200, height: 200)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "10B981"), Color(hex: "059669")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(spacing: 6) {
                Text("已完成 \(selectedMinutes) 分钟")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("已写入 Apple Health · 正念时长")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            HStack(spacing: 30) {
                VStack(spacing: 2) {
                    Text("\(Int(totalMindfulMinutes))")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("总正念分钟")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
            .padding(.top, 8)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(hex: "10B981"), Color(hex: "059669")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
            }
            .buttonStyle(.tempoPress)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Logic

    private func start() {
        let now = Date()
        startedAt = now
        endsAt = now.addingTimeInterval(TimeInterval(selectedMinutes * 60))
        remainingSeconds = selectedMinutes * 60
        phase = .running
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tick() }
        // 触觉提示开始
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    private func tick() {
        if remainingSeconds > 0 {
            remainingSeconds -= 1
        }
        if remainingSeconds <= 0 {
            stop(saveSession: true)
        }
    }

    private func stop(saveSession: Bool) {
        timer?.cancel()
        timer = nil
        guard let start = startedAt else {
            phase = .picker
            return
        }
        let actualEnd = Date()
        let actualMinutes = max(1, Int(actualEnd.timeIntervalSince(start) / 60))
        if saveSession {
            Task { @MainActor in
                try? await HealthKitService.shared.writeMindfulSession(start: start, end: actualEnd)
                totalMindfulMinutes += Double(actualMinutes)
                TodayMindfulCache.shared.markCompletedNow(minutes: actualMinutes)
            }
            // Phase 2: 上传 meditation session 到 server
            if TempoSession.shared.isLoggedIn {
                let minutesCopy = actualMinutes
                let endCopy = actualEnd
                Task.detached(priority: .background) {
                    try? await TempoAPIClient.shared.uploadMeditationSession(minutes: minutesCopy, completedAt: endCopy)
                }
            }
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            phase = .done
        } else {
            phase = .picker
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
