//
//  DesignSystem.swift
//  Tempo
//
//  Stitch / Figma 设计稿对应的视觉令牌:浅色 + 紫色 + 圆角 + 软阴影
//

import SwiftUI
import TempoCore

// MARK: - Color Hex

extension Color {
    init(hex: String) {
        var hexValue = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hexValue.hasPrefix("#") { hexValue.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: hexValue).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hexValue.count {
        case 3: (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

// MARK: - Theme Tokens

enum TempoTheme {
    // 背景
    static let background = Color(hex: "F5F7FB")
    static let cardBackground = Color.white

    // 文字
    static let primaryText = Color(hex: "1F2937")
    static let secondaryText = Color(hex: "6B7280")
    static let tertiaryText = Color(hex: "9CA3AF")

    // 主色 - Indigo / Violet
    static let accent = Color(hex: "6366F1")
    static let accentDark = Color(hex: "4F46E5")
    static let accentLight = Color(hex: "8B5CF6")
    static let accentSoft = Color(hex: "EEF2FF")

    // 状态色
    static let success = Color(hex: "10B981")
    static let successSoft = Color(hex: "D1FAE5")
    static let warning = Color(hex: "F59E0B")
    static let warningSoft = Color(hex: "FEF3C7")
    static let danger = Color(hex: "EF4444")
    static let dangerSoft = Color(hex: "FEE2E2")

    // 共振关怀分类色 — 跨 view 复用,改主题色只动这里
    static let care            = Color.pink                  // 心跳 / 鼓励
    static let breathing       = Color(hex: "8B5CF6")        // 呼吸训练 紫
    static let breathingDark   = Color(hex: "6D28D9")        // 呼吸 渐变深色
    static let meditation      = Color(hex: "10B981")        // 冥想 绿
    static let meditationDark  = Color(hex: "059669")        // 冥想 渐变深色
    static let alert           = Color(hex: "F97316")        // 健康告警 橙

    // 主按钮渐变
    static let buttonGradient = LinearGradient(
        colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
        startPoint: .leading,
        endPoint: .trailing
    )

    // 呼吸球渐变
    static let orbGradient = LinearGradient(
        colors: [Color(hex: "60A5FA"), Color(hex: "34D399")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // 压力等级 → 颜色映射
    static func stressColor(for level: StressLevel) -> Color {
        switch level {
        case .calm, .relaxed: success
        case .mild: warning
        case .high: Color(hex: "F97316")
        case .extreme: danger
        }
    }

    // 压力等级 → 鼓励文案
    static func encouragement(for level: StressLevel) -> String {
        switch level {
        case .calm: "今天表现很棒"
        case .relaxed: "状态轻松自如"
        case .mild: "略有起伏，注意休息"
        case .high: "压力上行，给自己一点缓冲"
        case .extreme: "先停下手中的事，联系可信的人"
        }
    }
}

// MARK: - Card Modifier

struct TempoCardModifier: ViewModifier {
    var radius: CGFloat = 22
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(TempoTheme.cardBackground)
                    .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 4)
            )
    }
}

extension View {
    func tempoCard(radius: CGFloat = 22, padding: CGFloat = 18) -> some View {
        modifier(TempoCardModifier(radius: radius, padding: padding))
    }
}

// MARK: - TempoPressStyle:全局按钮按下反馈(scale + 透明度 + haptic)
//
// 用法:
//   Button { ... } label: { ... }.buttonStyle(.tempoPress)
//   重按钮:  .buttonStyle(.tempoPress(.medium))
//   轻按钮:  .buttonStyle(.tempoPress(.light))   ← 默认
//   不要 haptic: .buttonStyle(.tempoPressSilent)
//
// 替换现有 .buttonStyle(.tempoPress) 即可获得 press 反馈。

#if canImport(UIKit)
import UIKit
#endif

struct TempoPressStyle: ButtonStyle {
    #if canImport(UIKit)
    var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle? = .light
    #else
    var hapticStyle: Int? = 0
    #endif
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .brightness(configuration.isPressed ? -0.018 : 0)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.10 : 0),
                radius: configuration.isPressed ? 3 : 0,
                x: 0,
                y: configuration.isPressed ? 1 : 0
            )
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                #if canImport(UIKit)
                if pressed, let s = hapticStyle {
                    UIImpactFeedbackGenerator(style: s).impactOccurred()
                }
                #endif
            }
    }
}

extension ButtonStyle where Self == TempoPressStyle {
    /// 默认轻按钮(.light haptic + 96% scale)
    static var tempoPress: TempoPressStyle { TempoPressStyle() }

    #if canImport(UIKit)
    /// 自定义 haptic 强度(.light / .medium / .heavy / .soft / .rigid)
    static func tempoPress(_ haptic: UIImpactFeedbackGenerator.FeedbackStyle) -> TempoPressStyle {
        TempoPressStyle(hapticStyle: haptic)
    }
    #endif

    /// 不带 haptic(用于密集列表项,避免 haptic 太多)
    static var tempoPressSilent: TempoPressStyle {
        TempoPressStyle(hapticStyle: nil)
    }
}

// MARK: - Common Pieces

struct SoftIconBubble: View {
    let systemName: String
    var color: Color = TempoTheme.accent
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

struct TrendBadge: View {
    let percent: Double  // 正负

    var body: some View {
        let isUp = percent >= 0
        let color: Color = isUp ? TempoTheme.danger : TempoTheme.success
        let bg: Color = isUp ? TempoTheme.dangerSoft : TempoTheme.successSoft
        return HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .bold))
            Text(String(format: "%.0f%%", abs(percent)))
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(bg))
    }
}

// MARK: - Tab Switcher Environment

private struct SwitchToTabKey: EnvironmentKey {
    static let defaultValue: ((TempoTab) -> Void) = { _ in }
}

extension EnvironmentValues {
    var switchToTab: (TempoTab) -> Void {
        get { self[SwitchToTabKey.self] }
        set { self[SwitchToTabKey.self] = newValue }
    }
}

enum TempoTab: Hashable {
    case home, trends, breathe, profile
}
