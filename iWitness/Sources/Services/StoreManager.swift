import Foundation
import StoreKit

/// Manages in-app purchases and subscriptions for iWitness Pro
@MainActor
class StoreManager: ObservableObject {
    
    // MARK: - Product IDs (Security-Focused Tiers)
    
    // Core protection - one-time purchase
    static let witnessID = "com.iwitness.witness"              // $9.99 one-time
    
    // Subscription tiers - escalating security
    static let guardianMonthlyID = "com.iwitness.guardian.monthly"   // $4.99/mo
    static let guardianYearlyID = "com.iwitness.guardian.yearly"     // $39.99/yr
    static let defenderMonthlyID = "com.iwitness.defender.monthly"   // $9.99/mo
    static let defenderYearlyID = "com.iwitness.defender.yearly"     // $79.99/yr
    
    // Cloud storage add-ons
    static let cloudBasicID = "com.iwitness.cloud.10gb"        // 10GB - $1.99/mo
    static let cloudPlusID = "com.iwitness.cloud.50gb"         // 50GB - $4.99/mo
    static let cloudUnlimitedID = "com.iwitness.cloud.unlimited" // 500GB - $9.99/mo
    
    private static let productIDs: Set<String> = [
        witnessID,
        guardianMonthlyID, guardianYearlyID,
        defenderMonthlyID, defenderYearlyID,
        cloudBasicID, cloudPlusID, cloudUnlimitedID
    ]
    
    // MARK: - Published State
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Computed Properties
    
    /// User has at least Witness tier (one-time purchase)
    var hasWitness: Bool {
        purchasedProductIDs.contains(Self.witnessID) || hasGuardian || hasDefender
    }
    
    /// User has Guardian subscription
    var hasGuardian: Bool {
        purchasedProductIDs.contains(Self.guardianMonthlyID) ||
        purchasedProductIDs.contains(Self.guardianYearlyID) ||
        hasDefender
    }
    
    /// User has Defender subscription (highest tier)
    var hasDefender: Bool {
        purchasedProductIDs.contains(Self.defenderMonthlyID) ||
        purchasedProductIDs.contains(Self.defenderYearlyID)
    }
    
    var hasCloudStorage: Bool {
        purchasedProductIDs.contains(Self.cloudBasicID) ||
        purchasedProductIDs.contains(Self.cloudPlusID) ||
        purchasedProductIDs.contains(Self.cloudUnlimitedID)
    }
    
    /// For backwards compatibility
    var isPro: Bool { hasGuardian }
    
    // MARK: - Transaction Listener
    
    private var transactionListener: Task<Void, Error>?
    
    // MARK: - Initialization
    
    init() {
        transactionListener = listenForTransactions()
        
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Load Products
    
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            
            // Sort by price
            products = storeProducts.sorted { $0.price < $1.price }
            
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Purchase
    
    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Check verification
                let transaction = try checkVerified(verification)
                
                // Update purchased products
                await updatePurchasedProducts()
                
                // Finish transaction
                await transaction.finish()
                
                isLoading = false
                return transaction
                
            case .userCancelled:
                isLoading = false
                return nil
                
            case .pending:
                isLoading = false
                errorMessage = "Purchase is pending approval"
                return nil
                
            @unknown default:
                isLoading = false
                return nil
            }
            
        } catch {
            isLoading = false
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Update Purchased Products
    
    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        
        // Check all current entitlements
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                purchased.insert(transaction.productID)
            } catch {
                // Skip unverified transactions
                continue
            }
        }
        
        purchasedProductIDs = purchased
        
        // Persist for offline access
        UserDefaults.standard.set(Array(purchased), forKey: "purchased_product_ids")
    }
    
    // MARK: - Transaction Listener
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    await self.updatePurchasedProducts()
                    
                    await transaction.finish()
                } catch {
                    // Handle verification failure
                    continue
                }
            }
        }
    }
    
    // MARK: - Verification
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Errors
    
    enum StoreError: LocalizedError {
        case failedVerification
        case productNotFound
        
        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return "Transaction verification failed"
            case .productNotFound:
                return "Product not found"
            }
        }
    }
}

// MARK: - Tier-Based Feature Gating

extension StoreManager {
    
    /// Security features by tier
    enum Feature: CaseIterable {
        // Witness tier (one-time $9.99)
        case dualCamera              // Front + back recording
        case hiddenVault             // Encrypted local storage
        case emergencyAlerts         // SMS to 1 contact
        
        // Guardian tier ($4.99/mo)
        case unlimitedContacts       // Alert unlimited contacts
        case nasBackup               // WebDAV/NAS upload
        case liveLocation            // Real-time location sharing
        case quickAlerts             // Pre-written emergency messages
        
        // Defender tier ($9.99/mo)
        case liveStreaming           // HLS stream to cloud
        case cloudBackup             // iWitness Cloud storage
        case priorityUpload          // Concurrent multi-destination
        case deadManSwitch           // Auto-alert if unresponsive
        case lawyerEscalation        // Auto-notify lawyer if no safe signal
        
        /// Minimum tier required
        var requiredTier: Tier {
            switch self {
            case .dualCamera, .hiddenVault, .emergencyAlerts:
                return .witness
            case .unlimitedContacts, .nasBackup, .liveLocation, .quickAlerts:
                return .guardian
            case .liveStreaming, .cloudBackup, .priorityUpload, .deadManSwitch, .lawyerEscalation:
                return .defender
            }
        }
        
        var displayName: String {
            switch self {
            case .dualCamera: return "Dual Camera Recording"
            case .hiddenVault: return "Encrypted Vault"
            case .emergencyAlerts: return "Emergency Alerts"
            case .unlimitedContacts: return "Unlimited Contacts"
            case .nasBackup: return "NAS/WebDAV Backup"
            case .liveLocation: return "Live Location Sharing"
            case .quickAlerts: return "Quick Alert Messages"
            case .liveStreaming: return "Live Streaming"
            case .cloudBackup: return "iWitness Cloud"
            case .priorityUpload: return "Priority Multi-Upload"
            case .deadManSwitch: return "Dead Man's Switch"
            case .lawyerEscalation: return "Lawyer Auto-Escalation"
            }
        }
    }
    
    enum Tier: Int, Comparable {
        case free = 0
        case witness = 1
        case guardian = 2
        case defender = 3
        
        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        var displayName: String {
            switch self {
            case .free: return "Free"
            case .witness: return "Witness"
            case .guardian: return "Guardian"
            case .defender: return "Defender"
            }
        }
        
        var tagline: String {
            switch self {
            case .free: return "Basic Protection"
            case .witness: return "Your Phone, Your Witness"
            case .guardian: return "Complete Protection"
            case .defender: return "Maximum Security"
            }
        }
    }
    
    /// Current user tier
    var currentTier: Tier {
        if hasDefender { return .defender }
        if hasGuardian { return .guardian }
        if hasWitness { return .witness }
        return .free
    }
    
    /// Check if user can access feature
    func canAccess(_ feature: Feature) -> Bool {
        currentTier >= feature.requiredTier
    }
    
    /// Features available at current tier
    var availableFeatures: [Feature] {
        Feature.allCases.filter { canAccess($0) }
    }
    
    /// Features locked at current tier
    var lockedFeatures: [Feature] {
        Feature.allCases.filter { !canAccess($0) }
    }
}

