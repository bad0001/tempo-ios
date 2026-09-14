//
//  MotionActivityDetector.swift
//  Tempo
//
//  通过 CoreMotion 推断当前运动状态(static / walking / running / cycling)+
//  通过 HealthKit 最近睡眠样本判断是否在睡眠中,产出 ActivityState 给 evaluator.
//
//  权限拒绝 → fallback .resting,不影响主流程.
//

import Foundation
import Observation
import TempoCore
#if canImport(CoreMotion)
import CoreMotion
#endif

@MainActor
@Observable
final class MotionActivityDetector {
    static let shared = MotionActivityDetector()

    private(set) var currentState: ActivityState = .resting
    private var lastUpdate: Date = .distantPast
    private let cacheTTL: TimeInterval = 60   // 1min 缓存

    #if canImport(CoreMotion)
    private let manager = CMMotionActivityManager()
    #endif

    /// 主入口 — 先睡眠后运动判断,优先返回 .sleeping
    func currentActivity() async -> ActivityState {
        if Date().timeIntervalSince(lastUpdate) < cacheTTL {
            return currentState
        }

        // 1) 睡眠优先
        if await HealthKitService.shared.isCurrentlyAsleep() {
            currentState = .sleeping
            lastUpdate = Date()
            return .sleeping
        }

        // 2) CoreMotion
        let state = await detectFromCoreMotion()
        currentState = state
        lastUpdate = Date()
        return state
    }

    func forceRefresh() async -> ActivityState {
        lastUpdate = .distantPast
        return await currentActivity()
    }

    // MARK: - CoreMotion

    private func detectFromCoreMotion() async -> ActivityState {
        #if canImport(CoreMotion)
        guard CMMotionActivityManager.isActivityAvailable() else { return .resting }

        let activities: [CMMotionActivity] = await withCheckedContinuation { cont in
            let start = Date().addingTimeInterval(-300)   // 最近 5 min
            let end = Date()
            manager.queryActivityStarting(from: start, to: end, to: .main) { result, _ in
                cont.resume(returning: result ?? [])
            }
        }

        // 取最近 5 个 activity 看 dominant
        let recent = activities.suffix(8)
        guard !recent.isEmpty else { return .resting }

        let isRunningOrCycling = recent.contains { $0.running || $0.cycling }
        let isWalking = recent.contains { $0.walking && $0.confidence != .low }
        let isAutomotive = recent.contains { $0.automotive }

        if isRunningOrCycling {
            return .exercising
        }
        if isWalking {
            return .active
        }
        // automotive 算静息(开车不算运动)
        if isAutomotive { return .resting }
        return .resting
        #else
        return .resting
        #endif
    }

    private init() {}
}
