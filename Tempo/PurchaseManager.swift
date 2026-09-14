//
//  PurchaseManager.swift
//  Tempo
//

import Foundation
import StoreKit

enum TempoProductID: String, CaseIterable {
    case proMonthly = "com.ayipocket.tempo.pro.monthly"
    case proYearly = "com.ayipocket.tempo.pro.yearly"
    case proLifetime = "com.ayipocket.tempo.pro.lifetime"

    var displayName: String {
        switch self {
        case .proMonthly: "Pro 月度"
        case .proYearly: "Pro 年度"
        case .proLifetime: "Pro 终身"
        }
    }

    var fallbackPrice: String {
        switch self {
        case .proMonthly: "¥18 / 月"
        case .proYearly: "¥98 / 年"
        case .proLifetime: "¥298 一次"
        }
    }

    var sortKey: Int {
        switch self {
        case .proMonthly: 0
        case .proYearly: 1
        case .proLifetime: 2
        }
    }
}

@Observable
@MainActor
final class PurchaseManager {
    static let shared = PurchaseManager()

    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoading = false
    var purchaseError: String?
    var pendingMessage: String?

    var isPro: Bool { !purchasedProductIDs.isEmpty }

    private init() {
        Task { [weak self] in
            await self?.observeTransactions()
        }
        Task { [weak self] in
            await self?.refreshPurchasedStatus()
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let ids = TempoProductID.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: ids)
            products = fetched.sorted { lhs, rhs in
                let l = TempoProductID(rawValue: lhs.id)?.sortKey ?? 99
                let r = TempoProductID(rawValue: rhs.id)?.sortKey ?? 99
                return l < r
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        purchaseError = nil
        pendingMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                pendingMessage = String(localized: "购买等待批准(可能是家庭共享 Ask to Buy)。家长批准后会自动激活 Pro。")
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshPurchasedStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func refreshPurchasedStatus() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                ids.insert(transaction.productID)
            }
        }
        purchasedProductIDs = ids
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(
                domain: "PurchaseManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "购买未通过验证")]
            )
        case .verified(let safe):
            return safe
        }
    }
}
