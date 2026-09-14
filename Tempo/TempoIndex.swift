//
//  TempoIndex.swift
//  Tempo
//
//  「节奏指数」(0-100):综合 Recovery / Strain / StressScore 推出的统一健康分。
//  对应对手 app 的「身体年龄」hook,但 Tempo 给好听名,且不在主屏一线展示。
//

import Foundation
import SwiftUI
import TempoCore

struct TempoIndex: Hashable, Sendable {
    let value: Int                  // 0-100
    let level: TempoIndexLevel
    let timestamp: Date

    // 对算法贡献最大的因素(用于「影响因素」展示)
    let recoveryContribution: Int   // 0-50
    let stressContribution: Int     // 0-30
    let strainContribution: Int     // 0-20

    static let unknown = TempoIndex(
        value: 0,
        level: .unknown,
        timestamp: .now,
        recoveryContribution: 0,
        stressContribution: 0,
        strainContribution: 0
    )

    init(
        value: Int,
        level: TempoIndexLevel,
        timestamp: Date,
        recoveryContribution: Int,
        stressContribution: Int,
        strainContribution: Int
    ) {
        self.value = max(0, min(100, value))
        self.level = level
        self.timestamp = timestamp
        self.recoveryContribution = recoveryContribution
        self.stressContribution = stressContribution
        self.strainContribution = strainContribution
    }

    /// 综合算法:50% Recovery + 30% (1 - Stress) + 20% (1 - Strain/10)
    static func compute(
        recovery: Recovery,
        stress: StressScore?,
        strain: Strain
    ) -> TempoIndex {
        let recoveryComponent = Double(recovery.value) * 0.5
        let stressValue = Double(stress?.value ?? 50)
        let stressComponent = (100 - stressValue) * 0.3
        let strainComponent = (10 - min(10, max(0, strain.value))) * 2.0  // 0-20

        let total = recoveryComponent + stressComponent + strainComponent
        let clamped = max(0, min(100, Int(total.rounded())))

        return TempoIndex(
            value: clamped,
            level: TempoIndexLevel(score: clamped),
            timestamp: .now,
            recoveryContribution: Int(recoveryComponent.rounded()),
            stressContribution: Int(stressComponent.rounded()),
            strainContribution: Int(strainComponent.rounded())
        )
    }
}

enum TempoIndexLevel: String, CaseIterable, Sendable {
    case unknown
    case disrupted   // 0-19  节奏紊乱
    case strained    // 20-39 节奏紧绷
    case mixed       // 40-59 略有失衡
    case smooth      // 60-79 节奏轻盈
    case harmonic    // 80-100 韵律协调

    init(score: Int) {
        switch score {
        case ...19: self = .disrupted
        case 20...39: self = .strained
        case 40...59: self = .mixed
        case 60...79: self = .smooth
        default: self = .harmonic
        }
    }

    var displayName: String {
        return switch self {
        case .unknown: "等待数据"
        case .disrupted: "节奏紊乱"
        case .strained: "节奏紧绷"
        case .mixed: "略有失衡"
        case .smooth: "节奏轻盈"
        case .harmonic: "韵律协调"
        }
    }

    var tempoDisplayName: String {
        guard TempoAppLanguage.usesEnglish else { return displayName }
        return switch self {
        case .unknown: "Waiting for Data"
        case .disrupted: "Disrupted"
        case .strained: "Strained"
        case .mixed: "Slightly Imbalanced"
        case .smooth: "Balanced"
        case .harmonic: "In Harmony"
        }
    }

    var color: Color {
        switch self {
        case .unknown: TempoTheme.tertiaryText
        case .disrupted: TempoTheme.danger
        case .strained: Color(hex: "F97316")
        case .mixed: TempoTheme.warning
        case .smooth: TempoTheme.success
        case .harmonic: TempoTheme.accent
        }
    }

    var encouragement: String {
        switch self {
        case .unknown: "佩戴 Apple Watch 后开始记录"
        case .disrupted: "请尽快休息和深呼吸"
        case .strained: "适度放松,做组呼吸训练"
        case .mixed: "状态尚可,保持节奏"
        case .smooth: "今天表现轻盈"
        case .harmonic: "韵律绝佳,继续保持"
        }
    }

    var tempoEncouragement: String {
        guard TempoAppLanguage.usesEnglish else { return encouragement }
        return switch self {
        case .unknown: "Wear your Apple Watch to start tracking"
        case .disrupted: "Take a break and slow your breathing"
        case .strained: "Pause for a short breathing session"
        case .mixed: "You're doing okay—keep a steady pace"
        case .smooth: "Your rhythm feels light today"
        case .harmonic: "You're in sync—keep it going"
        }
    }
}

// MARK: - Card View

struct TempoIndexCard: View {
    let index: TempoIndex

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("节奏指数")
                        .font(.system(size: 12, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(TempoTheme.tertiaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(index.value)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundStyle(TempoTheme.primaryText)
                            .contentTransition(.numericText())
                        Text("/100")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                    Text(LocalizedStringKey(index.level.tempoDisplayName))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(index.level.color)
                }
                Spacer()

                ZStack {
                    Circle()
                        .stroke(index.level.color.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(index.value) / 100)
                        .stroke(index.level.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.6), value: index.value)
                    Image(systemName: "waveform.path")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(index.level.color)
                }
                .frame(width: 80, height: 80)
            }

            Divider()

            // 影响因素分解
            VStack(spacing: 10) {
                ContributionRow(label: "恢复", value: index.recoveryContribution, max: 50, color: TempoTheme.accent)
                ContributionRow(label: "压力", value: index.stressContribution, max: 30, color: TempoTheme.warning)
                ContributionRow(label: "负荷", value: index.strainContribution, max: 20, color: Color(hex: "F97316"))
            }

            Text(LocalizedStringKey(index.level.tempoEncouragement))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 22, padding: 18)
    }
}

private struct ContributionRow: View {
    let label: String
    let value: Int
    let max: Int
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(TempoTheme.secondaryText)
                .frame(width: 36, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(value) / CGFloat(Swift.max(1, max)), height: 6)
                }
            }
            .frame(height: 6)

            Text("+\(value)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
