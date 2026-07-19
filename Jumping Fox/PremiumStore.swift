//
//  PremiumStore.swift
//  Jumping Fox
//
//  One-time Premium in-app purchase (StoreKit 2).
//  Premium unlocks 99 levels per topic, the character selector,
//  and an ad-free experience.
//

import Foundation
import Combine
import StoreKit

@MainActor
final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()
    /// Must exactly match the non-consumable Product ID in App Store Connect.
    static let productID = "premium_unlock_all"

    @Published private(set) var isPremium = false
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await listenForTransactionUpdates() }
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            // No store connection (e.g. simulator without a StoreKit config) — not fatal.
        }
        await updateEntitlement()
    }

    func purchase() async {
        guard !isPurchasing else { return }
        if product == nil { await refresh() }
        guard let product else {
            lastError = L("premium.storeUnavailable")
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isPremium = true
                    GameSettings.premiumUnlockedCache = true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await updateEntitlement()
    }

    private func updateEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isPremium = owned
        GameSettings.premiumUnlockedCache = owned
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
                await updateEntitlement()
            }
        }
    }
}
