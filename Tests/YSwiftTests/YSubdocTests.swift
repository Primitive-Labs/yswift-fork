import Foundation
import XCTest
@testable import YSwift

class YSubdocTests: XCTestCase {

    // MARK: - Basic Creation Tests

    func test_subdocBasicCreation() {
        let parentDoc = YDocument()
        let subdoc = YDocument(options: YDocumentOptions(guid: "test-subdoc"))

        XCTAssertEqual(subdoc.guid, "test-subdoc")
        XCTAssertNil(subdoc.parentDocument)

        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")
        parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        // After insertion, we should be able to retrieve it
        let retrieved = parentDoc.transactSync { txn in
            array.getSubdoc(at: 0, transaction: txn)
        }

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.guid, "test-subdoc")
    }

    func test_subdocWithOptions() {
        let options = YDocumentOptions(
            autoLoad: true,
            clientId: 12345,
            guid: "custom-guid",
            shouldLoad: true
        )
        let doc = YDocument(options: options)

        XCTAssertEqual(doc.autoLoad, true)
        XCTAssertEqual(doc.clientId, 12345)
        XCTAssertEqual(doc.guid, "custom-guid")
        XCTAssertEqual(doc.shouldLoad, true)
    }

    // MARK: - Parent Relationship Tests

    func test_subdocParentRelationship() {
        let parentDoc = YDocument()
        let subdoc = YDocument(options: YDocumentOptions(guid: "child"))
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "subdocs")

        // Before insertion, subdoc has no parent
        XCTAssertNil(subdoc.parentDocument)

        // Insert subdoc
        let inserted = parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        // The inserted subdoc should have a parent
        XCTAssertNotNil(inserted.parentDocument)
        XCTAssertTrue(inserted.parentDocument!.isSame(as: parentDoc))
    }

    // MARK: - Array Insertion Tests

    func test_subdocArrayInsertion() {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        let subdoc1 = YDocument(options: YDocumentOptions(guid: "doc-1"))
        let subdoc2 = YDocument(options: YDocumentOptions(guid: "doc-2"))

        parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc1, transaction: txn)
            array.insertSubdoc(at: 1, subdoc2, transaction: txn)
        }

        let retrieved1 = array.getSubdoc(at: 0)
        let retrieved2 = array.getSubdoc(at: 1)

        XCTAssertNotNil(retrieved1)
        XCTAssertNotNil(retrieved2)
        XCTAssertEqual(retrieved1?.guid, "doc-1")
        XCTAssertEqual(retrieved2?.guid, "doc-2")
    }

    // MARK: - Map Insertion Tests

    func test_subdocMapInsertion() {
        let parentDoc = YDocument()
        let map: YMap<String> = parentDoc.getOrCreateMap(named: "docs")

        let subdoc = YDocument(options: YDocumentOptions(guid: "mapped-doc"))

        parentDoc.transactSync { txn in
            map.insertSubdoc(subdoc, forKey: "myDoc", transaction: txn)
        }

        let retrieved = map.getSubdoc(forKey: "myDoc")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.guid, "mapped-doc")
    }

    // MARK: - Subdocs Iterator Tests

    func test_subdocsIterator() {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        let subdoc1 = YDocument(options: YDocumentOptions(guid: "iter-doc-1"))
        let subdoc2 = YDocument(options: YDocumentOptions(guid: "iter-doc-2"))

        parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc1, transaction: txn)
            array.insertSubdoc(at: 1, subdoc2, transaction: txn)
        }

        // Get subdoc GUIDs
        let guids = parentDoc.subdocGuids()
        XCTAssertEqual(guids.count, 2)
        XCTAssertTrue(guids.contains("iter-doc-1"))
        XCTAssertTrue(guids.contains("iter-doc-2"))

        // Get subdocs
        let subdocs = parentDoc.subdocs()
        XCTAssertEqual(subdocs.count, 2)
    }

    // MARK: - GUID Preservation Tests

    func test_subdocGuid() {
        let customGuid = "my-unique-guid-12345"
        let doc = YDocument(options: YDocumentOptions(guid: customGuid))

        XCTAssertEqual(doc.guid, customGuid)
    }

    // MARK: - Reference Equality Tests

    func test_subdocPtrEq() {
        let doc1 = YDocument()
        let doc2 = YDocument()

        // Different documents should not be equal
        XCTAssertFalse(doc1.isSame(as: doc2))

        // Same document should be equal to itself
        XCTAssertTrue(doc1.isSame(as: doc1))

        // Inserted and retrieved subdocs should be equal
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")
        let subdoc = YDocument(options: YDocumentOptions(guid: "ptr-test"))

        let inserted = parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        let retrieved = array.getSubdoc(at: 0)!

        XCTAssertTrue(inserted.isSame(as: retrieved))
    }

    // MARK: - Observation Tests

    func test_subdocObservation() {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        var addedCount = 0
        let subscription = parentDoc.observeSubdocs { event in
            addedCount += event.added.count
        }

        let subdoc = YDocument(options: YDocumentOptions(guid: "observed-doc"))
        parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        // Give a brief moment for the event to propagate
        XCTAssertGreaterThanOrEqual(addedCount, 1)

        subscription.cancel()
    }

    // MARK: - Subdoc Data Tests

    func test_subdocWithData() {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        // Create subdoc with its own data
        let subdoc = YDocument(options: YDocumentOptions(guid: "data-doc"))
        let subdocText = subdoc.getOrCreateText(named: "content")
        subdoc.transactSync { txn in
            subdocText.append("Hello from subdoc!", in: txn)
        }

        // Insert subdoc into parent
        let inserted = parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        // Retrieve and verify content
        let retrievedText = inserted.getOrCreateText(named: "content")
        let content = inserted.transactSync { txn in
            retrievedText.getString(in: txn)
        }

        XCTAssertEqual(content, "Hello from subdoc!")
    }

    // MARK: - Memory Leak Tests

    func test_subdocMemoryLeaks() {
        let parentDoc = YDocument()
        let subdoc = YDocument(options: YDocumentOptions(guid: "leak-test"))
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        trackForMemoryLeaks(parentDoc)
        trackForMemoryLeaks(subdoc)
        trackForMemoryLeaks(array)
    }
}
