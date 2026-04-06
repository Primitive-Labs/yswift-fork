import Combine
import Foundation
import Yniffi

/// A type that provides a list shared data type.
///
/// Store, order, and retrieve any single `Codable` type within a `YArray`.
///
/// Create a new `YArray` instance using ``YSwift/YDocument/getOrCreateArray(named:)`` from a ``YDocument``.
public final class YArray<T: Codable>: Transactable, YCollection, @unchecked Sendable {
    private let _array: YrsArray
    let document: YDocument

    init(array: YrsArray, document: YDocument) {
        _array = array
        self.document = document
    }

    // MARK: - Async APIs (Preferred)

    /// Returns the object at the index location asynchronously.
    /// - Parameter index: The location in the list to retrieve.
    /// - Returns: The instance at the location, or `nil` if unavailable.
    public func get(index: Int) async -> T? where T: Sendable {
        await document.transact { txn in
            if let result = try? self._array.get(tx: txn, index: UInt32(index)) {
                return Coder.decoded(result) as T?
            } else {
                return nil
            }
        }
    }

    /// Insert an object at an index location asynchronously.
    /// - Parameters:
    ///   - index: The location in the list to insert the object.
    ///   - value: The object to insert.
    public func insert(at index: Int, value: T) async where T: Sendable {
        await document.transact { txn in
            self._array.insert(tx: txn, index: UInt32(index), value: Coder.encoded(value))
        }
    }

    /// Inserts an array of objects at the index location asynchronously.
    /// - Parameters:
    ///   - index: The location in the list to insert the objects.
    ///   - values: An array of objects to insert.
    public func insertArray(at index: Int, values: [T]) async where T: Sendable {
        await document.transact { txn in
            self._array.insertRange(tx: txn, index: UInt32(index), values: Coder.encodedArray(values))
        }
    }

    /// Append an object to the end of the list asynchronously.
    /// - Parameter value: The object to insert.
    public func append(_ value: T) async where T: Sendable {
        await document.transact { txn in
            self._array.pushBack(tx: txn, value: Coder.encoded(value))
        }
    }

    /// Prepends an object at the beginning of the list asynchronously.
    /// - Parameter value: The object to insert.
    public func prepend(_ value: T) async where T: Sendable {
        await document.transact { txn in
            self._array.pushFront(tx: txn, value: Coder.encoded(value))
        }
    }

    /// Remove an object from the list asynchronously.
    /// - Parameter index: The index location of the object to remove.
    public func remove(at index: Int) async where T: Sendable {
        await document.transact { txn in
            self._array.remove(tx: txn, index: UInt32(index))
        }
    }

    /// Removes a range of objects from the list asynchronously.
    /// - Parameters:
    ///   - start: The index location of the first object to remove.
    ///   - length: The number of objects to remove.
    public func removeRange(start: Int, length: Int) async where T: Sendable {
        await document.transact { txn in
            self._array.removeRange(tx: txn, index: UInt32(start), len: UInt32(length))
        }
    }

    /// Returns the length of the list asynchronously.
    public func lengthAsync() async -> UInt32 where T: Sendable {
        await document.transact { txn in
            self._array.length(tx: txn)
        }
    }

    /// Returns the contents of the list as an array asynchronously.
    public func toArrayAsync() async -> [T] where T: Sendable {
        await document.transact { txn in
            Coder.decodedArray(self._array.toA(tx: txn))
        }
    }

    /// Returns an async stream of array changes.
    public func observeAsync() -> AsyncStream<[YArrayChange<T>]> where T: Sendable {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let subscription = self.observe { changes in
                continuation.yield(changes)
            }
            continuation.onTermination = { _ in
                subscription.cancel()
            }
        }
    }

    // MARK: - Sync APIs (Deprecated)

    /// The length of the list.
    public var count: Int {
        Int(length())
    }

    /// A Boolean value that indicates whether the list is empty.
    public var isEmpty: Bool {
        length() == 0
    }

    /// Returns the object at the index location you provide.
    /// - Warning: Deprecated. Use async `get(index:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - index: The location in the list to retrieve.
    ///   - transaction: An optional transaction to use when retrieving an object.
    /// - Returns: Returns the instance of a Codable type that was stored at the location you provided, or `nil` if it isn't available or couldn't be decoded.
    @available(*, deprecated, message: "Use async get(index:) or pass explicit transaction")
    public func get(index: Int, transaction: YrsTransaction? = nil) -> T? {
        withTransaction(transaction) { txn in
            if let result = try? self._array.get(tx: txn, index: UInt32(index)) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Insert an object at an index location you provide.
    /// - Warning: Deprecated. Use async `insert(at:value:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - index: The location in the list to insert the object.
    ///   - value: The object to insert.
    ///   - transaction: An optional transaction to use when retrieving an object.
    @available(*, deprecated, message: "Use async insert(at:value:) or pass explicit transaction")
    public func insert(at index: Int, value: T, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._array.insert(tx: txn, index: UInt32(index), value: Coder.encoded(value))
        }
    }

    /// Inserts an array of objects at the index location you provide.
    /// - Warning: Deprecated. Use async `insertArray(at:values:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - index: The location in the list to insert the objects.
    ///   - values: An array of objects to insert.
    ///   - transaction: An optional transaction to use when retrieving an object.
    @available(*, deprecated, message: "Use async insertArray(at:values:) or pass explicit transaction")
    public func insertArray(at index: Int, values: [T], transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._array.insertRange(tx: txn, index: UInt32(index), values: Coder.encodedArray(values))
        }
    }

    /// Append an object to the end of the list.
    /// - Warning: Deprecated. Use async `append(_:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - value: The object to insert.
    ///   - transaction: An optional transaction to use when retrieving an object.
    @available(*, deprecated, message: "Use async append(_:) or pass explicit transaction")
    public func append(_ value: T, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._array.pushBack(tx: txn, value: Coder.encoded(value))
        }
    }

    /// Prepends an object at the beginning of the list.
    /// - Warning: Deprecated. Use async `prepend(_:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - value: The object to insert.
    ///   - transaction: An optional transaction to use when retrieving an object.
    @available(*, deprecated, message: "Use async prepend(_:) or pass explicit transaction")
    public func prepend(_ value: T, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._array.pushFront(tx: txn, value: Coder.encoded(value))
        }
    }

    /// Remove an object from the list.
    /// - Warning: Deprecated. Use async `remove(at:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - index: The index location of the object to remove.
    ///   - transaction: An optional transaction to use when retrieving an object.
    @available(*, deprecated, message: "Use async remove(at:) or pass explicit transaction")
    public func remove(at index: Int, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._array.remove(tx: txn, index: UInt32(index))
        }
    }

    /// Removes a range of objects from the list, starting at the index position and for the number of elements you provide.
    /// - Warning: Deprecated. Use async `removeRange(start:length:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - start: The index location of the first object to remove.
    ///   - length: The number of objects to remove.
    ///   - transaction: An optional transaction to use when retrieving an object.
    @available(*, deprecated, message: "Use async removeRange(start:length:) or pass explicit transaction")
    public func removeRange(start: Int, length: Int, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._array.removeRange(tx: txn, index: UInt32(start), len: UInt32(length))
        }
    }

    /// Returns the length of the list.
    /// - Warning: Deprecated. Use async `lengthAsync()` or pass an explicit transaction.
    /// - Parameter transaction: An optional transaction to use when retrieving an object.
    @available(*, deprecated, message: "Use async lengthAsync() or pass explicit transaction")
    public func length(transaction: YrsTransaction? = nil) -> UInt32 {
        withTransaction(transaction) { txn in
            self._array.length(tx: txn)
        }
    }

    /// Returns the contents of the list as an array of objects.
    /// - Warning: Deprecated. Use async `toArrayAsync()` or pass an explicit transaction.
    /// - Parameter transaction: An optional transaction to use when retrieving an object.
    @available(*, deprecated, message: "Use async toArrayAsync() or pass explicit transaction")
    public func toArray(transaction: YrsTransaction? = nil) -> [T] {
        withTransaction(transaction) { txn in
            Coder.decodedArray(self._array.toA(tx: txn))
        }
    }

    /// Iterates over the list of elements, providing each element to the closure you provide.
    /// - Warning: Deprecated. Use async `toArrayAsync()` and iterate the result instead.
    /// - Parameters:
    ///   - transaction: An optional transaction to use when retrieving an object.
    ///   - body: A closure that is called repeatedly with each element in the list.
    @available(*, deprecated, message: "Use async toArrayAsync() and iterate instead")
    public func each(transaction: YrsTransaction? = nil, _ body: @escaping (T) -> Void) {
        let delegate = YArrayEachDelegate(callback: body, decoded: Coder.decoded)
        withTransaction(transaction) { txn in
            self._array.each(tx: txn, delegate: delegate)
        }
    }

    /// Returns a publisher of array changes.
    /// - Warning: Deprecated. Use `observeAsync()` instead.
    @available(*, deprecated, message: "Use observeAsync() instead")
    public func observe() -> AnyPublisher<[YArrayChange<T>], Never> {
        let subject = PassthroughSubject<[YArrayChange<T>], Never>()
        let subscription = observe { subject.send($0) }
        return subject.handleEvents(receiveCancel: {
            subscription.cancel()
        })
        .eraseToAnyPublisher()
    }

    /// Registers a closure that is called with an array of changes to the list.
    /// - Warning: Deprecated. Use `observeAsync()` instead.
    /// - Parameter body: A closure that is called with an array of list changes.
    /// - Returns: An observer identifier.
    @available(*, deprecated, message: "Use observeAsync() instead")
    public func observe(_ body: @escaping ([YArrayChange<T>]) -> Void) -> YSubscription {
        let delegate = YArrayObservationDelegate(callback: body, decoded: Coder.decodedArray)
        return YSubscription(subscription: _array.observe(delegate: delegate))
    }
    
    public func pointer() -> YrsCollectionPtr {
        return _array.rawPtr()
    }
}

extension YArray: Sequence {
    public typealias Iterator = YArrayIterator

    /// Returns an iterator for the list.
    public func makeIterator() -> Iterator {
        YArrayIterator(self)
    }

    public class YArrayIterator: IteratorProtocol {
        private var indexPosition: Int
        private var arrayRef: YArray

        init(_ arrayRef: YArray) {
            self.arrayRef = arrayRef
            indexPosition = 0
        }

        public func next() -> T? {
            if let item = arrayRef.get(index: indexPosition) {
                indexPosition += 1
                return item
            }
            return nil
        }
    }
}

// At the moment, below protocol implementations are "stub"-ish in nature
// They need to be completed & tested after Iterator is ported from Rust side
extension YArray: MutableCollection, RandomAccessCollection {
    public func index(after i: Int) -> Int {
        // precondition ensures index never goes past the bounds
        precondition(i < endIndex, "Index out of bounds")
        return i + 1
    }

    /// The location of the start of the list.
    public var startIndex: Int {
        0
    }

    /// The location at the end of the list.
    public var endIndex: Int {
        Int(length())
    }

    /// Inserts or returns the object in the list at the position you specify.
    public subscript(position: Int) -> T {
        get {
            precondition(position < endIndex, "Index out of bounds")
            return get(index: position)!
        }
        set(newValue) {
            precondition(position < endIndex, "Index out of bounds")
            withTransaction { txn in
                self.remove(at: position, transaction: txn)
                self.insert(at: position, value: newValue, transaction: txn)
            }
        }
    }
}

class YArrayEachDelegate<T: Codable>: YrsArrayEachDelegate {
    private var callback: (T) -> Void
    private var decoded: (String) -> T

    init(
        callback: @escaping (T) -> Void,
        decoded: @escaping (String) -> T
    ) {
        self.callback = callback
        self.decoded = decoded
    }

    func call(value: String) {
        callback(decoded(value))
    }
}

class YArrayObservationDelegate<T: Codable>: YrsArrayObservationDelegate {
    private var callback: ([YArrayChange<T>]) -> Void
    private var decoded: ([String]) -> [T]

    init(
        callback: @escaping ([YArrayChange<T>]) -> Void,
        decoded: @escaping ([String]) -> [T]
    ) {
        self.callback = callback
        self.decoded = decoded
    }

    func call(value: [YrsChange]) {
        let result: [YArrayChange<T>] = value.map { rsChange -> YArrayChange<T> in
            switch rsChange {
            case let .added(elements):
                return YArrayChange.added(elements: decoded(elements))
            case let .removed(range):
                return YArrayChange.removed(range: range)
            case let .retained(range):
                return YArrayChange.retained(range: range)
            }
        }
        callback(result)
    }
}

/// A type that represents changes to a list.
public enum YArrayChange<T> {
    /// Objects added to the list.
    case added(elements: [T])
    /// An index position that is removed.
    case removed(range: UInt32)
    /// An index position that is updated.
    case retained(range: UInt32)
}

extension YArrayChange: Equatable where T: Equatable {
    public static func == (lhs: YArrayChange<T>, rhs: YArrayChange<T>) -> Bool {
        switch (lhs, rhs) {
        case let (.added(elements1), .added(elements2)):
            return elements1 == elements2
        case let (.removed(range1), .removed(range2)):
            return range1 == range2
        case let (.retained(range1), .retained(range2)):
            return range1 == range2
        default:
            return false
        }
    }
}

extension YArrayChange: Hashable where T: Hashable {}

// MARK: - Subdocument Support

extension YArray {
    /// Returns a subdocument at the specified index.
    /// - Parameters:
    ///   - index: The index position of the subdocument.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The subdocument at the specified index, or nil if no subdocument exists at that index.
    public func getSubdoc(at index: Int, transaction: YrsTransaction? = nil) -> YDocument? {
        withTransaction(transaction) { txn in
            self._array.getDoc(tx: txn, index: UInt32(index)).map { YDocument(wrapping: $0) }
        }
    }

    /// Inserts a subdocument at the specified index.
    /// - Parameters:
    ///   - index: The index position where the subdocument should be inserted.
    ///   - subdoc: The subdocument to insert.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The integrated subdocument (may be different from the input if the document was already integrated).
    @discardableResult
    public func insertSubdoc(at index: Int, _ subdoc: YDocument, transaction: YrsTransaction? = nil) -> YDocument {
        withTransaction(transaction) { txn in
            let inserted = self._array.insertDoc(tx: txn, index: UInt32(index), doc: subdoc.document)
            return YDocument(wrapping: inserted)
        }
    }
}

// MARK: - Nested Shared Type Support

extension YArray {
    /// Returns a nested YMap at the specified index.
    public func getMap<U: Codable>(at index: Int, transaction: YrsTransaction? = nil) -> YMap<U>? {
        withTransaction(transaction) { txn in
            self._array.getMap(tx: txn, index: UInt32(index)).map { YMap<U>(map: $0, document: self.document) }
        }
    }

    /// Returns a nested YArray at the specified index.
    public func getArray<U: Codable>(at index: Int, transaction: YrsTransaction? = nil) -> YArray<U>? {
        withTransaction(transaction) { txn in
            self._array.getArray(tx: txn, index: UInt32(index)).map { YArray<U>(array: $0, document: self.document) }
        }
    }

    /// Returns a nested YText at the specified index.
    public func getText(at index: Int, transaction: YrsTransaction? = nil) -> YText? {
        withTransaction(transaction) { txn in
            self._array.getText(tx: txn, index: UInt32(index)).map { YText(text: $0, document: self.document) }
        }
    }

    /// Checks if value at index is an undefined reference.
    public func isUndefined(at index: Int, transaction: YrsTransaction? = nil) -> Bool {
        withTransaction(transaction) { txn in
            self._array.isUndefined(tx: txn, index: UInt32(index))
        }
    }

    /// Inserts an empty nested YMap at the specified index.
    @discardableResult
    public func insertMap<U: Codable>(at index: Int, transaction: YrsTransaction? = nil) -> YMap<U> {
        withTransaction(transaction) { txn in
            YMap<U>(map: self._array.insertMap(tx: txn, index: UInt32(index)), document: self.document)
        }
    }

    /// Inserts an empty nested YArray at the specified index.
    @discardableResult
    public func insertArray<U: Codable>(at index: Int, transaction: YrsTransaction? = nil) -> YArray<U> {
        withTransaction(transaction) { txn in
            YArray<U>(array: self._array.insertArray(tx: txn, index: UInt32(index)), document: self.document)
        }
    }

    /// Inserts an empty nested YText at the specified index.
    @discardableResult
    public func insertText(at index: Int, transaction: YrsTransaction? = nil) -> YText {
        withTransaction(transaction) { txn in
            YText(text: self._array.insertText(tx: txn, index: UInt32(index)), document: self.document)
        }
    }

    /// Pushes an empty nested YMap to the end of the array.
    @discardableResult
    public func pushMap<U: Codable>(transaction: YrsTransaction? = nil) -> YMap<U> {
        withTransaction(transaction) { txn in
            YMap<U>(map: self._array.pushMap(tx: txn), document: self.document)
        }
    }

    /// Pushes an empty nested YArray to the end of the array.
    @discardableResult
    public func pushArray<U: Codable>(transaction: YrsTransaction? = nil) -> YArray<U> {
        withTransaction(transaction) { txn in
            YArray<U>(array: self._array.pushArray(tx: txn), document: self.document)
        }
    }

    /// Pushes an empty nested YText to the end of the array.
    @discardableResult
    public func pushText(transaction: YrsTransaction? = nil) -> YText {
        withTransaction(transaction) { txn in
            YText(text: self._array.pushText(tx: txn), document: self.document)
        }
    }

    /// Moves element from source index to target index.
    public func move(from source: Int, to target: Int, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._array.moveTo(tx: txn, source: UInt32(source), target: UInt32(target))
        }
    }

    /// Moves range of elements to target index.
    public func moveRange(from start: Int, to end: Int, target: Int, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._array.moveRangeTo(tx: txn, start: UInt32(start), end: UInt32(end), target: UInt32(target))
        }
    }
}
