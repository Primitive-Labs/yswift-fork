import XCTest
@testable import YSwift

/// Regression tests for Primitive-Labs/js-bao-wss#1126: observer
/// (de)registration racing a transaction on the same doc from another
/// thread panicked inside yrs (the FFI layer `.expect()`s the store
/// borrow), aborting the host process. Pre-fix these tests crash the
/// test runner with SIGABRT within a few hundred iterations; post-fix
/// (per-doc FFI exclusion lock) they pass.
final class ConcurrentAccessTests: XCTestCase {
    /// Mirrors the StoryLens TestFlight crash: one thread registers a
    /// doc-update observer (DynamicModel.init / DocumentManager open
    /// path) while another runs `transactSync` writes on the same doc.
    func testObserverRegistrationDoesNotRaceTransactions() {
        let doc = YDocument()
        let iterations = 2_000

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                let subscription = doc.observeUpdate { _ in }
                subscription.cancel()
            } else {
                doc.transactSync { txn in
                    let text = doc.getOrInsertText(named: "t", transaction: txn)
                    text.append("x", in: txn)
                }
            }
        }
    }

    /// Raw `YrsDoc` transactions (the syncQueue-bypass paths in
    /// JsBaoClient / DocumentManager) must also exclude observer
    /// registration when bracketed with `withExclusiveAccess`.
    func testRawTransactionsViaExclusiveAccessDoNotRaceRegistration() {
        let doc = YDocument()
        let iterations = 2_000

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                let subscription = doc.observeUpdate { _ in }
                subscription.cancel()
            } else {
                doc.withExclusiveAccess {
                    let txn = doc.document.transact(origin: nil)
                    defer { txn.free() }
                    _ = txn.transactionEncodeStateAsUpdate()
                }
            }
        }
    }

    /// Concurrent registrations alone also conflicted (registration
    /// internally acquires a transaction) — crashes 1 & 3 in the report.
    func testConcurrentObserverRegistration() {
        let doc = YDocument()
        let iterations = 2_000

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let subscription = doc.observeUpdate { _ in }
            subscription.cancel()
        }
    }
}
