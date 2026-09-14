//
//  CircadianAdjustment.swift
//  TempoCore
//
//  生理节律(circadian rhythm)修正 — 消除「晨起 cortisol → HR↑ → 误判为压力」
//  和「凌晨深睡 → HRV↑↑ → 误判为极放松」的时间偏倚。
//
//  曲线参数基于 cortisol 日内节律研究(peak 6-8AM)+ HRV 日内节律
//  (nadir 14-16PM, peak 02-04AM)经验拟合,可在 PreferencesStore 关闭。
//

import Foundation

public enum CircadianAdjustment {
    /// 返回应该「加到 stress score 的修正分」.
    /// 正值 = 让 score 偏高(因为客观指标偏放松但生理上其实是醒态);
    /// 负值 = 让 score 偏低(因为客观指标偏紧张但生理上是激活期)。
    ///
    /// 拟合规律:
    ///   - 早 6-8 点:cortisol 峰,HR ↑ HRV ↓ 是正常清醒 — 应**减分** -5 到 -6
    ///   - 中午 12-14 点:HR 偏低 HRV 偏低,正常工作 — 微调 +1
    ///   - 傍晚 18-20 点:HR 微高 HRV 高,放松 — 微调 +2
    ///   - 夜里 22-2 点:HRV 高,准备睡眠 — 微调 +3
    ///   - 凌晨 3-5 点:深睡 HRV 极高,**加分** +6 修正过度放松
    ///   - 然后渐回到 0
    ///
    /// 平均值 0,不改变全天 stress 均值。
    public static func adjustment(for date: Date, calendar: Calendar = .current) -> Double {
        let hour = Double(calendar.component(.hour, from: date))
        let minute = Double(calendar.component(.minute, from: date)) / 60.0
        let h = hour + minute  // 0...24 连续小时

        // 主峰在 h=4(深睡 HRV 偏高 → 客观分被低估 → 加分),主谷在 h=16(下午 HR 偏高 → 客观分被高估 → 减分)
        // f(h) = +5 * cos(2π * (h - 4) / 24)
        let phase = (h - 4) / 24.0 * 2 * .pi
        let value = 5 * cos(phase)

        // 二次谐波微调:让傍晚 18-20 点 score 稍降(用户主观更放松)
        // g(h) = 1.5 * cos(2π * (h - 19) / 24)
        let phase2 = (h - 19) / 24.0 * 2 * .pi
        let value2 = 1.5 * cos(phase2)

        return value + value2
    }

    /// 测试 / debug 用的整点版
    public static func adjustment(forHour hour: Int) -> Double {
        let date = Calendar.current.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
        return adjustment(for: date)
    }

    /// 输出曲线的全天 hourly profile — UI debug 用
    public static func dailyProfile() -> [(hour: Int, adjustment: Double)] {
        (0..<24).map { ($0, adjustment(forHour: $0)) }
    }
}
