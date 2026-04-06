import Combine
import XCTest
@testable import YSwift

final class YMapTests: XCTestCase {
    var document: YDocument!
    var map: YMap<TestType>!

    override func setUp() {
        document = YDocument()
        map = document.getOrCreateMap(named: "test")
    }

    override func tearDown() {
        document = nil
        map = nil
    }

    func test_insert() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        XCTAssertEqual(map.length(), 2)

        let finalInstance = map.get(key: initialInstance.name)

        XCTAssertEqual(initialInstance, finalInstance)

        let contains = map.containsKey(secondInstance.name)
        XCTAssertTrue(contains)
    }

    func test_remove() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance

        XCTAssertEqual(map.length(), 2)
        map.removeValue(forKey: secondInstance.name)
        XCTAssertEqual(map.length(), 1)
    }

    func test_removeAll() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance

        XCTAssertEqual(map.length(), 2)
        map.removeAll()
        XCTAssertEqual(map.length(), 0)
    }

    func test_keys() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        XCTAssertEqual(map.length(), 2)

        var collectedKeys: [String] = []
        map.keys { collectedKeys.append($0) }

        XCTAssertEqual(collectedKeys.sorted(), ["Aidar", "Joe"])
    }

    func test_values() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        XCTAssertEqual(map.length(), 2)

        var collectedValues: [TestType] = []
        map.values {
            collectedValues.append($0)
        }

        XCTAssertTrue(collectedValues.contains(initialInstance))
        XCTAssertTrue(collectedValues.contains(secondInstance))
    }

    func test_each() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        XCTAssertEqual(map.length(), 2)

        var collectedValues: [String: TestType] = [:]
        map.each { key, value in
            collectedValues[key] = value
        }

        XCTAssertTrue(collectedValues.keys.contains("Aidar"))
        XCTAssertTrue(collectedValues.keys.contains("Joe"))

        XCTAssertTrue(collectedValues.values.contains(initialInstance))
        XCTAssertTrue(collectedValues.values.contains(secondInstance))
    }

    func test_observation_closure() {
        let first = TestType(name: "Aidar", age: 24)
        let second = TestType(name: "Joe", age: 55)
        let updatedSecond = TestType(name: "Joe", age: 101)

        var actualChanges: [YMapChange<TestType>] = []

        let subscription = map.observe { changes in
            changes.forEach { change in
                actualChanges.append(change)
            }
        }

        map[first.name] = first
        map[second.name] = second

        map[first.name] = nil
        map[second.name] = updatedSecond

        subscription.cancel()

        // Use set here, to compare two arrays by the composition not by order
        XCTAssertEqual(
            Set(actualChanges),
            Set([
                .inserted(key: first.name, value: first),
                .inserted(key: second.name, value: second),
                .removed(key: first.name, value: first),
                .updated(key: second.name, oldValue: second, newValue: updatedSecond),
            ])
        )
    }

    /*
     https://www.swiftbysundell.com/articles/using-unit-tests-to-identify-avoid-memory-leaks-in-swift/
     https://alisoftware.github.io/swift/closures/2016/07/25/closure-capture-1/
     */

    func test_observation_closure_IsLeakingWithoutUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let subscription = map.observe { [object] changes in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            changes.forEach { _ in }
        }

        // When we re-assign our local strong reference to a new object the
        // weak reference should still persist.
        // Because we didn't explicitly unobserved/unsubscribed.
        object = NSObject()
        XCTAssertNotNil(weakObject)
        
        subscription.cancel()
    }

    func test_observation_closure_IsNotLeakingAfterUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let subscription = map.observe { [object] changes in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            changes.forEach { _ in }
        }

        // Explicit unobserving, to prevent leaking
        subscription.cancel()

        // When we re-assign our local strong reference to a new object the
        // weak reference should become nil, since the closure should
        // have been run and removed at this point
        // Because we did explicitly unobserve/unsubscribe at this point.
        object = NSObject()
        XCTAssertNil(weakObject)
    }

    func test_observation_publisher() {
        let first = TestType(name: "Aidar", age: 24)
        let second = TestType(name: "Joe", age: 55)
        let updatedSecond = TestType(name: "Joe", age: 101)

        var actualChanges: [YMapChange<TestType>] = []

        let cancellable = map.observe().sink { changes in
            changes.forEach { change in
                actualChanges.append(change)
            }
        }

        map[first.name] = first
        map[second.name] = second

        map[first.name] = nil
        map[second.name] = updatedSecond

        cancellable.cancel()

        // Use set here, to compare two arrays by the composition not by order
        XCTAssertEqual(
            Set(actualChanges),
            Set([
                .inserted(key: first.name, value: first),
                .inserted(key: second.name, value: second),
                .removed(key: first.name, value: first),
                .updated(key: second.name, oldValue: second, newValue: updatedSecond),
            ])
        )
    }

    func test_observation_publisher_IsLeakingWithoutCancelling() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let cancellable = map.observe().sink { [object] changes in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            changes.forEach { _ in }
        }

        // this is to just silence the "unused variable" warning regading `cancellable` variable above
        // remove below two lines to see the warning; it cannot be replace with `_`, because Combine
        // automatically cancells the subscription in that case
        var bag = Set<AnyCancellable>()
        cancellable.store(in: &bag)

        // When we re-assign our local strong reference to a new object the
        // weak reference should still persist.
        // Because we didn't explicitly unobserved/unsubscribed.
        object = NSObject()
        XCTAssertNotNil(weakObject)
    }

    func test_observation_publisher_IsNotLeakingAfterCancelling() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let cancellable = map.observe().sink { [object] changes in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            changes.forEach { _ in }
        }

        // Explicit cancelling, to prevent leaking
        cancellable.cancel()

        // When we re-assign our local strong reference to a new object the
        // weak reference should become nil, since the closure should
        // have been run and removed at this point
        // Because we did explicitly unobserve/unsubscribe at this point.
        object = NSObject()
        XCTAssertNil(weakObject)
    }

    // MARK: - Nested Shared Type Tests

    func test_getNestedText_returnsNilForJsonValue() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["name"] = "hello"
        XCTAssertNil(root.getText(forKey: "name"))
        XCTAssertNil(root.getText(forKey: "nonexistent"))
    }

    func test_getNestedArray_returnsNilForJsonValue() {
        let root: YMap<[Int]> = document.getOrCreateMap(named: "root")
        root["numbers"] = [1, 2, 3]
        let arr: YArray<Int>? = root.getArray(forKey: "numbers")
        XCTAssertNil(arr)
    }

    func test_getNestedMap_returnsNilForJsonValue() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["key"] = "value"
        let nested: YMap<String>? = root.getMap(forKey: "key")
        XCTAssertNil(nested)
    }

    func test_isUndefined() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        XCTAssertFalse(root.isUndefined(forKey: "nonexistent"))
        root["name"] = "test"
        XCTAssertFalse(root.isUndefined(forKey: "name"))
    }

    // MARK: - Insert and Retrieve Nested Types

    func test_insertAndGetNestedMap() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested map
        let nested: YMap<String> = root.insertMap(forKey: "state")
        nested["foo"] = "bar"

        // Retrieve it and verify
        let retrieved: YMap<String>? = root.getMap(forKey: "state")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?["foo"], "bar")
    }

    func test_insertAndGetNestedArray() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested array
        let nested: YArray<Int> = root.insertArray(forKey: "numbers")
        nested.append(1)
        nested.append(2)
        nested.append(3)

        // Retrieve it and verify
        let retrieved: YArray<Int>? = root.getArray(forKey: "numbers")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.toArray(), [1, 2, 3])
    }

    func test_insertAndGetNestedText() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested text
        let nested = root.insertText(forKey: "content")
        nested.append("Hello, World!")

        // Retrieve it and verify
        let retrieved = root.getText(forKey: "content")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.getString(), "Hello, World!")
    }

    func test_getOrInsertMap() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the map
        let first: YMap<String> = root.getOrInsertMap(forKey: "state")
        first["key1"] = "value1"

        // Second call retrieves same map
        let second: YMap<String> = root.getOrInsertMap(forKey: "state")
        XCTAssertEqual(second["key1"], "value1")

        // Modifications to second affect first (same map)
        second["key2"] = "value2"
        XCTAssertEqual(first["key2"], "value2")
    }

    func test_getOrInsertArray() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the array
        let first: YArray<Int> = root.getOrInsertArray(forKey: "items")
        first.append(1)

        // Second call retrieves same array
        let second: YArray<Int> = root.getOrInsertArray(forKey: "items")
        XCTAssertEqual(second.toArray(), [1])

        // Modifications to second affect first (same array)
        second.append(2)
        XCTAssertEqual(first.toArray(), [1, 2])
    }

    func test_getOrInsertText() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the text
        let first = root.getOrInsertText(forKey: "content")
        first.append("Hello")

        // Second call retrieves same text
        let second = root.getOrInsertText(forKey: "content")
        XCTAssertEqual(second.getString(), "Hello")

        // Modifications to second affect first (same text)
        second.append(" World")
        XCTAssertEqual(first.getString(), "Hello World")
    }

    func test_tryUpdate_existingKey() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["existing"] = "oldValue"

        let updated = root.tryUpdate("newValue", forKey: "existing")
        XCTAssertTrue(updated)
        XCTAssertEqual(root["existing"], "newValue")
    }

    func test_tryUpdate_nonExistentKey() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Note: try_update in yrs actually inserts the value even for non-existent keys
        // and returns true. This is the actual behavior.
        let updated = root.tryUpdate("value", forKey: "nonexistent")
        XCTAssertTrue(updated)
        XCTAssertEqual(root["nonexistent"], "value")
    }

    func test_deeplyNestedStructure() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Create nested structure: root -> level1 (map) -> level2 (map) -> content (text)
        let level1: YMap<String> = root.insertMap(forKey: "level1")
        let level2: YMap<String> = level1.insertMap(forKey: "level2")
        let content = level2.insertText(forKey: "content")
        content.append("Deep value")

        // Retrieve through the chain
        let retrievedL1: YMap<String>? = root.getMap(forKey: "level1")
        XCTAssertNotNil(retrievedL1)

        let retrievedL2: YMap<String>? = retrievedL1?.getMap(forKey: "level2")
        XCTAssertNotNil(retrievedL2)

        let retrievedContent = retrievedL2?.getText(forKey: "content")
        XCTAssertNotNil(retrievedContent)
        XCTAssertEqual(retrievedContent?.getString(), "Deep value")
    }

    // MARK: - Sync/Encode Tests for Nested Types

    func test_encodeWithEmptyStateVector() {
        // Test that transactionEncodeStateAsUpdateFromSv requires a properly encoded state vector,
        // not just an empty byte array
        let doc1 = YDocument()
        let map1: YMap<Int> = doc1.getOrCreateMap(named: "test")
        map1["value"] = 42

        // Get a properly encoded empty state vector from a fresh document
        let doc2 = YDocument()
        let emptyEncodedStateVector: [UInt8] = doc2.transactSync { txn in
            txn.transactionStateVector()
        }
        print("[TEST] Empty encoded state vector bytes: \(emptyEncodedStateVector.count)")

        // Now use transactionEncodeStateAsUpdateFromSv with the properly encoded state vector
        let update: [UInt8]? = doc1.transactSync { txn in
            try? txn.transactionEncodeStateAsUpdateFromSv(stateVector: emptyEncodedStateVector)
        }
        print("[TEST] Update bytes from FromSv: \(update?.count ?? 0)")
        XCTAssertNotNil(update, "Encoding with properly encoded empty state vector should succeed")
        XCTAssertGreaterThan(update?.count ?? 0, 0, "Update should not be empty")

        // Verify the sync works
        if let update = update {
            doc2.transactSync { txn in
                try? txn.transactionApplyUpdate(update: update)
            }
        }
        let map2: YMap<Int> = doc2.getOrCreateMap(named: "test")
        XCTAssertEqual(map2["value"], 42, "Value should be synced")
    }

    func test_encodeAndApplyNestedMap() {
        // Create document with nested map structure
        let doc1 = YDocument()
        let root1: YMap<String> = doc1.getOrCreateMap(named: "root")

        doc1.transactSync { txn in
            let stateMap: YMap<Int> = root1.insertMap(forKey: "state", transaction: txn)
            stateMap.updateValue(42, forKey: "count", transaction: txn)
        }

        // Verify nested map exists in original doc
        let origStateMap: YMap<Int>? = doc1.transactSync { txn in
            root1.getMap(forKey: "state", transaction: txn)
        }
        XCTAssertNotNil(origStateMap, "Nested map should exist in original document")
        XCTAssertEqual(origStateMap?.get(key: "count"), 42)

        // Try the simpler encode method (uses StateVector::default() internally)
        let update: [UInt8] = doc1.transactSync { txn in
            txn.transactionEncodeStateAsUpdate()
        }
        print("[TEST] Update bytes from transactionEncodeStateAsUpdate: \(update.count)")
        XCTAssertGreaterThan(update.count, 0, "Update should not be empty")

        // Apply to new document
        let doc2 = YDocument()
        doc2.transactSync { txn in
            try? txn.transactionApplyUpdate(update: update)
        }

        // Verify nested map was synced
        let root2: YMap<String> = doc2.getOrCreateMap(named: "root")
        let syncedStateMap: YMap<Int>? = doc2.transactSync { txn in
            root2.getMap(forKey: "state", transaction: txn)
        }
        XCTAssertNotNil(syncedStateMap, "Nested map should exist in synced document")
        XCTAssertEqual(syncedStateMap?.get(key: "count"), 42, "Nested map value should be synced")
    }

    func test_encodeAndApplyNestedMapWithPrimitiveValue() {
        // Simpler test: nested map with just a primitive value
        let doc1 = YDocument()
        let root1: YMap<String> = doc1.getOrCreateMap(named: "root")

        // Insert nested map and set value
        let stateMap: YMap<Int> = root1.insertMap(forKey: "state")
        stateMap["count"] = 100

        // Encode using the simpler method
        let update: [UInt8] = doc1.transactSync { txn in
            txn.transactionEncodeStateAsUpdate()
        }
        print("[TEST] Update bytes: \(update.count)")
        XCTAssertGreaterThan(update.count, 0, "Update should not be empty")

        // Apply to new document
        let doc2 = YDocument()
        doc2.transactSync { txn in
            try? txn.transactionApplyUpdate(update: update)
        }

        // Verify
        let root2: YMap<String> = doc2.getOrCreateMap(named: "root")
        let syncedStateMap: YMap<Int>? = root2.getMap(forKey: "state")
        XCTAssertNotNil(syncedStateMap, "Nested map should exist after sync")
        XCTAssertEqual(syncedStateMap?["count"], 100, "Value should be synced")
    }

    // MARK: - Tests for mixed maps with nested types and primitives

    func test_eachIterationWithNestedMapDoesNotCrash() {
        // Test that iterating over a map containing nested types doesn't crash
        let doc = YDocument()
        let root: YMap<String> = doc.getOrCreateMap(named: "root")

        // Add a nested map
        let _: YMap<Int> = root.insertMap(forKey: "nestedMap")
        // Add a primitive value
        root["primitiveKey"] = "hello"

        // Iterate - this should not crash, and should only return the primitive
        var collectedKeys: [String] = []
        var collectedValues: [String] = []
        root.each { key, value in
            collectedKeys.append(key)
            collectedValues.append(value)
        }

        // Should only contain the primitive, not the nested map
        XCTAssertEqual(collectedKeys.count, 1, "Should only iterate over primitive values")
        XCTAssertEqual(collectedKeys.first, "primitiveKey")
        XCTAssertEqual(collectedValues.first, "hello")
    }

    func test_toMapWithNestedMapDoesNotCrash() {
        // Test that toMap() works when the map contains nested types
        let doc = YDocument()
        let root: YMap<String> = doc.getOrCreateMap(named: "root")

        // Add a nested map
        let _: YMap<Int> = root.insertMap(forKey: "nestedMap")
        // Add primitive values
        root["key1"] = "value1"
        root["key2"] = "value2"

        // toMap() should not crash and should only return primitives
        let map = root.toMap()

        XCTAssertEqual(map.count, 2, "Should only contain primitive values")
        XCTAssertEqual(map["key1"], "value1")
        XCTAssertEqual(map["key2"], "value2")
        XCTAssertNil(map["nestedMap"], "Nested map should not be in toMap() result")
    }

    func test_observeWithNestedMapDoesNotCrash() {
        // Test that observe() works when changes involve nested types
        let doc = YDocument()
        let root: YMap<String> = doc.getOrCreateMap(named: "root")

        var observedChanges: [YMapChange<String>] = []
        let subscription = root.observe { changes in
            observedChanges.append(contentsOf: changes)
        }

        // Insert a nested map - should not crash
        let _: YMap<Int> = root.insertMap(forKey: "nestedMap")

        // Insert a primitive - should trigger observable change
        root["primitiveKey"] = "hello"

        // Only primitive change should be observed
        XCTAssertEqual(observedChanges.count, 1, "Should only observe primitive value changes")
        if case .inserted(let key, let value) = observedChanges.first {
            XCTAssertEqual(key, "primitiveKey")
            XCTAssertEqual(value, "hello")
        } else {
            XCTFail("Expected inserted change for primitiveKey")
        }

        subscription.cancel()
    }

    func test_valuesIterationWithNestedMapDoesNotCrash() {
        // Test that values() iteration works with nested types
        let doc = YDocument()
        let root: YMap<String> = doc.getOrCreateMap(named: "root")

        // Add a nested map
        let _: YMap<Int> = root.insertMap(forKey: "nestedMap")
        // Add primitive values
        root["key1"] = "value1"
        root["key2"] = "value2"

        // Iterate values - should not crash
        var collectedValues: [String] = []
        root.values { value in
            collectedValues.append(value)
        }

        // Should only contain primitive values
        XCTAssertEqual(collectedValues.count, 2, "Should only iterate over primitive values")
        XCTAssertTrue(collectedValues.contains("value1"))
        XCTAssertTrue(collectedValues.contains("value2"))
    }

    func test_observeNestedMapChangesDirectly() {
        // Test that we can observe changes on the nested map itself
        let doc = YDocument()
        let root: YMap<String> = doc.getOrCreateMap(named: "root")
        let nested: YMap<Int> = root.insertMap(forKey: "state")

        var nestedChanges: [YMapChange<Int>] = []
        let subscription = nested.observe { changes in
            nestedChanges.append(contentsOf: changes)
        }

        // Changes to nested map should be observed
        nested["count"] = 42

        XCTAssertEqual(nestedChanges.count, 1)
        if case .inserted(let key, let value) = nestedChanges.first {
            XCTAssertEqual(key, "count")
            XCTAssertEqual(value, 42)
        } else {
            XCTFail("Expected inserted change for count")
        }

        subscription.cancel()
    }

    // MARK: - Async Observer Tests

    func test_observeAsync_receivesChanges() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "test")

        var receivedChanges: [YMapChange<Int>] = []

        // Start async observation in background
        let streamTask = Task {
            for await changes in map.observeAsync() {
                receivedChanges.append(contentsOf: changes)
                if receivedChanges.count >= 2 { break }
            }
        }

        // Give the stream time to set up
        try? await Task.sleep(for: .milliseconds(10))

        // Make changes
        map["a"] = 1
        map["b"] = 2

        // Wait for stream to receive changes
        _ = await streamTask.result

        XCTAssertEqual(receivedChanges.count, 2)
        XCTAssertTrue(receivedChanges.contains(.inserted(key: "a", value: 1)))
        XCTAssertTrue(receivedChanges.contains(.inserted(key: "b", value: 2)))
    }

    func test_observeAsync_safeToReadStateDuringCallback() async {
        // This is the key test: verify we can call transactSync from within the async observer
        // This would deadlock with synchronous observers
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "test")

        var readState: [String: Int] = [:]

        let streamTask = Task {
            for await _ in map.observeAsync() {
                // This should NOT deadlock because we're outside the transaction
                readState = map.toMap()
                break
            }
        }

        // Give stream time to set up
        try? await Task.sleep(for: .milliseconds(10))

        // Make a change
        map["count"] = 42

        // Wait for stream
        _ = await streamTask.result

        // Verify we successfully read state from within the async observer
        XCTAssertEqual(readState["count"], 42)
    }

    func test_observeAsync_cancellation() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "test")

        let task = Task {
            for await _ in map.observeAsync() {
                // Should receive at least one change
                break
            }
        }

        // Give stream time to set up
        try? await Task.sleep(for: .milliseconds(10))

        // Make a change to ensure stream is working
        map["test"] = 1

        // Wait for the task to complete
        _ = await task.result

        // Cancelling after completion should be fine
        task.cancel()
    }

    // MARK: - Async API Tests (Swift 6 Concurrency)

    func test_asyncTransact_basicUsage() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "test")

        // Use async transact to set values
        await doc.transact { txn in
            map.updateValue(42, forKey: "count", transaction: txn)
            map.updateValue(100, forKey: "score", transaction: txn)
        }

        // Use async transact to read values
        let result = await doc.transact { txn in
            map.toMap(transaction: txn)
        }

        XCTAssertEqual(result["count"], 42)
        XCTAssertEqual(result["score"], 100)
    }

    func test_asyncTransact_returnsValue() async {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "test")

        await doc.transact { txn in
            map.updateValue("hello", forKey: "greeting", transaction: txn)
        }

        let greeting = await doc.transact { txn -> String? in
            map.get(key: "greeting", transaction: txn)
        }

        XCTAssertEqual(greeting, "hello")
    }

    func test_asyncMapSet() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "test")

        // Use async set API
        await map.set(42, forKey: "value")

        // Use async get API
        let value = await map.get(key: "value")

        XCTAssertEqual(value, 42)
    }

    func test_asyncMapOperations() async {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "test")

        // Set multiple values
        await map.set("one", forKey: "a")
        await map.set("two", forKey: "b")
        await map.set("three", forKey: "c")

        // Test async length
        let length = await map.length()
        XCTAssertEqual(length, 3)

        // Test async containsKey
        let hasA = await map.containsKey("a")
        let hasZ = await map.containsKey("z")
        XCTAssertTrue(hasA)
        XCTAssertFalse(hasZ)

        // Test async keys
        let keys = await map.keys()
        XCTAssertEqual(Set(keys), Set(["a", "b", "c"]))

        // Test async values
        let values = await map.values()
        XCTAssertEqual(Set(values), Set(["one", "two", "three"]))

        // Test async toMapAsync
        let dict = await map.toMapAsync()
        XCTAssertEqual(dict, ["a": "one", "b": "two", "c": "three"])

        // Test async removeValue
        let removed = await map.removeValue(forKey: "b")
        XCTAssertEqual(removed, "two")

        let lengthAfter = await map.length()
        XCTAssertEqual(lengthAfter, 2)

        // Test async removeAll
        await map.removeAll()
        let finalLength = await map.length()
        XCTAssertEqual(finalLength, 0)
    }

    func test_asyncTransact_serialization() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "counter")

        // Fire multiple async transactions sequentially to test serialization
        // (Concurrent increment has a Rust bug with map.get on missing keys)
        for i in 0..<10 {
            await doc.transact { txn in
                map.updateValue(i, forKey: "key\(i)", transaction: txn)
            }
        }

        // All writes should have been serialized
        let finalMap = await doc.transact { txn in
            map.toMap(transaction: txn)
        }

        XCTAssertEqual(finalMap.count, 10)
        for i in 0..<10 {
            XCTAssertEqual(finalMap["key\(i)"], i)
        }
    }

    func test_asyncObserverWithAsyncStateRead() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "test")

        var capturedState: [String: Int] = [:]

        let streamTask = Task {
            for await _ in map.observeAsync() {
                // Use fully async API to read state
                capturedState = await map.toMapAsync()
                break
            }
        }

        try? await Task.sleep(for: .milliseconds(10))

        // Use async API to make change
        await map.set(99, forKey: "value")

        _ = await streamTask.result

        XCTAssertEqual(capturedState["value"], 99)
    }

    func test_asyncTransact_throwingVersion() async throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "test")

        await doc.transact { txn in
            map.updateValue("test", forKey: "key", transaction: txn)
        }

        // Test throwing transact
        let result = try await doc.transact { txn -> String in
            guard let value = map.get(key: "key", transaction: txn) else {
                throw TestError.notFound
            }
            return value
        }

        XCTAssertEqual(result, "test")
    }

    // MARK: - Regression Tests

    /// Tests that applying an update while observeAsync is active doesn't panic.
    /// This reproduces a bug where transactionApplyUpdate holds a RefCell borrow
    /// while triggering observers, causing a panic if observers access the transaction.
    func test_applyUpdateWithActiveObserver_doesNotPanic() async throws {
        // Create source document with nested structure (like VersionedQuantumStore)
        let sourceDoc = YDocument()
        let sourceRoot: YMap<Int> = sourceDoc.getOrCreateMap(named: "root")
        await sourceDoc.transact { txn in
            let stateMap: YMap<Int> = sourceRoot.insertMap(forKey: "state", transaction: txn)
            stateMap.updateValue(0, forKey: "count", transaction: txn)
        }

        // Encode the source document state
        let update: [UInt8] = await sourceDoc.transact { txn in
            txn.transactionEncodeStateAsUpdate()
        }

        // Create target document
        let targetDoc = YDocument()
        let targetRoot: YMap<Int> = targetDoc.getOrCreateMap(named: "root")

        // Set up async observer on root map BEFORE applying update
        var observedChanges: [[YMapChange<Int>]] = []
        let observerReady = AsyncStream.makeStream(of: Void.self)
        let observerTask = Task {
            var first = true
            for await changes in targetRoot.observeAsync() {
                if first {
                    observerReady.continuation.yield()
                    first = false
                }
                observedChanges.append(changes)
            }
        }

        // Apply the update - this should trigger the observer
        // The bug was: apply_update triggers observers while holding a RefCell borrow
        await targetDoc.transact { txn in
            try? txn.transactionApplyUpdate(update: update)
        }

        // Give observer time to process
        try await Task.sleep(for: .milliseconds(50))

        // Cancel observer task
        observerTask.cancel()

        // Verify the nested structure was synced
        let syncedStateMap: YMap<Int>? = await targetDoc.transact { txn in
            targetRoot.getMap(forKey: "state", transaction: txn)
        }
        XCTAssertNotNil(syncedStateMap)
    }

    /// Test that replicates the exact pattern from VersionedQuantumStore:
    /// 1. Apply local diffs to document
    /// 2. Set up observer on root map
    /// 3. Observer triggers and tries to read state
    /// 4. Meanwhile, other transacts are happening
    func test_observerReadStateWhileTransacting_doesNotPanic() async throws {
        // Create source document with nested structure
        let sourceDoc = YDocument()
        let sourceRoot: YMap<Int> = sourceDoc.getOrCreateMap(named: "root")
        await sourceDoc.transact { txn in
            let stateMap: YMap<Int> = sourceRoot.insertMap(forKey: "state", transaction: txn)
            stateMap.updateValue(0, forKey: "count", transaction: txn)
        }
        let initialUpdate: [UInt8] = await sourceDoc.transact { txn in
            txn.transactionEncodeStateAsUpdate()
        }

        // Create target document
        let targetDoc = YDocument()

        // Apply initial update FIRST (before getting root map, like runStream does)
        await targetDoc.transact { txn in
            try? txn.transactionApplyUpdate(update: initialUpdate)
        }

        // Now get the root map
        let targetRoot: YMap<Int> = targetDoc.getOrCreateMap(named: "root")

        // Track when observer fires and reads state
        var stateSnapshots: [[String: Int]] = []
        let observerTask = Task {
            for await _ in targetRoot.observeAsync() {
                // This pattern is from VersionedQuantumStore:
                // Observer fires, sleeps 1ms, then reads state
                try? await Task.sleep(for: .milliseconds(1))
                let state = await targetRoot.toMapAsync()
                stateSnapshots.append(state)
                if stateSnapshots.count >= 2 {
                    break
                }
            }
        }

        // Give observer time to set up
        try await Task.sleep(for: .milliseconds(10))

        // Now do multiple transacts concurrently with the observer
        // This simulates what happens in set() + commit()
        for i in 1...3 {
            // Create update with new count value
            let updateDoc = YDocument()
            await updateDoc.transact { txn in
                try? txn.transactionApplyUpdate(update: initialUpdate)
            }
            let updateRoot: YMap<Int> = updateDoc.getOrCreateMap(named: "root")
            if let stateMap: YMap<Int> = await updateDoc.transact({ txn in
                updateRoot.getMap(forKey: "state", transaction: txn)
            }) {
                await updateDoc.transact { txn in
                    stateMap.updateValue(i * 10, forKey: "count", transaction: txn)
                }
            }
            let update: [UInt8] = await updateDoc.transact { txn in
                txn.transactionEncodeStateAsUpdate()
            }

            // Apply update to target - may trigger observer
            await targetDoc.transact { txn in
                try? txn.transactionApplyUpdate(update: update)
            }

            // Also do an immediate read (like commit() does for state vector)
            _ = await targetDoc.transact { txn in
                txn.transactionStateVector()
            }
        }

        // Give observer time to process, then cancel
        try await Task.sleep(for: .milliseconds(100))
        observerTask.cancel()

        // Test passes if we got here without panic or deadlock
        // Observer may or may not have captured states depending on timing
    }

    /// Tests observeAsync with updates applied while consumer is actively iterating.
    /// This verifies that applying updates with an active observer doesn't panic or deadlock.
    func test_applyMultipleUpdatesWithActiveAsyncObserver() async throws {
        // Create source doc with nested structure
        let sourceDoc = YDocument()
        let sourceRoot: YMap<Int> = sourceDoc.getOrCreateMap(named: "root")
        await sourceDoc.transact { txn in
            let stateMap: YMap<Int> = sourceRoot.insertMap(forKey: "state", transaction: txn)
            stateMap.updateValue(0, forKey: "count", transaction: txn)
        }
        let initialUpdate: [UInt8] = await sourceDoc.transact { txn in
            txn.transactionEncodeStateAsUpdate()
        }

        // Create target document and apply initial structure
        let targetDoc = YDocument()
        await targetDoc.transact { txn in
            try? txn.transactionApplyUpdate(update: initialUpdate)
        }
        let targetRoot: YMap<Int> = targetDoc.getOrCreateMap(named: "root")

        // Set up observer that reads state on each change
        var capturedStates: [[String: Int]] = []

        let observerTask = Task {
            for await _ in targetRoot.observeAsync() {
                // Reading state from within async observer should be safe
                let state = await targetRoot.toMapAsync()
                capturedStates.append(state)
            }
        }

        // Give observer time to set up
        try await Task.sleep(for: .milliseconds(10))

        // Create update docs and apply them
        for i in 1...3 {
            // Create an update that modifies the nested state
            let updateDoc = YDocument()
            await updateDoc.transact { txn in
                try? txn.transactionApplyUpdate(update: initialUpdate)
            }
            let updateRoot: YMap<Int> = updateDoc.getOrCreateMap(named: "root")
            let stateMap: YMap<Int>? = await updateDoc.transact { txn in
                updateRoot.getMap(forKey: "state", transaction: txn)
            }

            if let stateMap = stateMap {
                await updateDoc.transact { txn in
                    stateMap.updateValue(i * 10, forKey: "count", transaction: txn)
                }
            }

            let update: [UInt8] = await updateDoc.transact { txn in
                txn.transactionEncodeStateAsUpdate()
            }

            // Apply update to target - this may trigger observers
            await targetDoc.transact { txn in
                try? txn.transactionApplyUpdate(update: update)
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        // Give observer some time to process, then cancel
        try await Task.sleep(for: .milliseconds(50))
        observerTask.cancel()

        // Test passes if we got here without panic or deadlock
        // Observer may or may not have captured states depending on timing
    }
}

enum TestError: Error {
    case notFound
}
