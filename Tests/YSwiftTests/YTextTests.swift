import Combine
import XCTest
@testable import YSwift

class YTextTests: XCTestCase {
    var document: YDocument!
    var text: YText!

    override func setUp() {
        document = YDocument()
        text = document.getOrCreateText(named: "test")
    }

    override func tearDown() {
        document = nil
        text = nil
    }

    func test_append() {
        text.append("hello, world!")

        XCTAssertEqual(String(text), "hello, world!")
    }

    func test_appendAndInsert() throws {
        text.append("trailing text")
        text.insert("leading text, ", at: 0)

        XCTAssertEqual(String(text), "leading text, trailing text")
    }

    func test_format() {
        let expectedAttributes = ["weight": "bold"]
        var actualAttributes: [String: String] = [:]

        let subscription = text.observe { deltas in
            deltas.forEach {
                switch $0 {
                case let .retained(_, attrs):
                    actualAttributes = Dictionary(
                        uniqueKeysWithValues: attrs.map {
                            ($0, $1 as! String)
                        }
                    )
                default: break
                }
            }
        }

        text.append("abc")
        text.format(at: 0, length: 3, attributes: expectedAttributes)

        subscription.cancel()

        XCTAssertEqual(expectedAttributes, actualAttributes)
    }

    func test_insertWithAttributes() {
        let expectedAttributes = ["weight": "bold"]
        var actualAttributes: [String: String] = [:]

        let subscription = text.observe { deltas in
            deltas.forEach {
                switch $0 {
                case let .inserted(_, attrs):
                    actualAttributes = Dictionary(
                        uniqueKeysWithValues: attrs.map {
                            ($0, $1 as! String)
                        }
                    )
                default: break
                }
            }
        }

        text.insertWithAttributes("abc", attributes: expectedAttributes, at: 0)

        subscription.cancel()

        XCTAssertEqual(String(text), "abc")
        XCTAssertEqual(expectedAttributes, actualAttributes)
    }

    func test_insertEmbed() {
        let embed = TestType(name: "Aidar", age: 24)
        var insertedEmbed: TestType?

        let subscription = text.observe { deltas in
            deltas.forEach {
                switch $0 {
                case let .inserted(value, _):
                    insertedEmbed = Coder.decoded(value)
                default: break
                }
            }
        }

        text.insertEmbed(embed, at: 0)

        subscription.cancel()

        XCTAssertEqual(embed, insertedEmbed)
        XCTAssertEqual(text.length(), 1)
    }

    func test_insertEmbedWithAttributes() {
        let embed = TestType(name: "Aidar", age: 24)
        var insertedEmbed: TestType?

        let expectedAttributes = ["weight": "bold"]
        var actualAttributes: [String: String] = [:]

        let subscription = text.observe { deltas in
            deltas.forEach {
                switch $0 {
                case let .inserted(value, attrs):
                    insertedEmbed = Coder.decoded(value)
                    actualAttributes = Dictionary(
                        uniqueKeysWithValues: attrs.map {
                            ($0, $1 as! String)
                        }
                    )
                default: break
                }
            }
        }

        text.insertEmbedWithAttributes(embed, attributes: expectedAttributes, at: 0)

        subscription.cancel()

        XCTAssertEqual(embed, insertedEmbed)
        XCTAssertEqual(expectedAttributes, actualAttributes)
    }

    func test_length() throws {
        text.append("abcd")
        XCTAssertEqual(text.length(), 4)
    }

    func test_removeRange() throws {
        text.append("few apples")
        text.removeRange(start: 0, length: 4)

        XCTAssertEqual(String(text), "apples")
    }

    func test_closure_observation() {
        var insertedValue = String()

        let subscription = text.observe { deltas in
            deltas.forEach {
                switch $0 {
                case let .inserted(value, _):
                    insertedValue = Coder.decoded(value)
                default: break
                }
            }
        }

        text.append("test")

        subscription.cancel()

        XCTAssertEqual(insertedValue, "test")
    }

    /*
     https://www.swiftbysundell.com/articles/using-unit-tests-to-identify-avoid-memory-leaks-in-swift/
     https://alisoftware.github.io/swift/closures/2016/07/25/closure-capture-1/
     */

    func test_closure_observation_IsLeakingwithoutUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let subscription = text.observe { [object] deltas in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            deltas.forEach { _ in }
        }

        // When we re-assign our local strong reference to a new object the
        // weak reference should still persist.
        // Because we didn't explicitly unobserved/unsubscribed.
        object = NSObject()
        XCTAssertNotNil(weakObject)
        
        subscription.cancel()
    }

    func test_closure_observation_IsNotLeakingAfterUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let subscription = text.observe { [object] deltas in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            deltas.forEach { _ in }
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
        var insertedValue = String()

        let cancellable = text.observe().sink { deltas in
            deltas.forEach {
                switch $0 {
                case let .inserted(value, _):
                    insertedValue = Coder.decoded(value)
                default: break
                }
            }
        }

        text.append("test")

        cancellable.cancel()

        XCTAssertEqual(insertedValue, "test")
    }

    func test_observation_publisher_IsLeakingWithoutCancelling() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let cancellable = text.observe().sink { [object] changes in
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

        let cancellable = text.observe().sink { [object] changes in
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

    // MARK: - Async API Tests

    func test_asyncAppend() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("hello")
        await text.append(", world!")

        let result = await text.getStringAsync()
        XCTAssertEqual(result, "hello, world!")
    }

    func test_asyncInsert() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("world!")
        await text.insert("hello, ", at: 0)

        let result = await text.getStringAsync()
        XCTAssertEqual(result, "hello, world!")
    }

    func test_asyncRemoveRange() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("hello, world!")
        await text.removeRange(start: 5, length: 7)

        let result = await text.getStringAsync()
        XCTAssertEqual(result, "hello!")
    }

    func test_asyncLength() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("hello")
        let length = await text.lengthAsync()
        XCTAssertEqual(length, 5)
    }

    func test_asyncObserveStream_exists() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        // Test that observeAsync returns an AsyncStream
        let stream = text.observeAsync()

        // Create a task that will consume from the stream
        let task = Task {
            for await _ in stream {
                break
            }
        }

        // Cancel immediately - we just want to verify the API exists and is usable
        task.cancel()
    }

    func test_asyncFormat() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("bold text")
        await text.format(at: 0, length: 4, attributes: ["weight": "bold"])

        let diff = await text.diffAsync()
        XCTAssertFalse(diff.isEmpty)
    }

    func test_asyncInsertWithAttributes() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.insertWithAttributes("styled", attributes: ["color": "red"], at: 0)

        let result = await text.getStringAsync()
        XCTAssertEqual(result, "styled")
    }

    func test_asyncDiff() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("hello world")

        let diff = await text.diffAsync()
        XCTAssertEqual(diff.count, 1)
        if case .text(let value, _) = diff[0] {
            // The diff value is the raw text, not JSON
            XCTAssertTrue(value.contains("hello world"))
        } else {
            XCTFail("Expected text diff")
        }
    }

    func test_asyncMultipleOperations() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        // Test multiple sequential async operations
        await text.append("hello")
        await text.insert(" world", at: 5)
        await text.removeRange(start: 0, length: 6)

        let result = await text.getStringAsync()
        XCTAssertEqual(result, "world")
    }
}
