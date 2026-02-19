import Foundation
import StoreKit

/// Resolves real App Store prices for paywall rendering.
class PriceResolver {

    struct ResolvedPlan {
        let productId: String
        let displayPrice: String
        let price: Decimal
        let currencyCode: String
        let introOffer: IntroOffer?
        let isEligibleForIntroOffer: Bool
    }

    struct IntroOffer {
        let displayPrice: String
        let period: Product.SubscriptionPeriod
        let paymentMode: Product.SubscriptionOffer.PaymentMode
    }

    /// Resolve real App Store prices for a paywall config's plans.
    func resolvePrices(for plans: [[String: Any]]) async -> [ResolvedPlan] {
        let productIds = plans.compactMap { $0["product_id"] as? String }
        guard !productIds.isEmpty else { return [] }

        do {
            let products = try await Product.products(for: Set(productIds))

            return plans.compactMap { plan in
                guard let productId = plan["product_id"] as? String,
                      let product = products.first(where: { $0.id == productId }) else { return nil }

                var introOffer: IntroOffer?
                if let subOffer = product.subscription?.introductoryOffer {
                    introOffer = IntroOffer(
                        displayPrice: subOffer.displayPrice,
                        period: subOffer.period,
                        paymentMode: subOffer.paymentMode
                    )
                }

                return ResolvedPlan(
                    productId: product.id,
                    displayPrice: product.displayPrice,
                    price: product.price,
                    currencyCode: product.priceFormatStyle.currencyCode ?? "USD",
                    introOffer: introOffer,
                    isEligibleForIntroOffer: product.subscription?.isEligibleForIntroOffer ?? false
                )
            }
        } catch {
            Log.error("Failed to resolve prices: \(error)")
            return []
        }
    }
}
