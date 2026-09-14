//
//  ECGMetrics.swift
//  TempoCore
//
//  从 Apple Watch ECG (HKElectrocardiogram, ~30s, 500Hz) 提取的高分辨率
//  HRV 指标,Apple HK 主流 SDNN 之外的「真 RMSSD」。
//
//  通常 30s ECG 含 30-40 个心拍,足够算 RMSSD / pNN50 / 短时 SDNN,
//  但 DFA α1 需要 ≥100 拍,所以这里不算 DFA(用户连续录 3 次再拼算)。
//
//  学术依据:
//   - Task Force 1996(SDNN/RMSSD/pNN50 经典定义)
//   - Munoz et al. 2015,验证 ultra-short HRV 与 5min 一致性
//

import Foundation

public struct ECGMetrics: Codable, Hashable, Sendable {
    /// 平均 R-R interval(ms)
    public let meanRR: Double
    /// SDNN(ms)— 短时整体变异性,通常 30-60ms
    public let sdnn: Double
    /// RMSSD(ms)— 短时迷走神经活动指标,通常 20-50ms
    public let rmssd: Double
    /// pNN50(%)— 相邻 RR 差 >50ms 的占比
    public let pnn50: Double
    /// R 波数(用于判断 ECG 是否足够长)
    public let beatCount: Int
    /// 平均心率(bpm)
    public let avgHeartRate: Double
    public let recordedAt: Date

    public init(
        rrIntervalsMs: [Double],
        recordedAt: Date = .now
    ) {
        guard rrIntervalsMs.count >= 5 else {
            self.meanRR = 0
            self.sdnn = 0
            self.rmssd = 0
            self.pnn50 = 0
            self.beatCount = 0
            self.avgHeartRate = 0
            self.recordedAt = recordedAt
            return
        }

        let n = Double(rrIntervalsMs.count)
        let mean = rrIntervalsMs.reduce(0, +) / n
        let variance = rrIntervalsMs.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let sdnnValue = variance.squareRoot()

        // RMSSD = sqrt( mean( (RR[i+1] - RR[i])² ) )
        var sumSquaredDiff: Double = 0
        var nn50Count: Int = 0
        for i in 1..<rrIntervalsMs.count {
            let diff = rrIntervalsMs[i] - rrIntervalsMs[i - 1]
            sumSquaredDiff += diff * diff
            if abs(diff) > 50 {
                nn50Count += 1
            }
        }
        let rmssdValue = (sumSquaredDiff / Double(rrIntervalsMs.count - 1)).squareRoot()
        let pnn50Value = Double(nn50Count) / Double(rrIntervalsMs.count - 1) * 100

        self.meanRR = mean
        self.sdnn = sdnnValue
        self.rmssd = rmssdValue
        self.pnn50 = pnn50Value
        self.beatCount = rrIntervalsMs.count
        self.avgHeartRate = 60_000.0 / max(1, mean)
        self.recordedAt = recordedAt
    }

    public var isConfident: Bool {
        beatCount >= 20 && meanRR > 300 && meanRR < 1500
    }

    public static let unknown = ECGMetrics(rrIntervalsMs: [], recordedAt: .distantPast)
}
