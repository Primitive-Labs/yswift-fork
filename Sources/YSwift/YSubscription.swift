import Foundation
import Yniffi

/// Handler for an active subscription.
/// Once the subscription is deinitialized, it will automatically unsubscribe.
/// You can explicitly cancel the subscription by calling `cancel`.
public final class YSubscription {
    private var subscription: Yniffi.YSubscription?

    /// The owning document's FFI exclusion lock, when the subscription
    /// came from a `YDocument` observer API. Dropping the FFI handle
    /// deregisters inside yrs, which must not overlap a transaction on
    /// another thread (#1126).
    private let lock: NSRecursiveLock?

    init(subscription: Yniffi.YSubscription, lock: NSRecursiveLock? = nil) {
        self.subscription = subscription
        self.lock = lock
    }

    public func cancel() {
        lock?.lock()
        defer { lock?.unlock() }
        subscription = nil
    }

    deinit {
        cancel()
    }
}
