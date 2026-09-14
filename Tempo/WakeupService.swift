//
//  WakeupService.swift
//  Tempo
//
//  节奏唤醒(轻量版):
//  - iOS 限制下无法真正监听浅睡阶段实时唤醒
//  - 折中方案:主闹钟 + 提前 N/2 分钟的「轻柔预热」通知
//  - 文案根据昨晚 HRV 自动调整("能量满满 / 恢复一般 / 节奏稳定")
//

import Foundation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class WakeupService {
    static let shared = WakeupService()

    private let earlyId = "wakeup.early"
    private let mainId  = "wakeup.main"

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "wakeup.enabled") }
    }
    var hour: Int {
        didSet { UserDefaults.standard.set(hour, forKey: "wakeup.hour") }
    }
    var minute: Int {
        didSet { UserDefaults.standard.set(minute, forKey: "wakeup.minute") }
    }
    var windowMinutes: Int {
        didSet { UserDefaults.standard.set(windowMinutes, forKey: "wakeup.window") }
    }

    private init() {
        let d = UserDefaults.standard
        self.enabled = d.bool(forKey: "wakeup.enabled")
        let storedHour = d.integer(forKey: "wakeup.hour")
        self.hour = (0...23).contains(storedHour) ? storedHour : 7
        let storedMinute = d.integer(forKey: "wakeup.minute")
        self.minute = (0...59).contains(storedMinute) ? storedMinute : 0
        let storedWindow = d.integer(forKey: "wakeup.window")
        self.windowMinutes = [15, 30, 45, 60].contains(storedWindow) ? storedWindow : 30
    }

    var formattedTime: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// 闹钟时间(用于 DatePicker 绑定)
    var alarmDate: Date {
        get {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = comps.hour ?? 7
            minute = comps.minute ?? 0
        }
    }

    /// 提前轻柔通知的时刻(主闹钟 - windowMinutes / 2)
    private var earlyTimeComponents: (hour: Int, minute: Int) {
        let halfWindow = windowMinutes / 2
        let total = hour * 60 + minute - halfWindow
        let normalized = ((total % (24 * 60)) + 24 * 60) % (24 * 60)
        return (hour: normalized / 60, minute: normalized % 60)
    }

    var earlyTimeFormatted: String {
        let c = earlyTimeComponents
        return String(format: "%02d:%02d", c.hour, c.minute)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            return true
        }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: - Schedule / Cancel

    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [earlyId, mainId])

        guard enabled, await requestAuthorization() else { return }

        let early = earlyTimeComponents
        let earlyContent = UNMutableNotificationContent()
        earlyContent.title = "晨曦在等你 🌅"
        earlyContent.body = encouragementText()
        earlyContent.sound = .default
        let earlyTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: early.hour, minute: early.minute),
            repeats: true
        )
        let earlyReq = UNNotificationRequest(identifier: earlyId, content: earlyContent, trigger: earlyTrigger)
        try? await center.add(earlyReq)

        let mainContent = UNMutableNotificationContent()
        mainContent.title = "节奏唤醒 ⏰"
        mainContent.body = "起床后做组 5-5 呼吸,开启顺畅一天。"
        mainContent.sound = .default
        let mainTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute),
            repeats: true
        )
        let mainReq = UNNotificationRequest(identifier: mainId, content: mainContent, trigger: mainTrigger)
        try? await center.add(mainReq)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [earlyId, mainId])
    }

    // MARK: - 文案根据 HRV 自适应

    private func encouragementText() -> String {
        let d = UserDefaults.standard
        let latestHRV = d.double(forKey: "latest.overnightHRV")
        let baseline  = d.double(forKey: "baseline.averageHRV")

        if baseline > 0 && latestHRV > 0 {
            let delta = (latestHRV - baseline) / baseline
            if delta > 0.10 {
                return "昨晚 HRV 比平均高 \(Int(delta * 100))%,今天能量满满。"
            } else if delta < -0.10 {
                return "昨晚恢复一般,起床后做组深呼吸帮自己回血。"
            }
        }
        return "节奏稳定,准备好开启新的一天。"
    }
}
