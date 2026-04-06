import Foundation
import XCTest
import Yniffi
@testable import YSwift

class YJsonPathTests: XCTestCase {

    // MARK: - Basic Query Tests

    func test_queryRootMap() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "user")
        doc.transactSync { txn in
            map.updateValue("Alice", forKey: "name", transaction: txn)
        }

        let results = try doc.query("$.user")
        XCTAssertEqual(results.count, 1)
        // The result should be a JSON object with name: "Alice"
        XCTAssertTrue(results[0].contains("Alice"))
    }

    func test_queryMapField() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "user")
        doc.transactSync { txn in
            map.updateValue("Bob", forKey: "name", transaction: txn)
            map.updateValue("30", forKey: "age", transaction: txn)
        }

        let results = try doc.query("$.user.name")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "\"Bob\"")
    }

    func test_queryArray() throws {
        let doc = YDocument()
        let array: YArray<String> = doc.getOrCreateArray(named: "items")
        doc.transactSync { txn in
            array.append("first", transaction: txn)
            array.append("second", transaction: txn)
            array.append("third", transaction: txn)
        }

        // Query using wildcard to get individual elements instead of the array itself
        let results = try doc.query("$.items[*]")
        XCTAssertEqual(results.count, 3)
        // Each result is a JSON-encoded string
        XCTAssertEqual(results[0], "\"first\"")
        XCTAssertEqual(results[1], "\"second\"")
        XCTAssertEqual(results[2], "\"third\"")
    }

    func test_queryArrayIndex() throws {
        let doc = YDocument()
        let array: YArray<String> = doc.getOrCreateArray(named: "items")
        doc.transactSync { txn in
            array.append("apple", transaction: txn)
            array.append("banana", transaction: txn)
            array.append("cherry", transaction: txn)
        }

        let results = try doc.query("$.items[1]")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "\"banana\"")
    }

    func test_queryArrayWildcard() throws {
        let doc = YDocument()
        let array: YArray<String> = doc.getOrCreateArray(named: "items")
        doc.transactSync { txn in
            array.append("one", transaction: txn)
            array.append("two", transaction: txn)
            array.append("three", transaction: txn)
        }

        let results = try doc.query("$.items[*]")
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0], "\"one\"")
        XCTAssertEqual(results[1], "\"two\"")
        XCTAssertEqual(results[2], "\"three\"")
    }

    // MARK: - Text Query Tests

    func test_queryText() throws {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "content")
        doc.transactSync { txn in
            text.append("Hello, World!", in: txn)
        }

        let results = try doc.query("$.content")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "\"Hello, World!\"")
    }

    // MARK: - Nested Query Tests

    func test_queryNestedStructure() throws {
        let doc = YDocument()
        let users: YArray<String> = doc.getOrCreateArray(named: "users")

        // Create JSON objects for users
        doc.transactSync { txn in
            users.append("{\"name\":\"Alice\",\"age\":30}", transaction: txn)
            users.append("{\"name\":\"Bob\",\"age\":25}", transaction: txn)
        }

        let results = try doc.query("$.users[*]")
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Error Handling Tests

    func test_invalidPathThrows() {
        let doc = YDocument()
        let _: YMap<String> = doc.getOrCreateMap(named: "test")

        XCTAssertThrowsError(try doc.query("invalid path syntax!!!")) { error in
            XCTAssertTrue(error is YrsJsonPathError)
        }
    }

    func test_emptyPathReturnsEmpty() throws {
        let doc = YDocument()

        // Empty path is technically valid but returns no results
        let results = try doc.query("")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Empty Results Tests

    func test_queryNonExistentPath() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "data")
        doc.transactSync { txn in
            map.updateValue("value", forKey: "key", transaction: txn)
        }

        let results = try doc.query("$.nonexistent")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Transaction Tests

    func test_queryWithExplicitTransaction() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "test")

        let results = doc.transactSync { txn in
            map.updateValue("hello", forKey: "greeting", transaction: txn)
            return try? doc.query("$.test.greeting", transaction: txn)
        }

        XCTAssertNotNil(results)
        XCTAssertEqual(results?.count, 1)
        XCTAssertEqual(results?[0], "\"hello\"")
    }

    // MARK: - Array Slice Tests

    func test_queryArraySlice() throws {
        let doc = YDocument()
        let array: YArray<Int> = doc.getOrCreateArray(named: "numbers")
        doc.transactSync { txn in
            array.append(1, transaction: txn)
            array.append(2, transaction: txn)
            array.append(3, transaction: txn)
            array.append(4, transaction: txn)
            array.append(5, transaction: txn)
        }

        let results = try doc.query("$.numbers[1:3]")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], "2")
        XCTAssertEqual(results[1], "3")
    }

    // MARK: - Recursive Descent Tests

    func test_queryRecursiveDescent() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "data")
        doc.transactSync { txn in
            map.updateValue("outer", forKey: "name", transaction: txn)
        }

        // This should find "name" at any depth
        let results = try doc.query("$..name")
        XCTAssertGreaterThanOrEqual(results.count, 1)
    }
}
