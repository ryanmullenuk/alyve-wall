import Foundation
import Observation
import StoreKit

/// ALYVE WALL Premium: a single £1.99 non-consumable purchase that removes the watermark and
/// unlocks every export size, 60 fps and the Full HD Live Photo.
@MainActor
@Observable
final class PremiumStore {
    static let productID = "games.redhead.alyvewall.premium"
    static let fallbackPrice = "£1.99"
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private(set) var product: Product?
    private(set) var isPremium = false
    private(set) var isWorking = false
    var message: String?

    /// True in Debug builds and in TestFlight builds archived with the TESTER flag, which adds a
    /// switch to unlock Premium without paying. App Store builds don't have it.
    static var isTesterBuild: Bool {
        #if DEBUG || TESTER
        return true
        #else
        return false
        #endif
    }

    private static let testerKey = "alyvewall.testerPremium"
    private(set) var testerUnlocked = false
    private var purchased = false
    private var updates: Task<Void, Never>?

    init() {
        if Self.isTesterBuild { testerUnlocked = UserDefaults.standard.bool(forKey: Self.testerKey) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-forcePremium") { testerUnlocked = true }
        #endif
        isPremium = testerUnlocked
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { await load() }
    }

    var price: String { product?.displayPrice ?? Self.fallbackPrice }

    func setTesterPremium(_ on: Bool) {
        guard Self.isTesterBuild else { return }
        testerUnlocked = on
        UserDefaults.standard.set(on, forKey: Self.testerKey)
        isPremium = purchased || testerUnlocked
    }

    func load() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            product = nil
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { owned = true }
        }
        purchased = owned
        isPremium = owned || testerUnlocked
    }

    func purchase() async {
        message = nil
        if product == nil { await load() }
        guard let product else {
            message = "The App Store isn't available right now. Please try again in a moment."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification { await t.finish() }
                await refreshEntitlements()
                if isPremium { message = "Premium unlocked. Thank you!" }
            case .pending:
                message = "Your purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        message = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch {
            message = error.localizedDescription
            return
        }
        await refreshEntitlements()
        message = isPremium ? "Premium restored." : "No previous purchase was found for this Apple Account."
    }
}
