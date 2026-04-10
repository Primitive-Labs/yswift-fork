import Foundation
import XCTest
@testable import YSwift
import Yniffi

/// Tests for the transaction-aware factory methods on `YDocument`:
///
///   getOrInsertText(named:transaction:)
///   getOrInsertArray(named:transaction:)
///   getOrInsertMap(named:transaction:)
///
/// These exist to fix a long-standing footgun: the older
/// `getOrCreateText/Array/Map(named:)` methods route through `YrsDoc::get_*`,
/// which internally calls `transact_mut()` on the underlying yrs `Doc`.
/// yrs's RwLock is NOT reentrant, so calling those getters from inside an
/// already-open transaction deadlocks the calling thread against itself.
///
/// The new transaction-aware methods route through the held `TransactionMut`
/// instead and never re-acquire the doc lock — so they're safe to call from
/// inside any open transaction.
///
/// IMPORTANT: These tests use `DispatchQueue` + `DispatchSemaphore` (NOT Swift
/// Concurrency) because a Task blocked in Rust FFI on a lock cannot be
/// cancelled — `withTaskGroup` would hang forever instead of timing out.
/// With GCD, a hung worker thread is leaked at the end of the test but the
/// test itself completes and reports failure.
final class YDocumentGetOrInsertTests: XCTestCase {

    // MARK: - Repro: the OLD APIs deadlock when called inside a transaction

    /// Documents the existing footgun. This is a regression marker:
    /// `getOrCreateMap(named:)` from inside a transaction WILL deadlock.
    /// If this test ever stops timing out, someone has fixed the doc-level
    /// getter and we should celebrate.
    func test_oldGetOrCreateMapInsideTransactionDeadlocks() {
        let doc = YDocument()
        let semaphore = DispatchSemaphore(value: 0)
        var completed = false

        DispatchQueue.global(qos: .userInitiated).async {
            let txn = doc.document.transact(origin: nil)
            defer { txn.free() }

            // The old, broken pattern: doc-level get-or-create from inside an
            // open transaction. This re-enters yrs's non-reentrant lock.
            let _: YMap<String> = doc.getOrCreateMap(named: "demo")
            completed = true
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + 3)
        if result != .timedOut && completed {
            XCTFail(
                "Unexpected: getOrCreateMap inside an open transaction completed. "
                + "If yrs's lock has become reentrant or the doc-level getter "
                + "now routes through the active txn, this regression marker can be removed."
            )
        }
        // Otherwise: deadlock confirmed (expected). Worker thread is leaked.
    }

    // MARK: - The fix: the NEW APIs do NOT deadlock

    /// `getOrInsertMap(named:transaction:)` must NOT deadlock when called from
    /// inside an open transaction, because it routes through the held
    /// TransactionMut instead of taking a fresh doc lock.
    func test_newGetOrInsertMapInsideTransactionDoesNotDeadlock() {
        let doc = YDocument()
        let semaphore = DispatchSemaphore(value: 0)
        var completed = false
        var inserted: String?

        DispatchQueue.global(qos: .userInitiated).async {
            let txn = doc.document.transact(origin: nil)
            defer { txn.free() }

            // The new, safe pattern: lazily get-or-create from INSIDE the txn.
            let map: YMap<String> = doc.getOrInsertMap(named: "demo", transaction: txn)
            map.updateValue("hello", forKey: "greeting", transaction: txn)
            inserted = map.get(key: "greeting", transaction: txn)

            completed = true
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + 3)
        XCTAssertEqual(result, .success, "getOrInsertMap inside txn should not deadlock")
        XCTAssertTrue(completed)
        XCTAssertEqual(inserted, "hello")
    }

    /// Same test for text.
    func test_newGetOrInsertTextInsideTransactionDoesNotDeadlock() {
        let doc = YDocument()
        let semaphore = DispatchSemaphore(value: 0)
        var completed = false
        var content: String?

        DispatchQueue.global(qos: .userInitiated).async {
            let txn = doc.document.transact(origin: nil)
            defer { txn.free() }

            let text = doc.getOrInsertText(named: "doc", transaction: txn)
            text.append("hello, world!", in: txn)
            content = text.getString(in: txn)

            completed = true
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + 3)
        XCTAssertEqual(result, .success, "getOrInsertText inside txn should not deadlock")
        XCTAssertTrue(completed)
        XCTAssertEqual(content, "hello, world!")
    }

    /// Same test for array.
    func test_newGetOrInsertArrayInsideTransactionDoesNotDeadlock() {
        let doc = YDocument()
        let semaphore = DispatchSemaphore(value: 0)
        var completed = false
        var firstValue: String?

        DispatchQueue.global(qos: .userInitiated).async {
            let txn = doc.document.transact(origin: nil)
            defer { txn.free() }

            let array: YArray<String> = doc.getOrInsertArray(named: "items", transaction: txn)
            array.insert(at: 0, value: "first", transaction: txn)
            firstValue = array.get(index: 0, transaction: txn)

            completed = true
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + 3)
        XCTAssertEqual(result, .success, "getOrInsertArray inside txn should not deadlock")
        XCTAssertTrue(completed)
        XCTAssertEqual(firstValue, "first")
    }

    // MARK: - Idempotence

    /// Calling `getOrInsertMap` twice with the same name from inside the same
    /// transaction must return references to the same underlying shared type.
    func test_getOrInsertMapIsIdempotentWithinSameTransaction() {
        let doc = YDocument()

        doc.transactSync { txn in
            let map1: YMap<String> = doc.getOrInsertMap(named: "shared", transaction: txn)
            map1.updateValue("first", forKey: "k", transaction: txn)

            let map2: YMap<String> = doc.getOrInsertMap(named: "shared", transaction: txn)
            // Reading via map2 should see the write made via map1
            XCTAssertEqual(map2.get(key: "k", transaction: txn), "first")
        }
    }

    /// And across transactions on the same doc.
    func test_getOrInsertMapPersistsAcrossTransactions() {
        let doc = YDocument()

        doc.transactSync { txn in
            let map: YMap<String> = doc.getOrInsertMap(named: "persisted", transaction: txn)
            map.updateValue("v1", forKey: "k", transaction: txn)
        }

        doc.transactSync { txn in
            let map: YMap<String> = doc.getOrInsertMap(named: "persisted", transaction: txn)
            XCTAssertEqual(map.get(key: "k", transaction: txn), "v1")
        }
    }

    // MARK: - Cross-API compatibility

    /// A map created via the OLD getOrCreateMap (outside any txn) and a map
    /// retrieved via the NEW getOrInsertMap (inside a txn) must reference the
    /// same underlying shared type.
    func test_oldAndNewAPIsReturnSameSharedType() {
        let doc = YDocument()
        let oldMap: YMap<String> = doc.getOrCreateMap(named: "shared")

        doc.transactSync { txn in
            oldMap.updateValue("from-old", forKey: "k", transaction: txn)
        }

        doc.transactSync { txn in
            let newMap: YMap<String> = doc.getOrInsertMap(named: "shared", transaction: txn)
            XCTAssertEqual(newMap.get(key: "k", transaction: txn), "from-old")

            newMap.updateValue("from-new", forKey: "k", transaction: txn)
        }

        // The original `oldMap` reference should also see the update
        doc.transactSync { txn in
            XCTAssertEqual(oldMap.get(key: "k", transaction: txn), "from-new")
        }
    }
}
