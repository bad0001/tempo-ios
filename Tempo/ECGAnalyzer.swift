//
//  ECGAnalyzer.swift
//  Tempo
//
//  Apple Watch ECG (HKElectrocardiogram) voltage → R-peak detection → RR intervals
//  → ECGMetrics (RMSSD / SDNN / pNN50 / pNN20)。
//
//  Apple Watch ECG 参数:
//   - 单导联 Lead I 类似(.appleWatchSimilarToLeadI)
//   - 采样率 512Hz(Series 4-8)/ 也可能 256Hz,从 sample.samplingFrequency 拿
//   - 时长 30s → ~15360 samples
//   - voltage 单位 μV(微伏)
//
//  R-peak 检测策略(简化版,避免 Pan-Tompkins 整套):
//   1. 计算 voltage 的绝对值序列(避免极性)
//   2. 平滑(3 样本滑动均值)
//   3. 取全局百分位 70 作为初始 threshold
//   4. 找局部 max(threshold 之上,与前一个峰间距 ≥ 250ms = 240bpm 上限)
//   5. 自适应 threshold:每找到一个峰,threshold = 0.5 × peak_value(降低)
//

import Foundation
import HealthKit
import TempoCore

enum ECGAnalyzer {

    /// 从 HKElectrocardiogram + voltage 数组,提取 ECGMetrics
    /// - Parameters:
    ///   - ecg: HK 样本
    ///   - voltages: 时序 voltage(μV)
    static func analyze(ecg: HKElectrocardiogram, voltages: [Double]) -> ECGMetrics {
        // 1. 确定采样率
        let sampleRate = ecg.samplingFrequency?.doubleValue(for: HKUnit.hertz()) ?? 512.0
        guard sampleRate > 0, voltages.count > Int(sampleRate * 2) else {
            return .unknown
        }

        // 2. R-peak 检测
        let rPeakIndices = detectRPeaks(voltages: voltages, sampleRate: sampleRate)
        guard rPeakIndices.count >= 5 else {
            return .unknown
        }

        // 3. RR intervals(ms)
        var rrIntervals: [Double] = []
        for i in 1..<rPeakIndices.count {
            let deltaSamples = rPeakIndices[i] - rPeakIndices[i - 1]
            let deltaMs = Double(deltaSamples) / sampleRate * 1000
            // 过滤异常 RR(<300ms / >1500ms 多半是错检)
            if deltaMs > 300 && deltaMs < 1500 {
                rrIntervals.append(deltaMs)
            }
        }

        return ECGMetrics(
            rrIntervalsMs: rrIntervals,
            recordedAt: ecg.startDate
        )
    }

    // MARK: - R-peak detection

    /// 找出 voltage 序列中 R 波的 index 列表
    private static func detectRPeaks(voltages: [Double], sampleRate: Double) -> [Int] {
        guard voltages.count > 100 else { return [] }

        // 1. 取绝对值(R 波通常正向,但极性可能反)
        let abs_v = voltages.map { abs($0) }

        // 2. 简单 3-tap 平滑(减少噪声毛刺)
        var smooth = [Double](repeating: 0, count: abs_v.count)
        for i in 0..<abs_v.count {
            let left = i > 0 ? abs_v[i - 1] : abs_v[i]
            let right = i < abs_v.count - 1 ? abs_v[i + 1] : abs_v[i]
            smooth[i] = (left + abs_v[i] + right) / 3
        }

        // 3. 全局 70 百分位作为初始 threshold
        let sorted = smooth.sorted()
        let p70Idx = Int(Double(sorted.count) * 0.7)
        let initialThreshold = sorted[p70Idx]

        // 4. 找局部最大 — refractory period 250ms = 0.25 * sampleRate samples
        let refractorySamples = Int(0.25 * sampleRate)
        var peaks: [Int] = []
        var threshold = initialThreshold
        var i = 1
        while i < smooth.count - 1 {
            // 检查是否在 5 样本窗口内是局部最大,且超过 threshold
            let windowStart = max(0, i - 2)
            let windowEnd = min(smooth.count - 1, i + 2)
            var isLocalMax = true
            for j in windowStart...windowEnd where j != i {
                if smooth[j] > smooth[i] {
                    isLocalMax = false
                    break
                }
            }

            if isLocalMax && smooth[i] >= threshold {
                if let lastPeak = peaks.last {
                    if i - lastPeak >= refractorySamples {
                        peaks.append(i)
                        // 自适应:用最近 5 峰的均值更新 threshold
                        let recent = peaks.suffix(5).map { smooth[$0] }
                        let recentMean = recent.reduce(0, +) / Double(recent.count)
                        threshold = max(initialThreshold * 0.5, recentMean * 0.5)
                        i += refractorySamples
                        continue
                    }
                } else {
                    peaks.append(i)
                }
            }
            i += 1
        }

        return peaks
    }
}
