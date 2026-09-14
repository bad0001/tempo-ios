//
//  ContentView.swift
//  Tempo Watch App
//
//  手表只保留三个高频场景:
//   1. 现在:压力 + 恢复,一眼确认状态
//   2. 关怀:查看一条最新密友关怀并快捷回应
//   3. 身体:体征 + 实时心率监测
//

import SwiftUI
import HealthKit
import WatchConnectivity
import WatchKit
import os
import TempoCore

// MARK: - Heart rate monitor

@Observable
final class HeartRateMonitor {
    var bpm: Double = 0
    var isMonitoring = false
    var isStarting = false
    var errorMessage: String?
}

@MainActor
final class WorkoutController: NSObject, HKWorkoutSessionDelegate {
    static let shared = WorkoutController()
    let state = HeartRateMonitor()

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var heartRateQuery: HKAnchoredObjectQuery?

    private func requestAuthorization() async throws {
        var toRead: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            toRead.insert(heartRate)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            toRead.insert(hrv)
        }
        try await healthStore.requestAuthorization(toShare: [], read: toRead)
    }

    func start() {
        guard !state.isStarting, !state.isMonitoring else { return }
        state.isStarting = true
        state.errorMessage = nil
        WKInterfaceDevice.current().play(.click)

        Task { @MainActor in
            do {
                try await requestAuthorization()

                let configuration = HKWorkoutConfiguration()
                configuration.activityType = .other
                configuration.locationType = .indoor

                let session = try HKWorkoutSession(
                    healthStore: healthStore,
                    configuration: configuration
                )
                session.delegate = self
                workoutSession = session
                session.startActivity(with: .now)
                startHeartRateQuery()
            } catch {
                state.isStarting = false
                state.isMonitoring = false
                state.errorMessage = error.localizedDescription
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    func stop() {
        guard state.isStarting || state.isMonitoring else { return }
        WKInterfaceDevice.current().play(.stop)
        workoutSession?.end()
        stopHeartRateQuery()
        state.isStarting = false
        state.isMonitoring = false
        state.bpm = 0
    }

    private func startHeartRateQuery() {
        guard heartRateQuery == nil,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let predicate = HKQuery.predicateForSamples(
            withStart: .now,
            end: nil,
            options: .strictStartDate
        )
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.handle(samples: samples)
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.handle(samples: samples)
        }
        healthStore.execute(query)
        heartRateQuery = query
    }

    private func stopHeartRateQuery() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }

    private nonisolated func handle(samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample],
              let latest = samples.last else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = latest.quantity.doubleValue(for: unit)
        Task { @MainActor in
            self.state.bpm = bpm
            WatchSessionManager.shared.send(heartRate: bpm)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                state.isStarting = false
                state.isMonitoring = true
                state.errorMessage = nil
                WKInterfaceDevice.current().play(.start)
            case .ended:
                stopHeartRateQuery()
                self.workoutSession = nil
                state.isStarting = false
                state.isMonitoring = false
                state.bpm = 0
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            stopHeartRateQuery()
            self.workoutSession = nil
            state.isStarting = false
            state.isMonitoring = false
            state.errorMessage = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

// MARK: - Watch connectivity

enum WatchCareReplyState: Equatable {
    case idle
    case sending
    case queued
    case sent
    case failed(String)
}

@Observable
final class WatchSnapshotStore {
    var snapshot: WatchSnapshot = .empty
    var hasReceivedFromPhone = false
    var isRequesting = false
    var syncMessage: String?
    var careReplyState: WatchCareReplyState = .idle
}

final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    let snapshotStore = WatchSnapshotStore()

    private let logger = Logger(
        subsystem: "com.ayipocket.tempo.watchkitapp",
        category: "WatchConnectivity"
    )
    private var shouldRequestAfterActivation = true
    private var lastAutomaticSnapshotRequest = Date.distantPast

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(heartRate bpm: Double) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = [WCMessageKeys.heartRate: bpm]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.debug("Heart-rate message failed: \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    func requestSnapshot(userInitiated: Bool) {
        if !userInitiated,
           Date().timeIntervalSince(lastAutomaticSnapshotRequest) < 10 {
            return
        }
        if !userInitiated {
            lastAutomaticSnapshotRequest = .now
        }
        if userInitiated {
            WKInterfaceDevice.current().play(.click)
        }
        guard WCSession.isSupported() else {
            setSyncFailure(String(localized: "此设备不支持与 iPhone 同步"))
            return
        }

        let session = WCSession.default
        guard session.activationState == .activated else {
            shouldRequestAfterActivation = true
            Task { @MainActor in
                snapshotStore.isRequesting = true
                snapshotStore.syncMessage = String(localized: "正在连接 iPhone")
            }
            session.activate()
            return
        }

        shouldRequestAfterActivation = false
        Task { @MainActor in
            snapshotStore.isRequesting = true
            snapshotStore.syncMessage = session.isReachable
                ? String(localized: "正在刷新")
                : String(localized: "等待 iPhone 连接")
        }

        let payload: [String: Any] = [WCMessageKeys.watchRequestSnapshot: true]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in
                Task { @MainActor in
                    self.snapshotStore.syncMessage = String(localized: "已请求最新数据")
                }
            }) { [weak self] error in
                guard let self else { return }
                self.logger.debug("Snapshot request failed, queued: \(error.localizedDescription)")
                session.transferUserInfo(payload)
                Task { @MainActor in
                    self.snapshotStore.syncMessage = String(localized: "已排队，等待 iPhone")
                }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    func sendCareReply(_ message: String, for signal: WatchCareSignal) {
        guard snapshotStore.careReplyState != .sending else { return }
        WKInterfaceDevice.current().play(.click)

        let session = WCSession.default
        guard session.activationState == .activated else {
            snapshotStore.careReplyState = .failed(String(localized: "请先连接 iPhone"))
            WKInterfaceDevice.current().play(.failure)
            session.activate()
            return
        }

        let payload: [String: Any] = [
            WCMessageKeys.watchCareReplyMessage: message,
            WCMessageKeys.watchCareFriendUserID: signal.friendUserID,
            WCMessageKeys.watchCareEventID: signal.eventID,
        ]

        snapshotStore.careReplyState = .sending
        if session.isReachable {
            session.sendMessage(payload) { [weak self] reply in
                guard let self else { return }
                let succeeded = reply[WCMessageKeys.watchCareReplySucceeded] as? Bool == true
                Task { @MainActor in
                    if succeeded {
                        self.finishCareReply(eventID: signal.eventID)
                    } else {
                        let message = reply[WCMessageKeys.watchCareReplyError] as? String
                            ?? String(localized: "发送失败，请重试")
                        self.snapshotStore.careReplyState = .failed(message)
                        WKInterfaceDevice.current().play(.failure)
                    }
                }
            } errorHandler: { [weak self] error in
                guard let self else { return }
                self.logger.debug("Care reply message failed, queued: \(error.localizedDescription)")
                session.transferUserInfo(payload)
                Task { @MainActor in
                    self.snapshotStore.careReplyState = .queued
                    WKInterfaceDevice.current().play(.directionUp)
                }
            }
        } else {
            session.transferUserInfo(payload)
            snapshotStore.careReplyState = .queued
            WKInterfaceDevice.current().play(.directionUp)
        }
    }

    @MainActor
    private func finishCareReply(eventID: String) {
        if snapshotStore.snapshot.careSignal?.eventID == eventID {
            snapshotStore.snapshot = snapshotStore.snapshot.replacingCareSignal(nil)
        }
        snapshotStore.careReplyState = .sent
        WKInterfaceDevice.current().play(.success)
    }

    private func handleControl(_ message: [String: Any]) {
        if let monitoring = message[WCMessageKeys.isMonitoring] as? Bool {
            Task { @MainActor in
                if monitoring {
                    WorkoutController.shared.start()
                } else {
                    WorkoutController.shared.stop()
                }
            }
        }

        if let json = message[WCMessageKeys.watchSnapshotJSON] as? String,
           let snapshot = WatchSnapshot.decodeJSON(json) {
            Task { @MainActor in
                let oldEventID = snapshotStore.snapshot.careSignal?.eventID
                snapshotStore.snapshot = snapshot
                snapshotStore.hasReceivedFromPhone = true
                snapshotStore.isRequesting = false
                snapshotStore.syncMessage = nil
                if oldEventID != snapshot.careSignal?.eventID {
                    snapshotStore.careReplyState = .idle
                }
            }
        }
    }

    private func setSyncFailure(_ message: String) {
        Task { @MainActor in
            snapshotStore.isRequesting = false
            snapshotStore.syncMessage = message
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("WC activation failed: \(error.localizedDescription)")
            setSyncFailure("连接 iPhone 失败")
            return
        }

        if let context = session.receivedApplicationContext as [String: Any]?, !context.isEmpty {
            handleControl(context)
        }
        if activationState == .activated, shouldRequestAfterActivation {
            requestSnapshot(userInitiated: false)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleControl(message)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        handleControl(applicationContext)
    }
}

// MARK: - Root

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var heartRate = WorkoutController.shared.state
    @State private var store = WatchSessionManager.shared.snapshotStore

    var body: some View {
        TabView {
            WatchNowPage(store: store)
            WatchCarePage(store: store)
            WatchBodyPage(snapshot: store.snapshot, monitor: heartRate)
        }
        .tabViewStyle(.verticalPage)
        .task {
            WatchSessionManager.shared.requestSnapshot(userInitiated: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                WatchSessionManager.shared.requestSnapshot(userInitiated: false)
            }
        }
    }
}

// MARK: - Page 1: Now

struct WatchNowPage: View {
    let store: WatchSnapshotStore

    private var snapshot: WatchSnapshot { store.snapshot }

    private var stressColor: Color {
        guard let level = snapshot.stressLevel else { return .gray }
        switch level {
        case .calm: return .green
        case .relaxed: return .mint
        case .mild: return .blue
        case .high: return .orange
        case .extreme: return .red
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            if let stress = snapshot.stressValue {
                HStack {
                    Text("现在")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    freshnessLabel
                }

                Text("\(stress)")
                    .font(.system(size: 58, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(stressColor)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .accessibilityLabel("当前压力 \(stress)，\(stressLevelName(snapshot.stressLevel))")

                HStack(spacing: 6) {
                    statusPill(
                        stressLevelName(snapshot.stressLevel),
                        color: stressColor
                    )
                    if let recovery = snapshot.recoveryValue {
                        statusPill(String(localized: "恢复 \(recovery)%"), color: .cyan)
                    }
                }

                if snapshot.recoveryHasElevatedTemp {
                    Label("体温趋势偏高", systemImage: "thermometer.high")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }

                if !snapshot.isFresh {
                    refreshButton
                }
            } else {
                if store.isRequesting {
                    ProgressView()
                        .tint(.cyan)
                } else {
                    Image(systemName: "applewatch")
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(.cyan)
                }

                Text(store.isRequesting
                    ? String(localized: "正在同步")
                    : String(localized: "等待压力数据"))
                    .font(.system(size: 14, weight: .bold))

                Text(store.syncMessage ?? String(localized: "从 iPhone 获取最近一次健康快照"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                refreshButton
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var freshnessLabel: some View {
        if snapshot.updatedAt > .distantPast {
            Text(relativeTime(snapshot.updatedAt))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(snapshot.isFresh ? Color.secondary : Color.orange)
                .accessibilityLabel("数据更新于 \(relativeTime(snapshot.updatedAt))")
        }
    }

    private var refreshButton: some View {
        Button {
            WatchSessionManager.shared.requestSnapshot(userInitiated: true)
        } label: {
            if store.isRequesting {
                ProgressView()
            } else {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
        .tint(.cyan)
        .disabled(store.isRequesting)
        .accessibilityHint("从配对的 iPhone 获取最新压力与恢复数据")
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func stressLevelName(_ level: StressLevel?) -> String {
        guard let level else { return String(localized: "压力") }
        let language = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "zh"
        return language.hasPrefix("en") ? level.displayNameEnglish : level.displayName
    }
}

// MARK: - Page 2: Care

struct WatchCarePage: View {
    let store: WatchSnapshotStore

    private var quickReplies: [String] {
        [
            String(localized: "收到啦"),
            String(localized: "谢谢你"),
            String(localized: "抱抱你"),
        ]
    }

    var body: some View {
        Group {
            if let signal = store.snapshot.careSignal {
                careContent(signal)
            } else {
                emptyCare
            }
        }
        .padding(.horizontal, 8)
    }

    private func careContent(_ signal: WatchCareSignal) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(String(signal.senderName.prefix(1)))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(careColor(signal.kind))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(careColor(signal.kind).opacity(0.15)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(signal.senderName)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                        Text(relativeTime(signal.sentAt))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: careIcon(signal.kind))
                        .foregroundStyle(careColor(signal.kind))
                }

                Text(signal.message)
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                    .accessibilityLabel("\(signal.senderName)说，\(signal.message)")

                replyStatus

                if canReply {
                    ForEach(quickReplies, id: \.self) { reply in
                        Button(reply) {
                            WatchSessionManager.shared.sendCareReply(reply, for: signal)
                        }
                        .buttonStyle(.bordered)
                        .tint(careColor(signal.kind))
                        .disabled(store.careReplyState == .sending)
                        .accessibilityLabel("回复 \(signal.senderName)，\(reply)")
                    }
                }
            }
        }
    }

    private var emptyCare: some View {
        VStack(spacing: 9) {
            Image(systemName: store.careReplyState == .sent ? "checkmark.heart.fill" : "heart.text.square")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(store.careReplyState == .sent ? Color.green : Color.pink)

            Text(store.careReplyState == .sent
                ? String(localized: "已经回应")
                : String(localized: "暂无新关怀"))
                .font(.system(size: 14, weight: .bold))

            Text(store.careReplyState == .sent
                ? String(localized: "你的回应已送达")
                : String(localized: "密友的新消息会出现在这里"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var replyStatus: some View {
        switch store.careReplyState {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 6) {
                ProgressView()
                Text("正在发送")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        case .queued:
            Label("已交给 iPhone，连接后发送", systemImage: "iphone.and.arrow.forward")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.orange)
        case .sent:
            Label("已送达", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var canReply: Bool {
        switch store.careReplyState {
        case .idle, .failed:
            true
        case .sending, .queued, .sent:
            false
        }
    }

    private func careIcon(_ kind: String) -> String {
        switch kind {
        case "heartbeat": "heart.fill"
        case "breathing_invite": "wind"
        case "meditation_invite": "leaf.fill"
        case "session_completed": "checkmark.seal.fill"
        default: "envelope.fill"
        }
    }

    private func careColor(_ kind: String) -> Color {
        switch kind {
        case "breathing_invite": .cyan
        case "meditation_invite": .mint
        case "session_completed": .green
        default: .pink
        }
    }
}

// MARK: - Page 3: Body

struct WatchBodyPage: View {
    let snapshot: WatchSnapshot
    let monitor: HeartRateMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                HStack {
                    Text("身体")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if monitor.isMonitoring {
                        Label("实时", systemImage: "circle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.pink)
                    }
                }

                vitalRow(
                    icon: "heart.fill",
                    color: .pink,
                    label: String(localized: "心率"),
                    value: effectiveHeartRate.map { "\(Int($0))" } ?? "—",
                    unit: "bpm"
                )
                vitalRow(
                    icon: "waveform.path.ecg",
                    color: .purple,
                    label: "HRV",
                    value: snapshot.latestHRV.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "ms"
                )
                vitalRow(
                    icon: "heart.text.square.fill",
                    color: .indigo,
                    label: String(localized: "静息"),
                    value: snapshot.restingHR.map { "\(Int($0))" } ?? "—",
                    unit: "bpm"
                )
                vitalRow(
                    icon: "moon.zzz.fill",
                    color: .blue,
                    label: String(localized: "睡眠"),
                    value: snapshot.totalAsleepHours.map { String(format: "%.1f", $0) } ?? "—",
                    unit: "h"
                )

                monitorControl

                if let error = monitor.errorMessage {
                    Text(error)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var effectiveHeartRate: Double? {
        monitor.bpm > 0 ? monitor.bpm : snapshot.latestHR
    }

    @ViewBuilder
    private var monitorControl: some View {
        if monitor.isStarting {
            HStack(spacing: 7) {
                ProgressView()
                Text("正在启动监测")
            }
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        } else if monitor.isMonitoring {
            Button(role: .destructive) {
                WorkoutController.shared.stop()
            } label: {
                Label("停止监测", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityHint("结束实时心率采集")
        } else {
            Button {
                WorkoutController.shared.start()
            } label: {
                Label("开始监测", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.pink)
            .accessibilityHint("启动 Apple Watch 实时心率采集")
        }
    }

    private func vitalRow(
        icon: String,
        color: Color,
        label: String,
        value: String,
        unit: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value) \(unit)")
    }
}

// MARK: - Helpers

private func relativeTime(_ date: Date) -> String {
    guard date > .distantPast else { return String(localized: "尚未同步") }
    let interval = max(0, Date().timeIntervalSince(date))
    if interval < 60 { return String(localized: "刚刚") }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: .now)
}

#Preview {
    ContentView()
}
