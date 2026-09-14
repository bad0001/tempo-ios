//
//  PaywallView.swift
//  Tempo
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var purchase = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    signatureFeatures
                    proBenefits
                    productCards
                    bottomActions
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(TempoTheme.tertiaryText)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white))
                    }
                }
            }
        }
        .task { await purchase.loadProducts() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TempoTheme.accent, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: TempoTheme.accent.opacity(0.4), radius: 16, y: 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Tempo Pro")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("解锁实时压力 + 密友共振关怀")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [TempoTheme.accent, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 核心能力

    private var signatureFeatures: some View {
        VStack(spacing: 10) {
            SignatureFeatureRow(
                icon: "heart.text.square.fill",
                title: "密友共振关怀",
                subtitle: "互看压力摘要,收发心跳、呼吸邀请和鼓励",
                gradient: [Color(hex: "EC4899"), Color(hex: "F59E0B")]
            )
            SignatureFeatureRow(
                icon: "waveform.path.ecg",
                title: "实时压力监测",
                subtitle: "结合 Apple Watch 心率、HRV 追踪压力趋势",
                gradient: [TempoTheme.accent, TempoTheme.accentLight]
            )
            SignatureFeatureRow(
                icon: "music.note.list",
                title: "节奏匹配音乐",
                subtitle: "Apple Music 或内置音景,随压力状态切换",
                gradient: [Color(hex: "8B5CF6"), Color(hex: "60A5FA")]
            )
            SignatureFeatureRow(
                icon: "sunrise.fill",
                title: "节奏唤醒",
                subtitle: "依据夜间 HRV 自适应起床",
                gradient: [Color(hex: "F59E0B"), Color(hex: "F97316")]
            )
        }
    }

    // MARK: - 其他 Pro 福利

    private var proBenefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("还包含")
                .font(.system(size: 12, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            VStack(alignment: .leading, spacing: 10) {
                BenefitRow(icon: "waveform.path.ecg", text: "实时压力监测(免费版不含)")
                BenefitRow(icon: "wind", text: "全部 6 种呼吸训练")
                BenefitRow(icon: "chart.xyaxis.line", text: "无限历史 + 周/月报")
                BenefitRow(icon: "person.2.wave.2.fill", text: "密友压力摘要和关怀通知同步")
                BenefitRow(icon: "rectangle.stack.badge.plus", text: "全规格 Complication / Widget")
                BenefitRow(icon: "bell.badge", text: "智能压力提醒")
                BenefitRow(icon: "square.and.arrow.up", text: "数据导出 CSV / JSON")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 14, y: 4)
            )
        }
    }

    // MARK: - Product cards

    @ViewBuilder
    private var productCards: some View {
        if purchase.isLoading && purchase.products.isEmpty {
            ProgressView()
                .padding(.vertical, 30)
        } else if purchase.products.isEmpty {
            VStack(spacing: 10) {
                ForEach(TempoProductID.allCases, id: \.self) { id in
                    FallbackProductCard(productID: id)
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(purchase.products, id: \.id) { product in
                    Button {
                        Task {
                            await purchase.purchase(product)
                            if purchase.isPro {
                                dismiss()
                            }
                        }
                    } label: {
                        ProductCard(product: product)
                    }
                    .buttonStyle(.tempoPress)
                }
            }
        }
    }

    // MARK: - Bottom

    private var bottomActions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchase.restore() }
            } label: {
                Text("恢复购买")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(TempoTheme.accent)
            }

            if let pending = purchase.pendingMessage {
                Text(LocalizedStringKey(pending))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            if let err = purchase.purchaseError {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Text("订阅自动续费,可在 设置 → Apple ID → 订阅 随时取消。终身买断一次性付费,永久使用。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Link("隐私政策", destination: URL(string: "https://tempo.tiyicard.cn/privacy")!)
                Link("服务条款", destination: URL(string: "https://tempo.tiyicard.cn/terms")!)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(TempoTheme.accent)
        }
    }
}

// MARK: - Signature Row

struct SignatureFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
            Text("Pro")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                    )
                )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        )
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(TempoTheme.accent)
            Text(LocalizedStringKey(text))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TempoTheme.primaryText)
            Spacer()
        }
    }
}

// MARK: - Product Card

struct ProductCard: View {
    let product: Product

    private var isYearly: Bool {
        product.id.hasSuffix("yearly")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(product.displayName)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if isYearly {
                        Text("最划算")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TempoTheme.accent))
                    }
                }
                Text(product.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
            Text(product.displayPrice)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(TempoTheme.accent)
                .monospacedDigit()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isYearly ? TempoTheme.accent : Color.clear, lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        )
    }
}

struct FallbackProductCard: View {
    let productID: TempoProductID

    private var isYearly: Bool {
        productID == .proYearly
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(productID.displayName))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if isYearly {
                        Text("最划算")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TempoTheme.accent))
                    }
                }
                Text("联网后显示 App Store 实时价格")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
            Text(productID.fallbackPrice)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(TempoTheme.tertiaryText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.7))
        )
    }
}

#Preview {
    PaywallView()
}
