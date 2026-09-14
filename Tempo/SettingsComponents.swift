//
//  SettingsComponents.swift
//  Tempo
//
//  "我的"页和设置子页共享的卡片、行、状态组件。
//

import SwiftUI

struct StatBoxCard: View {
    let value: String
    let unit: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(unit))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .tempoCard(radius: 22, padding: 14)
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var badge: Int = 0
    var iconSize: CGFloat = 38
    var titleSize: CGFloat = 16
    var verticalPadding: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SoftIconBubble(systemName: icon, color: iconColor, size: iconSize)
                Text(LocalizedStringKey(title))
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.pink))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.tempoPress)
    }
}

struct ProUpsellCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TempoTheme.accent, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("升级到 Tempo Pro")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("解锁完整趋势、实时压力与共振关怀")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TempoTheme.accent)
        }
        .tempoCard(radius: 22, padding: 18)
    }
}

struct ProActiveCard: View {
    var body: some View {
        HStack(spacing: 14) {
            SoftIconBubble(systemName: "checkmark.seal.fill", color: TempoTheme.success, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tempo Pro 已激活")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("完整趋势与共振关怀已解锁")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .tempoCard(radius: 22, padding: 18)
    }
}

struct SettingsSheetHeader: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            SoftIconBubble(systemName: icon, color: color, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SoftIconBubble(systemName: icon, color: iconColor, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer(minLength: 8)
            Toggle(isOn: $isOn) {
                Text(LocalizedStringKey(title))
            }
                .labelsHidden()
                .tint(iconColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsInlineSliderRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                SoftIconBubble(systemName: icon, color: iconColor, size: 42)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Text(valueText)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(iconColor)
            }
            Slider(value: $value, in: range, step: step)
                .tint(iconColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsSliderCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                SoftIconBubble(systemName: icon, color: iconColor, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(valueText)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(iconColor)
                }
                Spacer()
            }
            Slider(value: $value, in: range, step: step)
                .tint(iconColor)
        }
        .tempoCard(radius: 22, padding: 16)
    }
}

struct SettingsNavigationRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            SoftIconBubble(systemName: icon, color: iconColor, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct SettingsStatTile: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(TempoTheme.tertiaryText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.035), radius: 12, y: 3)
        )
    }
}

struct EmptySettingsRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            SoftIconBubble(systemName: icon, color: TempoTheme.tertiaryText, size: 42)
            Text(LocalizedStringKey(title))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsFootnoteCard: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
            Text(LocalizedStringKey(text))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .tempoCard(radius: 18, padding: 14)
    }
}

extension View {
    func settingsPanel() -> some View {
        background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 4)
        )
    }
}
