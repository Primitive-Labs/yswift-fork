import Foundation
import XCTest
@testable import YSwift

class YDocumentTests: XCTestCase {
    func test_memoryLeaks() {
        let document = YDocument()
        let array: YArray<String> = document.getOrCreateArray(named: "array")
        let map: YMap<String> = document.getOrCreateMap(named: "map")
        let text: YText = document.getOrCreateText(named: "text")

        trackForMemoryLeaks(array)
        trackForMemoryLeaks(map)
        trackForMemoryLeaks(text)
        trackForMemoryLeaks(document)
    }

    func test_localAndRemoteSyncing() {
        let localDocument = YDocument()
        let localText = localDocument.getOrCreateText(named: "example")
        localDocument.transactSync { txn in
            localText.append("hello, world!", in: txn)
        }

        let remoteDocument = YDocument()
        let remoteText = remoteDocument.getOrCreateText(named: "example")

        let remoteState = remoteDocument.transactSync { txn in
            txn.transactionStateVector()
        }
        let updateRemote = localDocument.transactSync { txn in
            localDocument.diff(txn: txn, from: remoteState)
        }
        remoteDocument.transactSync { txn in
            try! txn.transactionApplyUpdate(update: updateRemote)
        }

        let localString = localDocument.transactSync { txn in
            localText.getString(in: txn)
        }

        let remoteString = remoteDocument.transactSync { txn in
            remoteText.getString(in: txn)
        }

        XCTAssertEqual(localString, remoteString)
    }

    func test_localAndRemoteEditingAndSyncing() {
        let localDocument = YDocument()
        let localText = localDocument.getOrCreateText(named: "example")
        localDocument.transactSync { txn in
            localText.append("hello, world!", in: txn)
        }

        let remoteDocument = YDocument()
        let remoteText = remoteDocument.getOrCreateText(named: "example")
        remoteDocument.transactSync { txn in
            remoteText.append("123456", in: txn)
        }

        let remoteState = remoteDocument.transactSync { txn in
            txn.transactionStateVector()
        }
        let updateRemote = localDocument.transactSync { txn in
            localDocument.diff(txn: txn, from: remoteState)
        }
        remoteDocument.transactSync { txn in
            try! txn.transactionApplyUpdate(update: updateRemote)
        }

        let localState = localDocument.transactSync { txn in
            txn.transactionStateVector()
        }
        let updateLocal = remoteDocument.transactSync { txn in
            localDocument.diff(txn: txn, from: localState)
        }
        localDocument.transactSync { txn in
            try! txn.transactionApplyUpdate(update: updateLocal)
        }

        let localString = localDocument.transactSync { txn in
            localText.getString(in: txn)
        }

        let remoteString = remoteDocument.transactSync { txn in
            remoteText.getString(in: txn)
        }

        XCTAssertEqual(localString, remoteString)
    }

    // MARK: - Async API Tests

    func test_asyncTransact_basicUsage() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await doc.transact { txn in
            text.append("hello", in: txn)
        }

        let result = await doc.transact { txn in
            text.getString(in: txn)
        }

        XCTAssertEqual(result, "hello")
    }

    func test_asyncTransact_syncing() async {
        let localDoc = YDocument()
        let localText = localDoc.getOrCreateText(named: "example")

        await localDoc.transact { txn in
            localText.append("async hello!", in: txn)
        }

        let remoteDoc = YDocument()
        let remoteText = remoteDoc.getOrCreateText(named: "example")

        // Get state and diff using async transact
        let remoteState = await remoteDoc.transact { txn in
            txn.transactionStateVector()
        }

        let update = await localDoc.transact { txn in
            localDoc.diff(txn: txn, from: remoteState)
        }

        await remoteDoc.transact { txn in
            try! txn.transactionApplyUpdate(update: update)
        }

        let remoteString = await remoteDoc.transact { txn in
            remoteText.getString(in: txn)
        }

        XCTAssertEqual(remoteString, "async hello!")
    }

    func test_asyncTransact_multipleOperations() async {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "data")

        // Run multiple sequential async transactions
        for i in 0..<5 {
            await doc.transact { txn in
                map.updateValue("value\(i)", forKey: "key\(i)", transaction: txn)
            }
        }

        let finalMap = await doc.transact { txn in
            map.toMap(transaction: txn)
        }

        // All operations should have completed
        XCTAssertEqual(finalMap.count, 5)
        for i in 0..<5 {
            XCTAssertEqual(finalMap["key\(i)"], "value\(i)")
        }
    }

    func test_queryAsync() async throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "users")

        await doc.transact { txn in
            map.updateValue("Alice", forKey: "name", transaction: txn)
            map.updateValue("alice@example.com", forKey: "email", transaction: txn)
        }

        // Test async query
        let results = try await doc.queryAsync("$.users.name")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first, "\"Alice\"")
    }

    func test_queryAsync_multipleResults() async throws {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "numbers")

        await doc.transact { txn in
            map.updateValue(1, forKey: "a", transaction: txn)
            map.updateValue(2, forKey: "b", transaction: txn)
            map.updateValue(3, forKey: "c", transaction: txn)
        }

        // Query all values in the map
        let results = try await doc.queryAsync("$.numbers.*")
        XCTAssertEqual(results.count, 3)
    }

    // MARK: - Async Subdoc Tests

    func test_subdocGuidsAsync() async {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        let subdoc1 = YDocument(options: YDocumentOptions(guid: "async-doc-1"))
        let subdoc2 = YDocument(options: YDocumentOptions(guid: "async-doc-2"))

        await parentDoc.transact { txn in
            array.insertSubdoc(at: 0, subdoc1, transaction: txn)
            array.insertSubdoc(at: 1, subdoc2, transaction: txn)
        }

        let guids = await parentDoc.subdocGuidsAsync()
        XCTAssertEqual(guids.count, 2)
        XCTAssertTrue(guids.contains("async-doc-1"))
        XCTAssertTrue(guids.contains("async-doc-2"))
    }

    func test_subdocsAsync() async {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        let subdoc1 = YDocument(options: YDocumentOptions(guid: "subdoc-a"))
        let subdoc2 = YDocument(options: YDocumentOptions(guid: "subdoc-b"))
        let subdoc3 = YDocument(options: YDocumentOptions(guid: "subdoc-c"))

        await parentDoc.transact { txn in
            array.insertSubdoc(at: 0, subdoc1, transaction: txn)
            array.insertSubdoc(at: 1, subdoc2, transaction: txn)
            array.insertSubdoc(at: 2, subdoc3, transaction: txn)
        }

        let subdocs = await parentDoc.subdocsAsync()
        XCTAssertEqual(subdocs.count, 3)

        let retrievedGuids = subdocs.map { $0.guid }
        XCTAssertTrue(retrievedGuids.contains("subdoc-a"))
        XCTAssertTrue(retrievedGuids.contains("subdoc-b"))
        XCTAssertTrue(retrievedGuids.contains("subdoc-c"))
    }

    func test_subdocsAsync_withData() async {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        // Create subdoc with its own data
        let subdoc = YDocument(options: YDocumentOptions(guid: "data-subdoc"))
        let subdocText = subdoc.getOrCreateText(named: "content")
        await subdoc.transact { txn in
            subdocText.append("Async subdoc content!", in: txn)
        }

        // Insert subdoc into parent
        await parentDoc.transact { txn in
            _ = array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        // Retrieve via async subdocs and verify content
        let subdocs = await parentDoc.subdocsAsync()
        XCTAssertEqual(subdocs.count, 1)

        let retrieved = subdocs.first!
        let retrievedText = retrieved.getOrCreateText(named: "content")
        let content = await retrieved.transact { txn in
            retrievedText.getString(in: txn)
        }

        XCTAssertEqual(content, "Async subdoc content!")
    }
}
