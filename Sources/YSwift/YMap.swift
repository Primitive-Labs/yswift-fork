import Combine
import Foundation
import Queue
import Yniffi

/// A type that provides a map shared data type.
///
/// Store, order, and retrieve any single `Codable` type within a `YMap` keyed with a `String`.
///
/// Create a new `YMap` instance using ``YSwift/YDocument/getOrCreateMap(named:)`` from a ``YDocument``.
public final class YMap<T: Codable>: Transactable, YCollection, @unchecked Sendable {
    private let _map: YrsMap
    let document: YDocument

    init(map: YrsMap, document: YDocument) {
        _map = map
        self.document = document
    }

    // MARK: - Properties

    /// Returns a Boolean value that indicates whether the map is empty.
    public var isEmpty: Bool {
        length() == 0
    }

    /// Returns the number of items in the map.
    public var count: Int {
        Int(length())
    }

    // MARK: - Async API (Preferred)

    /// Gets the value within a map identified by the string you provide.
    /// - Parameter key: The string that identifies the object.
    /// - Returns: The object within the map at that key, or `nil` if it's not available.
    public func get(key: String) async -> T? where T: Sendable {
        await withTransaction { txn -> T? in
            if let result = try? self._map.get(tx: txn, key: key) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Sets the value within a map identified by the string you provide.
    /// - Parameters:
    ///   - value: The object to set, or nil to remove.
    ///   - key: The string that identifies the object.
    public func set(_ value: T?, forKey key: String) async where T: Sendable {
        await withTransaction { txn in
            if let value = value {
                self._map.insert(tx: txn, key: key, value: Coder.encoded(value))
            } else {
                _ = try? self._map.remove(tx: txn, key: key)
            }
        }
    }

    /// Returns the length of the map.
    public func length() async -> UInt32 where T: Sendable {
        await withTransaction { txn in
            self._map.length(tx: txn)
        }
    }

    /// Returns a Boolean value indicating whether the key you provide is in the map.
    /// - Parameter key: A string that identifies an object within the map.
    public func containsKey(_ key: String) async -> Bool where T: Sendable {
        await withTransaction { txn in
            self._map.containsKey(tx: txn, key: key)
        }
    }

    /// Removes an object from the map.
    /// - Parameter key: A string that identifies the object to remove.
    /// - Returns: The item removed, or `nil` if unavailable.
    @discardableResult
    public func removeValue(forKey key: String) async -> T? where T: Sendable {
        await withTransaction { txn -> T? in
            if let result = try? self._map.remove(tx: txn, key: key) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Removes all items from the map.
    public func removeAll() async where T: Sendable {
        await withTransaction { txn in
            self._map.clear(tx: txn)
        }
    }

    /// Returns all keys from the map.
    public func keys() async -> [String] where T: Sendable {
        await withTransaction { txn in
            var result: [String] = []
            let delegate = YMapKeyIteratorDelegate { result.append($0) }
            self._map.keys(tx: txn, delegate: delegate)
            return result
        }
    }

    /// Returns all values from the map.
    public func values() async -> [T] where T: Sendable {
        await withTransaction { txn in
            var result: [T] = []
            let delegate = YMapValueIteratorDelegate(callback: { result.append($0) }, decoded: Coder.decoded)
            self._map.values(tx: txn, delegate: delegate)
            return result
        }
    }

    /// Returns the map as a dictionary asynchronously.
    public func toMapAsync() async -> [String: T] where T: Sendable {
        await withTransaction { txn in
            var result: [String: T] = [:]
            let delegate = YMapKeyValueIteratorDelegate(callback: { result[$0] = $1 }, decoded: Coder.decoded)
            self._map.each(tx: txn, delegate: delegate)
            return result
        }
    }

    // MARK: - Sync API with Explicit Transaction (Always Available)

    /// Gets the value using an existing transaction.
    public func get(key: String, transaction: YrsTransaction) -> T? {
        if let result = try? _map.get(tx: transaction, key: key) {
            return Coder.decoded(result)
        }
        return nil
    }

    /// Updates or inserts the value using an existing transaction.
    public func updateValue(_ value: T, forKey key: String, transaction: YrsTransaction) {
        _map.insert(tx: transaction, key: key, value: Coder.encoded(value))
    }

    /// Returns the length using an existing transaction.
    public func length(transaction: YrsTransaction) -> UInt32 {
        _map.length(tx: transaction)
    }

    /// Returns whether the key exists using an existing transaction.
    public func containsKey(_ key: String, transaction: YrsTransaction) -> Bool {
        _map.containsKey(tx: transaction, key: key)
    }

    /// Removes a value using an existing transaction.
    @discardableResult
    public func removeValue(forKey key: String, transaction: YrsTransaction) -> T? {
        if let result = try? _map.remove(tx: transaction, key: key) {
            return Coder.decoded(result)
        }
        return nil
    }

    /// Removes all items using an existing transaction.
    public func removeAll(transaction: YrsTransaction) {
        _map.clear(tx: transaction)
    }

    /// Iterates keys using an existing transaction.
    public func keys(transaction: YrsTransaction, _ body: @escaping (String) -> Void) {
        let delegate = YMapKeyIteratorDelegate(callback: body)
        _map.keys(tx: transaction, delegate: delegate)
    }

    /// Iterates values using an existing transaction.
    public func values(transaction: YrsTransaction, _ body: @escaping (T) -> Void) {
        let delegate = YMapValueIteratorDelegate(callback: body, decoded: Coder.decoded)
        _map.values(tx: transaction, delegate: delegate)
    }

    /// Iterates key-value pairs using an existing transaction.
    public func each(transaction: YrsTransaction, _ body: @escaping (String, T) -> Void) {
        let delegate = YMapKeyValueIteratorDelegate(callback: body, decoded: Coder.decoded)
        _map.each(tx: transaction, delegate: delegate)
    }

    /// Returns the map as a dictionary using an existing transaction.
    public func toMap(transaction: YrsTransaction) -> [String: T] {
        var result: [String: T] = [:]
        each(transaction: transaction) { key, value in
            result[key] = value
        }
        return result
    }

    // MARK: - Deprecated Sync API (Creates Own Transaction)

    /// Gets or sets the value within a map identified by the string you provide.
    /// - Warning: Deprecated. Use async `get(key:)` and `set(_:forKey:)` instead.
    @available(*, deprecated, message: "Use async get(key:) and set(_:forKey:) instead")
    public subscript(key: String) -> T? {
        get {
            get(key: key, transaction: nil)
        }
        set {
            if let newValue = newValue {
                updateValue(newValue, forKey: key, transaction: nil)
            } else {
                removeValue(forKey: key, transaction: nil)
            }
        }
    }

    /// Updates or inserts the object for the key you provide.
    /// - Warning: Deprecated. Use async `set(_:forKey:)` or pass explicit transaction.
    @available(*, deprecated, message: "Use async set(_:forKey:) or pass explicit transaction")
    public func updateValue(_ value: T, forKey key: String, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._map.insert(tx: txn, key: key, value: Coder.encoded(value))
        }
    }

    /// Returns the length of the map.
    /// - Warning: Deprecated. Use async `length()` or pass explicit transaction.
    @available(*, deprecated, message: "Use async length() or pass explicit transaction")
    public func length(transaction: YrsTransaction? = nil) -> UInt32 {
        withTransaction(transaction) { txn in
            self._map.length(tx: txn)
        }
    }

    /// Returns the object from the map identified by the key you provide.
    /// - Warning: Deprecated. Use async `get(key:)` or pass explicit transaction.
    @available(*, deprecated, message: "Use async get(key:) or pass explicit transaction")
    public func get(key: String, transaction: YrsTransaction? = nil) -> T? {
        withTransaction(transaction) { txn -> T? in
            if let result = try? self._map.get(tx: txn, key: key) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Returns a Boolean value indicating whether the key you provide is in the map.
    /// - Warning: Deprecated. Use async `containsKey(_:)` or pass explicit transaction.
    @available(*, deprecated, message: "Use async containsKey(_:) or pass explicit transaction")
    public func containsKey(_ key: String, transaction: YrsTransaction? = nil) -> Bool {
        withTransaction(transaction) { txn in
            self._map.containsKey(tx: txn, key: key)
        }
    }

    /// Removes an object from the map.
    /// - Warning: Deprecated. Use async `removeValue(forKey:)` or pass explicit transaction.
    @available(*, deprecated, message: "Use async removeValue(forKey:) or pass explicit transaction")
    @discardableResult
    public func removeValue(forKey key: String, transaction: YrsTransaction? = nil) -> T? {
        withTransaction(transaction) { txn -> T? in
            if let result = try? self._map.remove(tx: txn, key: key) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Removes all items from the map.
    /// - Warning: Deprecated. Use async `removeAll()` or pass explicit transaction.
    @available(*, deprecated, message: "Use async removeAll() or pass explicit transaction")
    public func removeAll(transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._map.clear(tx: txn)
        }
    }

    /// Calls the closure you provide with each key from the map.
    /// - Warning: Deprecated. Use async `keys()` or pass explicit transaction.
    @available(*, deprecated, message: "Use async keys() or pass explicit transaction")
    public func keys(transaction: YrsTransaction? = nil, _ body: @escaping (String) -> Void) {
        let delegate = YMapKeyIteratorDelegate(callback: body)
        withTransaction(transaction) { txn in
            self._map.keys(tx: txn, delegate: delegate)
        }
    }

    /// Calls the closure you provide with each value from the map.
    /// - Warning: Deprecated. Use async `values()` or pass explicit transaction.
    @available(*, deprecated, message: "Use async values() or pass explicit transaction")
    public func values(transaction: YrsTransaction? = nil, _ body: @escaping (T) -> Void) {
        let delegate = YMapValueIteratorDelegate(callback: body, decoded: Coder.decoded)
        withTransaction(transaction) { txn in
            self._map.values(tx: txn, delegate: delegate)
        }
    }

    /// Iterates over the map of elements, providing each element to the closure you provide.
    /// - Warning: Deprecated. Use async iteration or pass explicit transaction.
    @available(*, deprecated, message: "Use async toMap() or pass explicit transaction")
    public func each(transaction: YrsTransaction? = nil, _ body: @escaping (String, T) -> Void) {
        let delegate = YMapKeyValueIteratorDelegate(callback: body, decoded: Coder.decoded)
        withTransaction(transaction) { txn in
            self._map.each(tx: txn, delegate: delegate)
        }
    }

    /// Returns a publisher of map changes.
    public func observe() -> AnyPublisher<[YMapChange<T>], Never> {
        let subject = PassthroughSubject<[YMapChange<T>], Never>()
        let subscription = observe { subject.send($0) }
        return subject.handleEvents(receiveCancel: {
            subscription.cancel()
        })
        .eraseToAnyPublisher()
    }

    /// Registers a closure that is called with an array of changes to the map.
    /// - Parameter body: A closure that is called with an array of map changes.
    /// - Returns: An observer identifier.
    public func observe(_ body: @escaping ([YMapChange<T>]) -> Void) -> YSubscription {
        let delegate = YMapObservationDelegate(decoded: Coder.decoded, callback: body)
        return YSubscription(subscription: _map.observe(delegate: delegate))
    }

    /// Returns an async stream of map changes.
    ///
    /// Changes are delivered asynchronously after the transaction commits,
    /// making it safe to read document state from within the stream consumer.
    ///
    /// ```swift
    /// for await changes in map.observeAsync() {
    ///     // Safe to call transactSync or read state here
    ///     let currentState = map.toMap()
    /// }
    /// ```
    ///
    /// - TODO: Support queue priority argument as optional parameter (e.g. `.high`, `.userInitiated`)
    public func observeAsync() -> AsyncStream<[YMapChange<T>]> where T: Sendable {
        // Use unbounded buffering to avoid blocking the synchronous observer callback
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let subscription = observe { changes in
                // Called synchronously during transaction.
                // Yield directly - the unbounded buffer ensures we don't block.
                // Changes will be delivered asynchronously to the consumer.
                continuation.yield(changes)
            }

            continuation.onTermination = { _ in
                subscription.cancel()
            }
        }
    }

    /// Returns the map as a dictionary.
    /// - Warning: Deprecated. Use async `toMapAsync()` or pass explicit transaction.
    @available(*, deprecated, message: "Use async toMapAsync() or pass explicit transaction")
    public func toMap(transaction: YrsTransaction? = nil) -> [String: T] {
        if let transaction = transaction {
            return toMap(transaction: transaction)
        }
        var replicatedMap: [String: T] = [:]
        withTransaction(transaction) { txn in
            let delegate = YMapKeyValueIteratorDelegate(callback: { replicatedMap[$0] = $1 }, decoded: Coder.decoded)
            self._map.each(tx: txn, delegate: delegate)
        }
        return replicatedMap
    }
    
    public func pointer() -> YrsCollectionPtr {
        return _map.rawPtr()
    }
}

extension YMap: Sequence {
    public typealias Iterator = YMapIterator

    // this method can't support the Iterator protocol because I've added
    // YrsTransation to the function, needed for any interactions with the
    // map - but the protocol defines it as taking no additional
    // options. So... where do we get a relevant transaction? Do we stash
    // one within the map, or create it afresh on each iterator creation?
    public func makeIterator() -> Iterator {
        YMapIterator(self)
    }

    public class YMapIterator: IteratorProtocol {
        var keyValues: [(String, T)]

        init(_ map: YMap) {
            var collectedKeyValues: [(String, T)] = []
            map.each { key, value in
                collectedKeyValues.append((key, value))
            }
            keyValues = collectedKeyValues
        }

        public func next() -> (String, T)? {
            keyValues.popLast()
        }
    }
}

/// A type that holds a closure that the Rust language bindings calls
/// while iterating the keys of a Map.
class YMapKeyIteratorDelegate: YrsMapIteratorDelegate {
    private var callback: (String) -> Void

    init(callback: @escaping (String) -> Void) {
        self.callback = callback
    }

    func call(value: String) {
        callback(value)
    }
}

/// A type that holds a closure that the Rust language bindings calls
/// while iterating the values of a Map.
///
/// The values returned by Rust is a String with a JSON encoded object that this
/// delegate needs to unwrap/decode on the fly...
class YMapValueIteratorDelegate<T: Codable>: YrsMapIteratorDelegate {
    private var callback: (T) -> Void
    private var decoded: (String) -> T

    init(callback: @escaping (T) -> Void,
         decoded: @escaping (String) -> T)
    {
        self.callback = callback
        self.decoded = decoded
    }

    func call(value: String) {
        callback(decoded(value))
    }
}

/// A type that holds a closure that the Rust language bindings calls
/// while iterating the keys and values of a Map.
///
/// The key is a string, and the value is a String with a JSON encoded object that this
/// delegate needs to unwrap/decode on the fly.
class YMapKeyValueIteratorDelegate<T: Codable>: YrsMapKvIteratorDelegate {
    private var callback: (String, T) -> Void
    private var decoded: (String) -> T

    init(callback: @escaping (String, T) -> Void,
         decoded: @escaping (String) -> T)
    {
        self.callback = callback
        self.decoded = decoded
    }

    func call(key: String, value: String) {
        callback(key, decoded(value))
    }
}

class YMapObservationDelegate<T: Codable>: YrsMapObservationDelegate {
    private var callback: ([YMapChange<T>]) -> Void
    private var decoded: (String) -> T

    init(
        decoded: @escaping (String) -> T,
        callback: @escaping ([YMapChange<T>]) -> Void
    ) {
        self.decoded = decoded
        self.callback = callback
    }

    func call(value: [YrsMapChange]) {
        let result: [YMapChange<T>] = value.map { rsChange -> YMapChange<T> in
            switch rsChange.change {
            case let .inserted(value):
                return YMapChange.inserted(key: rsChange.key, value: decoded(value))
            case let .updated(oldValue, newValue):
                return YMapChange.updated(key: rsChange.key, oldValue: decoded(oldValue), newValue: decoded(newValue))
            case let .removed(value):
                return YMapChange.removed(key: rsChange.key, value: decoded(value))
            }
        }
        callback(result)
    }
}

/// A type that represents changes to a Map.
public enum YMapChange<T> {
    /// The key and value inserted into the map.
    case inserted(key: String, value: T)
    /// The key, old value, and new value updated in the map.
    case updated(key: String, oldValue: T, newValue: T)
    /// The key and value removed from the map.
    case removed(key: String, value: T)
}

extension YMapChange: Equatable where T: Equatable {
    public static func == (lhs: YMapChange<T>, rhs: YMapChange<T>) -> Bool {
        switch (lhs, rhs) {
        case let (.inserted(key1, value1), .inserted(key2, value2)):
            return key1 == key2 && value1 == value2
        case let (.updated(key1, oldValue1, newValue1), .updated(key2, oldValue2, newValue2)):
            return key1 == key2 && oldValue1 == oldValue2 && newValue1 == newValue2
        case let (.removed(key1, value1), .removed(key2, value2)):
            return key1 == key2 && value1 == value2
        default:
            return false
        }
    }
}

extension YMapChange: Sendable where T: Sendable {}

extension YMapChange: Hashable where T: Hashable {}

// MARK: - Subdocument Support

extension YMap {
    /// Returns a subdocument for the specified key.
    /// - Parameters:
    ///   - key: The key that identifies the subdocument.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The subdocument for the specified key, or nil if no subdocument exists for that key.
    public func getSubdoc(forKey key: String, transaction: YrsTransaction? = nil) -> YDocument? {
        withTransaction(transaction) { txn in
            self._map.getDoc(tx: txn, key: key).map { YDocument(wrapping: $0) }
        }
    }

    /// Inserts a subdocument for the specified key.
    /// - Parameters:
    ///   - subdoc: The subdocument to insert.
    ///   - key: The key to associate with the subdocument.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The integrated subdocument (may be different from the input if the document was already integrated).
    @discardableResult
    public func insertSubdoc(_ subdoc: YDocument, forKey key: String, transaction: YrsTransaction? = nil) -> YDocument {
        withTransaction(transaction) { txn in
            let inserted = self._map.insertDoc(tx: txn, key: key, doc: subdoc.document)
            return YDocument(wrapping: inserted)
        }
    }
}

// MARK: - Nested Shared Type Support

extension YMap {
    /// Returns a nested YArray for the specified key.
    /// - Parameters:
    ///   - key: The key that identifies the nested array.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The nested array, or nil if no array exists for that key.
    public func getArray<U: Codable>(forKey key: String, transaction: YrsTransaction? = nil) -> YArray<U>? {
        withTransaction(transaction) { txn in
            self._map.getArray(tx: txn, key: key).map { YArray(array: $0, document: self.document) }
        }
    }

    /// Returns a nested YMap for the specified key.
    /// - Parameters:
    ///   - key: The key that identifies the nested map.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The nested map, or nil if no map exists for that key.
    public func getMap<U: Codable>(forKey key: String, transaction: YrsTransaction? = nil) -> YMap<U>? {
        withTransaction(transaction) { txn in
            self._map.getMap(tx: txn, key: key).map { YMap<U>(map: $0, document: self.document) }
        }
    }

    /// Returns a nested YText for the specified key.
    /// - Parameters:
    ///   - key: The key that identifies the nested text.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The nested text, or nil if no text exists for that key.
    public func getText(forKey key: String, transaction: YrsTransaction? = nil) -> YText? {
        withTransaction(transaction) { txn in
            self._map.getText(tx: txn, key: key).map { YText(text: $0, document: self.document) }
        }
    }

    /// Checks if the value at the specified key is an undefined reference.
    /// - Parameters:
    ///   - key: The key to check.
    ///   - transaction: An optional transaction to use.
    /// - Returns: True if the key exists but holds an undefined/deleted reference.
    public func isUndefined(forKey key: String, transaction: YrsTransaction? = nil) -> Bool {
        withTransaction(transaction) { txn in
            self._map.isUndefined(tx: txn, key: key)
        }
    }

    /// Inserts an empty nested YMap at the specified key.
    /// - Parameters:
    ///   - key: The key for the new nested map.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The newly inserted nested map.
    @discardableResult
    public func insertMap<U: Codable>(forKey key: String, transaction: YrsTransaction? = nil) -> YMap<U> {
        withTransaction(transaction) { txn in
            YMap<U>(map: self._map.insertMap(tx: txn, key: key), document: self.document)
        }
    }

    /// Inserts an empty nested YArray at the specified key.
    /// - Parameters:
    ///   - key: The key for the new nested array.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The newly inserted nested array.
    @discardableResult
    public func insertArray<U: Codable>(forKey key: String, transaction: YrsTransaction? = nil) -> YArray<U> {
        withTransaction(transaction) { txn in
            YArray<U>(array: self._map.insertArray(tx: txn, key: key), document: self.document)
        }
    }

    /// Inserts an empty nested YText at the specified key.
    /// - Parameters:
    ///   - key: The key for the new nested text.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The newly inserted nested text.
    @discardableResult
    public func insertText(forKey key: String, transaction: YrsTransaction? = nil) -> YText {
        withTransaction(transaction) { txn in
            YText(text: self._map.insertText(tx: txn, key: key), document: self.document)
        }
    }

    /// Updates value only if different from current value.
    /// - Parameters:
    ///   - value: The new value to set.
    ///   - key: The key to update.
    ///   - transaction: An optional transaction to use.
    /// - Returns: True if the value was updated, false if unchanged.
    @discardableResult
    public func tryUpdate(_ value: T, forKey key: String, transaction: YrsTransaction? = nil) -> Bool {
        withTransaction(transaction) { txn in
            self._map.tryUpdate(tx: txn, key: key, value: Coder.encoded(value))
        }
    }

    /// Gets existing nested map or creates new one at key.
    /// - Parameters:
    ///   - key: The key for the nested map.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The existing or newly created nested map.
    public func getOrInsertMap<U: Codable>(forKey key: String, transaction: YrsTransaction? = nil) -> YMap<U> {
        withTransaction(transaction) { txn in
            YMap<U>(map: self._map.getOrInsertMap(tx: txn, key: key), document: self.document)
        }
    }

    /// Gets existing nested array or creates new one at key.
    /// - Parameters:
    ///   - key: The key for the nested array.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The existing or newly created nested array.
    public func getOrInsertArray<U: Codable>(forKey key: String, transaction: YrsTransaction? = nil) -> YArray<U> {
        withTransaction(transaction) { txn in
            YArray<U>(array: self._map.getOrInsertArray(tx: txn, key: key), document: self.document)
        }
    }

    /// Gets existing nested text or creates new one at key.
    /// - Parameters:
    ///   - key: The key for the nested text.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The existing or newly created nested text.
    public func getOrInsertText(forKey key: String, transaction: YrsTransaction? = nil) -> YText {
        withTransaction(transaction) { txn in
            YText(text: self._map.getOrInsertText(tx: txn, key: key), document: self.document)
        }
    }
}
