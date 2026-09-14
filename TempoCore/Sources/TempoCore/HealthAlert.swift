//
//  HealthAlert.swift
//  TempoCore
//
//  健康告警 — 跨好友共享的「事件信号」,只传 metric + severity,绝不传数值.
//  Apple HealthKit 5.1.3 红线下:派生分数(stress score)可传,raw 数据不可传,
//  但「异常事件」是 boolean / label,既不暴露数值也强化关怀.
//

import Foundation

// MARK: - Alert metric

public enum HealthAlertMetric: String, Codable, CaseIterable, Sendable {
    case heartRateHigh = "heart_rate_high"
    case heartRateLow = "heart_rate_low"
    case spo2Low = "spo2_low"

    public var label: String {
        switch self {
        case .heartRateHigh: "心率偏高"
        case .heartRateLow: "心率偏低"
        case .spo2Low: "血氧偏低"
        }
    }

    public var description: String {
        switch self {
        case .heartRateHigh: "静息状态下心率持续高于阈值"
        case .heartRateLow: "清醒时心率持续低于阈值"
        case .spo2Low: "血氧饱和度持续低于阈值"
        }
    }

    public var icon: String {
        switch self {
        case .heartRateHigh, .heartRateLow: "heart.fill"
        case .spo2Low: "lungs.fill"
        }
    }

    public var unit: String {
        switch self {
        case .heartRateHigh, .heartRateLow: "bpm"
        case .spo2Low: "%"
        }
    }

    public var defaultThreshold: Double {
        switch self {
        case .heartRateHigh: 120
        case .heartRateLow: 50
        case .spo2Low: 92
        }
    }

    /// 持续多久才算触发(秒).短暂超阈值(运动 / 紧张瞬间)不算.
    public var sustainedDuration: TimeInterval {
        switch self {
        case .heartRateHigh, .heartRateLow: 300  // 5 分钟
        case .spo2Low: 60                        // 1 分钟
        }
    }

    /// 严重等级判定:超过 critical 倍率就升级为 critical
    public func severity(forValue value: Double, threshold: Double) -> HealthAlertSeverity {
        switch self {
        case .heartRateHigh:
            return value > 140 ? .critical : .warning
        case .heartRateLow:
            return value < 40 ? .critical : .warning
        case .spo2Low:
            return value < 88 ? .critical : .warning
        }
    }

    /// 是不是"高于阈值才报警"还是"低于阈值才报警"
    public var triggersWhenAbove: Bool {
        switch self {
        case .heartRateHigh: true
        case .heartRateLow, .spo2Low: false
        }
    }
}

// MARK: - Severity

public enum HealthAlertSeverity: String, Codable, CaseIterable, Sendable {
    case warning
    case critical

    public var label: String {
        switch self {
        case .warning: "需要关注"
        case .critical: "明显异常"
        }
    }
}

// MARK: - User-facing alert message templates(给朋友看的,绝不带数值)

public enum HealthAlertMessage {
    public static func friendNotificationTitle(friendName: String, metric: HealthAlertMetric) -> String {
        "\(friendName) \(metric.label)"
    }

    public static func friendNotificationBody(metric: HealthAlertMetric, severity: HealthAlertSeverity) -> String {
        switch (metric, severity) {
        case (.heartRateHigh, .warning): "Ta 心率持续偏高,要不要发个鼓励?"
        case (.heartRateHigh, .critical): "Ta 心率明显偏高,关心一下 Ta?"
        case (.heartRateLow, .warning): "Ta 心率持续偏低,要不要问候一下?"
        case (.heartRateLow, .critical): "Ta 心率明显偏低,关心一下 Ta?"
        case (.spo2Low, .warning): "Ta 血氧偏低,提醒 Ta 深呼吸一下?"
        case (.spo2Low, .critical): "Ta 血氧明显偏低,关心一下 Ta?"
        }
    }
}
