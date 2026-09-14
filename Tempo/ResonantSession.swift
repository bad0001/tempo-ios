//
//  ResonantSession.swift
//  Tempo
//
//  共振呼吸 P2P 同步核心.
//  使用 Apple Network framework(NWBrowser + NWListener + NWConnection),
//  替代旧的 MultipeerConnectivity(在 iOS 26 上握手不稳定).
//
//  - Host 一方: NWListener 注册 Bonjour service 等待 incoming connection
//  - Follower 一方: NWBrowser 找到 service → NWConnection 直连
//  - 消息格式: 4-byte big-endian length prefix + JSON payload
//

import Foundation
import os
import Network
import SwiftUI
import TempoCore
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class ResonantSession {
    static let serviceType = "_tempo-rsn._tcp"

    enum Role { case idle, host, follower }
    enum Status { case idle, advertising, browsing, connecting, connected, running, finished, error }

    let myDeviceName: String

    @ObservationIgnored
    private var listener: NWListener?
    @ObservationIgnored
    private var browser: NWBrowser?
    @ObservationIgnored
    private var connection: NWConnection?
    @ObservationIgnored
    private var phaseTask: Task<Void, Never>?
    @ObservationIgnored
    private var connectingTimeoutTask: Task<Void, Never>?

    var role: Role = .idle
    var status: Status = .idle
    var foundPeers: [DiscoveredPeer] = []
    var connectedPeerName: String?
    var lastError: String?
    var lastDiagnostic: String?

    // 同步呼吸状态
    var sessionPattern: BreathingPattern?
    var sessionPhase: String = "idle"
    var sessionPhaseLabel: String = "准备"
    var sessionRemaining: Int = 0
    var sessionCycle: Int = 0
    var sessionTargetCycles: Int = 6

    private var startedAt: Date?
    private var finishedAt: Date?

    struct DiscoveredPeer: Identifiable, Hashable {
        let id: UUID = UUID()
        let endpoint: NWEndpoint
        let displayName: String

        static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
            lhs.displayName == rhs.displayName
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(displayName)
        }
    }

    enum Message: Codable {
        case startSession(patternId: String, targetCycles: Int)
        case phaseChange(phase: String, phaseLabel: String, remaining: Int, cycle: Int)
        case endSession
    }

    init() {
        #if canImport(UIKit)
        myDeviceName = UIDevice.current.name
        #else
        myDeviceName = "Tempo"
        #endif
    }

    // MARK: - Host

    func startHosting() {
        stopAll()
        role = .host
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        // 不限制接口类型,让 Network framework 自己挑最优(awdl0 / wifi / cellular).
        // 但 explicitly 不禁止任何接口,提高兼容性.
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters)
            // Bonjour service name 必须在网内唯一 — 加 4 位随机后缀避免两台都叫 "iPhone" 冲突
            let suffix = String(format: "%04d", Int.random(in: 1000...9999))
            let uniqueServiceName = "\(myDeviceName) #\(suffix)"
            listener.service = NWListener.Service(name: uniqueServiceName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] newConn in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.acceptIncoming(newConn)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            status = .advertising
            lastDiagnostic = "已开始广播为 「\(uniqueServiceName)」"
            TempoLog.session.debug("listener started as \(uniqueServiceName)")
        } catch {
            lastError = error.localizedDescription
            status = .error
            TempoLog.session.debug("listener failed: \(error)")
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            lastDiagnostic = "广播中,对方应能搜到 \(myDeviceName)"
            TempoLog.session.debug("listener ready")
        case .failed(let error):
            lastError = error.localizedDescription
            status = .error
            TempoLog.session.debug("listener failed: \(error)")
        case .waiting(let error):
            lastDiagnostic = "等待网络:\(error.localizedDescription)"
        case .cancelled:
            TempoLog.session.debug("listener cancelled")
        default:
            break
        }
    }

    private func acceptIncoming(_ newConn: NWConnection) {
        guard connection == nil else {
            newConn.cancel()
            return
        }
        let peerName = endpointDisplayName(newConn.endpoint)
        TempoLog.session.debug("accept incoming from \(peerName)")
        setupConnection(newConn)
        connection = newConn
        connectedPeerName = peerName
        status = .connecting
        lastDiagnostic = "正在握手 \(peerName)..."
        newConn.start(queue: .main)
    }

    // MARK: - Follower

    func startBrowsing() {
        stopAll()
        role = .follower
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        // 不限制接口类型,让 Network framework 自己挑最优(awdl0 / wifi / cellular).
        // 但 explicitly 不禁止任何接口,提高兼容性.
        parameters.allowLocalEndpointReuse = true

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.updateFoundPeers(results)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleBrowserState(state)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        status = .browsing
        lastDiagnostic = "搜索中..."
        TempoLog.session.debug("browser started")
    }

    private func updateFoundPeers(_ results: Set<NWBrowser.Result>) {
        foundPeers = results.map { result in
            DiscoveredPeer(endpoint: result.endpoint, displayName: endpointDisplayName(result.endpoint))
        }
        if foundPeers.isEmpty {
            lastDiagnostic = "搜索中..."
        } else {
            lastDiagnostic = "找到 \(foundPeers.count) 个设备"
        }
        TempoLog.session.debug("found peers: \(self.foundPeers.map(\.displayName))")
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .failed(let error):
            lastError = error.localizedDescription
            status = .error
            TempoLog.session.debug("browser failed: \(error)")
        case .waiting(let error):
            lastDiagnostic = "等待网络:\(error.localizedDescription)"
        case .ready:
            TempoLog.session.debug("browser ready")
        default:
            break
        }
    }

    func connect(to peer: DiscoveredPeer) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        // 不限制接口类型,让 Network framework 自己挑最优(awdl0 / wifi / cellular).
        // 但 explicitly 不禁止任何接口,提高兼容性.
        parameters.allowLocalEndpointReuse = true
        let conn = NWConnection(to: peer.endpoint, using: parameters)
        setupConnection(conn)
        connection = conn
        connectedPeerName = peer.displayName
        status = .connecting
        lastDiagnostic = "正在连接 \(peer.displayName)..."
        TempoLog.session.debug("connecting to \(peer.displayName)")
        conn.start(queue: .main)
    }

    // MARK: - Connection

    private func setupConnection(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleConnectionState(state, connection: conn)
            }
        }
    }

    private func handleConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        switch state {
        case .ready:
            connectingTimeoutTask?.cancel()
            connectingTimeoutTask = nil
            status = .connected
            lastDiagnostic = "已连接 \(connectedPeerName ?? "")"
            TempoLog.session.debug("connection ready")
            startReceiveLoop(connection)
        case .failed(let error):
            connectingTimeoutTask?.cancel()
            connectingTimeoutTask = nil
            lastError = error.localizedDescription
            lastDiagnostic = "连接失败:\(error.localizedDescription)"
            status = .error
            TempoLog.session.debug("connection failed: \(error)")
        case .waiting(let error):
            lastDiagnostic = "等待网络:\(error.localizedDescription)"
            TempoLog.session.debug("connection waiting: \(error)")
            startConnectingTimeoutIfNeeded(connection: connection)
        case .cancelled:
            connectingTimeoutTask?.cancel()
            connectingTimeoutTask = nil
            if status == .connected || status == .running {
                status = .finished
            }
            TempoLog.session.debug("connection cancelled")
        case .preparing:
            lastDiagnostic = "正在准备连接..."
            startConnectingTimeoutIfNeeded(connection: connection)
        case .setup:
            lastDiagnostic = "建立连接..."
            startConnectingTimeoutIfNeeded(connection: connection)
        @unknown default:
            break
        }
    }

    private func startConnectingTimeoutIfNeeded(connection: NWConnection) {
        guard connectingTimeoutTask == nil else { return }
        connectingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.status == .connecting {
                    self.lastError = "握手超时(20s)— 本地网络可能阻断 P2P。换手机热点试试,或建议 SharePlay 远程模式"
                    self.lastDiagnostic = "握手超时"
                    self.status = .error
                    connection.cancel()
                }
            }
        }
    }

    private func startReceiveLoop(_ conn: NWConnection) {
        Self.receiveLengthPrefix(conn, owner: self)
    }

    private nonisolated static func receiveLengthPrefix(_ conn: NWConnection, owner: ResonantSession) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak owner] data, _, _, error in
            guard let owner, let data, data.count == 4, error == nil else {
                if let error { TempoLog.session.debug("receive prefix error: \(error)") }
                return
            }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            Self.receivePayload(conn, length: Int(length), owner: owner)
        }
    }

    private nonisolated static func receivePayload(_ conn: NWConnection, length: Int, owner: ResonantSession) {
        guard length > 0, length < 1_000_000 else { return }
        conn.receive(minimumIncompleteLength: length, maximumLength: length) { [weak owner] data, _, _, error in
            guard let owner, let data, data.count == length, error == nil else {
                if let error { TempoLog.session.debug("receive payload error: \(error)") }
                return
            }
            Task { @MainActor [weak owner] in
                owner?.handleReceive(data)
            }
            Self.receiveLengthPrefix(conn, owner: owner)
        }
    }

    // MARK: - Session control (host)

    func startBreathingSession(pattern: BreathingPattern, targetCycles: Int = 6) {
        guard role == .host, status == .connected else { return }
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

    private func accumulateMindful() {
        guard let started = startedAt, let ended = finishedAt else { return }
        let minutes = ended.timeIntervalSince(started) / 60
        let prev = UserDefaults.standard.double(forKey: "totalMindfulMinutes")
        UserDefaults.standard.set(prev + minutes, forKey: "totalMindfulMinutes")
    }

    // MARK: - Messaging

    private func send(_ message: Message) {
        guard let connection, let payload = try? JSONEncoder().encode(message) else { return }
        var lengthBE = UInt32(payload.count).bigEndian
        var packet = Data(bytes: &lengthBE, count: 4)
        packet.append(payload)
        connection.send(content: packet, completion: .contentProcessed { _ in })
    }

    private func handleReceive(_ data: Data) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
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

    // MARK: - Cleanup

    func stopAll() {
        phaseTask?.cancel()
        phaseTask = nil
        connectingTimeoutTask?.cancel()
        connectingTimeoutTask = nil
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        foundPeers.removeAll()
        connectedPeerName = nil
        sessionPattern = nil
        sessionPhase = "idle"
        sessionPhaseLabel = "准备"
        sessionRemaining = 0
        sessionCycle = 0
        startedAt = nil
        finishedAt = nil
        role = .idle
        status = .idle
    }

    // MARK: - Helpers

    private func endpointDisplayName(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, _, _, _): return name
        case .hostPort(let host, _): return "\(host)"
        case .url(let url): return url.host ?? "unknown"
        case .unix: return "unix"
        case .opaque: return "opaque"
        @unknown default: return "unknown"
        }
    }
}
