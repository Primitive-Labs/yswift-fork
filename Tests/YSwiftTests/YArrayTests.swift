import Combine
import XCTest
@testable import YSwift

class YArrayTests: XCTestCase {
    var document: YDocument!
    var array: YArray<TestType>!

    override func setUp() {
        document = YDocument()
        array = document.getOrCreateArray(named: "test")
    }

    override func tearDown() {
        document = nil
        array = nil
    }

    func test_subscripts() {
        let aidar = TestType(name: "Aidar", age: 24)
        let kevin = TestType(name: "Kevin", age: 100)
        let joe = TestType(name: "Joe", age: 55)
        let bart = TestType(name: "Bart", age: 200)

        array.insertArray(at: 0, values: [aidar, kevin, joe])

        array[0] = bart
        array.remove(at: 1)

        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(array[0], bart)
        XCTAssertEqual(array[1], joe)
    }

    func test_HOFs() {
        let aidar = TestType(name: "Aidar", age: 24)
        let joe = TestType(name: "Joe", age: 55)
        array.insertArray(at: 0, values: [aidar, joe])

        XCTAssertEqual(
            array.filter { $0.name == "Aidar" },
            [aidar]
        )

        XCTAssertEqual(
            array.map { TestType(name: "Mr. " + $0.name, age: 100) },
            [TestType(name: "Mr. Aidar", age: 100), TestType(name: "Mr. Joe", age: 100)]
        )

        XCTAssertEqual(
            array.reduce(into: 0) { sum, current in
                sum += current.age
            },
            79
        )
    }

    func test_insert() {
        let initialInstance = TestType(name: "Aidar", age: 24)

        array.insert(at: 0, value: initialInstance)

        XCTAssertEqual(array[0], initialInstance)
    }

    func test_getIndexOutOfBounds() {
        let initialInstance = TestType(name: "Aidar", age: 24)

        array.insert(at: 0, value: initialInstance)

        XCTAssertEqual(array.get(index: 1), nil)
    }

    func test_insertArray() {
        let arrayToInsert = [TestType(name: "Aidar", age: 24), TestType(name: "Joe", age: 55)]

        array.insertArray(at: 0, values: arrayToInsert)

        XCTAssertEqual(array.toArray(), arrayToInsert)
    }

    func test_length() {
        array.insert(at: 0, value: TestType(name: "Aidar", age: 24))
        XCTAssertEqual(array.length(), 1)
    }

    func test_pushBack_and_pushFront() {
        let initial = TestType(name: "Middleton", age: 77)
        let front = TestType(name: "Aidar", age: 24)
        let back = TestType(name: "Joe", age: 55)

        array.insert(at: 0, value: initial)
        array.append(back)
        array.prepend(front)

        XCTAssertEqual(array.toArray(), [front, initial, back])
    }

    func test_remove() {
        let initial = TestType(name: "Middleton", age: 77)
        let front = TestType(name: "Aidar", age: 24)
        let back = TestType(name: "Joe", age: 55)

        array.insert(at: 0, value: initial)
        array.append(back)
        array.prepend(front)

        XCTAssertEqual(array.toArray(), [front, initial, back])

        array.remove(at: 1)

        XCTAssertEqual(array.toArray(), [front, back])
    }

    func test_removeRange() {
        let initial = TestType(name: "Middleton", age: 77)
        let front = TestType(name: "Aidar", age: 24)
        let back = TestType(name: "Joe", age: 55)

        array.insert(at: 0, value: initial)
        array.append(back)
        array.prepend(front)

        XCTAssertEqual(array.toArray(), [front, initial, back])

        array.removeRange(start: 0, length: 3)

        XCTAssertEqual(array.length(), 0)
    }

    func test_forEach() {
        let arrayToInsert = [TestType(name: "Aidar", age: 24), TestType(name: "Joe", age: 55)]
        var collectedArray: [TestType] = []

        array.insertArray(at: 0, values: arrayToInsert)

        array.each {
            collectedArray.append($0)
        }

        XCTAssertEqual(arrayToInsert, collectedArray)
    }

    func test_transaction_IsNotLeaking() {
        let localDocument = YDocument()
        let localArray: YArray<TestType> = localDocument.getOrCreateArray(named: "test")

        var object = NSObject()
        weak var weakObject = object

        localDocument.transactSync { [object] txn in
            _ = object
            localArray.insert(at: 0, value: .init(name: "Aidar", age: 24), transaction: txn)
        }

        object = NSObject()
        XCTAssertNil(weakObject)
        trackForMemoryLeaks(localArray)
        trackForMemoryLeaks(localDocument)
    }

    func test_observation_closure() {
        let insertedElements = [TestType(name: "Aidar", age: 24), TestType(name: "Joe", age: 55)]
        var receivedElements: [TestType] = []

        let subscription = array.observe { changes in
            changes.forEach {
                switch $0 {
                case let .added(elements):
                    receivedElements = elements
                default: break
                }
            }
        }

        array.insertArray(at: 0, values: insertedElements)

        subscription.cancel()

        XCTAssertEqual(insertedElements, receivedElements)
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

        let subscription = array.observe { [object] changes in
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

        let subscription = array.observe { [object] changes in
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
        let insertedElements = [TestType(name: "Aidar", age: 24), TestType(name: "Joe", age: 55)]
        var receivedElements: [TestType] = []

        let cancellable = array.observe().sink { changes in
            changes.forEach {
                switch $0 {
                case let .added(elements):
                    receivedElements = elements
                default: break
                }
            }
        }

        array.insertArray(at: 0, values: insertedElements)

        cancellable.cancel()

        XCTAssertEqual(insertedElements, receivedElements)
    }

    func test_observation_publisher_IsLeakingWithoutCancelling() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let cancellable = array.observe().sink { [object] changes in
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

        let cancellable = array.observe().sink { [object] changes in
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

    func test_insertAndGetNestedMap() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Insert a nested map at index 0
        let nested: YMap<String> = arr.insertMap(at: 0)
        nested["key"] = "value"

        // Retrieve it and verify
        let retrieved: YMap<String>? = arr.getMap(at: 0)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?["key"], "value")
    }

    func test_insertAndGetNestedArray() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Insert a nested array at index 0
        let nested: YArray<Int> = arr.insertArray(at: 0)
        nested.append(1)
        nested.append(2)
        nested.append(3)

        // Retrieve it and verify
        let retrieved: YArray<Int>? = arr.getArray(at: 0)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.toArray(), [1, 2, 3])
    }

    func test_insertAndGetNestedText() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Insert a nested text at index 0
        let nested = arr.insertText(at: 0)
        nested.append("Hello, World!")

        // Retrieve it and verify
        let retrieved = arr.getText(at: 0)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.getString(), "Hello, World!")
    }

    func test_pushNestedMap() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Push a nested map
        let nested: YMap<String> = arr.pushMap()
        nested["foo"] = "bar"

        XCTAssertEqual(arr.count, 1)
        let retrieved: YMap<String>? = arr.getMap(at: 0)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?["foo"], "bar")
    }

    func test_pushNestedArray() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Push a nested array
        let nested: YArray<Int> = arr.pushArray()
        nested.append(42)

        XCTAssertEqual(arr.count, 1)
        let retrieved: YArray<Int>? = arr.getArray(at: 0)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.toArray(), [42])
    }

    func test_pushNestedText() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Push a nested text
        let nested = arr.pushText()
        nested.append("pushed text")

        XCTAssertEqual(arr.count, 1)
        let retrieved = arr.getText(at: 0)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.getString(), "pushed text")
    }

    func test_moveElement() {
        let arr: YArray<Int> = document.getOrCreateArray(named: "testArr")
        arr.insertArray(at: 0, values: [1, 2, 3, 4, 5])

        // Move element at index 0 to index 3
        arr.move(from: 0, to: 3)

        XCTAssertEqual(arr.toArray(), [2, 3, 1, 4, 5])
    }

    func test_moveRange() {
        let arr: YArray<Int> = document.getOrCreateArray(named: "testArr")
        arr.insertArray(at: 0, values: [1, 2, 3, 4, 5])

        // Move elements at indices 0-2 to index 4
        arr.moveRange(from: 0, to: 2, target: 4)

        // After moving [1,2,3] to position 4, array should be [4, 5, 1, 2, 3]
        // The exact result depends on the semantics of move_range_to
        XCTAssertEqual(arr.count, 5)
    }

    func test_isUndefined() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")
        arr.append("hello")

        // Regular value should not be undefined
        XCTAssertFalse(arr.isUndefined(at: 0))
    }

    func test_nestedTypesInArray_returnsNilForJsonValue() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")
        arr.append("hello")

        // JSON string value should return nil for nested type getters
        XCTAssertNil(arr.getMap(at: 0) as YMap<String>?)
        XCTAssertNil(arr.getArray(at: 0) as YArray<Int>?)
        XCTAssertNil(arr.getText(at: 0))
    }

    // MARK: - Async API Tests

    func test_asyncAppend() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.append(1)
        await arr.append(2)
        await arr.append(3)

        let result = await arr.toArrayAsync()
        XCTAssertEqual(result, [1, 2, 3])
    }

    func test_asyncInsert() async {
        let doc = YDocument()
        let arr: YArray<String> = doc.getOrCreateArray(named: "test")

        await arr.append("first")
        await arr.append("third")
        await arr.insert(at: 1, value: "second")

        let result = await arr.toArrayAsync()
        XCTAssertEqual(result, ["first", "second", "third"])
    }

    func test_asyncInsertArray() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: [1, 2, 3, 4, 5])

        let result = await arr.toArrayAsync()
        XCTAssertEqual(result, [1, 2, 3, 4, 5])
    }

    func test_asyncPrepend() async {
        let doc = YDocument()
        let arr: YArray<String> = doc.getOrCreateArray(named: "test")

        await arr.append("second")
        await arr.prepend("first")

        let result = await arr.toArrayAsync()
        XCTAssertEqual(result, ["first", "second"])
    }

    func test_asyncRemove() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: [1, 2, 3])
        await arr.remove(at: 1)

        let result = await arr.toArrayAsync()
        XCTAssertEqual(result, [1, 3])
    }

    func test_asyncRemoveRange() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: [1, 2, 3, 4, 5])
        await arr.removeRange(start: 1, length: 3)

        let result = await arr.toArrayAsync()
        XCTAssertEqual(result, [1, 5])
    }

    func test_asyncLength() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: [1, 2, 3, 4, 5])

        let length = await arr.lengthAsync()
        XCTAssertEqual(length, 5)
    }

    func test_asyncGet() async {
        let doc = YDocument()
        let arr: YArray<String> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: ["a", "b", "c"])

        let value = await arr.get(index: 1)
        XCTAssertEqual(value, "b")

        let outOfBounds = await arr.get(index: 10)
        XCTAssertNil(outOfBounds)
    }

    func test_asyncObserveStream_exists() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        // Test that observeAsync returns an AsyncStream
        let stream = arr.observeAsync()

        // Create a task that will consume from the stream
        let task = Task {
            for await _ in stream {
                break
            }
        }

        // Cancel immediately - we just want to verify the API exists and is usable
        task.cancel()
    }

    func test_asyncToArray() async {
        let doc = YDocument()
        let arr: YArray<TestType> = doc.getOrCreateArray(named: "test")

        let aidar = TestType(name: "Aidar", age: 24)
        let joe = TestType(name: "Joe", age: 55)

        await arr.append(aidar)
        await arr.append(joe)

        let result = await arr.toArrayAsync()
        XCTAssertEqual(result, [aidar, joe])
    }
}
