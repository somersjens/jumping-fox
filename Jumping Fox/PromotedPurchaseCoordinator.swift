//
//  PromotedPurchaseCoordinator.swift
//  Jumping Fox
//
//  Defers App Store promoted IAP payments until the parental gate is passed.
//

import Combine
import StoreKit

@MainActor
final class PromotedPurchaseCoordinator: NSObject, ObservableObject {
    static let shared = PromotedPurchaseCoordinator()

    @Published private(set) var isAwaitingParentApproval = false

    private var deferredPayment: SKPayment?

    private override init() {
        super.init()
    }

    /// Install this as early as possible so a promoted App Store purchase can
    /// never enter the payment queue before the app presents its parental gate.
    func startListening() {
        SKPaymentQueue.default().delegate = self
        // Ensure StoreKit 2 transaction updates are observed even when the app
        // was opened directly from the App Store before the main UI is visible.
        _ = PremiumStore.shared
    }

    func approveDeferredPurchase() {
        guard let deferredPayment else { return }
        self.deferredPayment = nil
        isAwaitingParentApproval = false
        SKPaymentQueue.default().add(deferredPayment)
    }

    func cancelDeferredPurchase() {
        deferredPayment = nil
        isAwaitingParentApproval = false
    }
}

extension PromotedPurchaseCoordinator: SKPaymentQueueDelegate {
    func paymentQueue(_ paymentQueue: SKPaymentQueue,
                      shouldAddStorePayment payment: SKPayment,
                      for product: SKProduct) -> Bool {
        // Returning false prevents StoreKit from starting the promoted payment.
        // It is only added back to the queue after adult approval above.
        // Keep this in sync with `PremiumStore.productID`.
        guard product.productIdentifier == "premium_unlock_all" else { return false }
        // A newer App Store request replaces an older, still-deferred one.
        deferredPayment = payment
        isAwaitingParentApproval = true
        return false
    }
}
