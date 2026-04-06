import Combine
import Foundation
import Queue
import Yniffi

/// YDocument holds YSwift shared data types and coordinates collaboration and changes.
public final class YDocument {
    public let document: YrsDoc

    // MARK: - Serialization Queues
    // Two parallel worlds: sync (deprecated) and async (preferred)
    // Don't mix - pick one paradigm and stick with it

    /// GCD queue for deprecated sync APIs. Will be removed in future version.
    private let syncQueue = DispatchQueue(label: "YSwift.YDocument.sync", qos: .userInitiated)

    /// AsyncQueue for Swift 6 concurrency-native APIs (preferred).
    private let asyncQueue = AsyncQueue()

    /// Create a new YSwift Document.
    public init() {
        document = YrsDoc()
    }

    /// Create a new YSwift Document with custom options.
    /// - Parameter options: Configuration options for the document.
    public init(options: YDocumentOptions) {
        document = YrsDoc.newWithOptions(options: options.yrsOptions)
    }

    /// Internal initializer for wrapping a YrsDoc (used when retrieving subdocuments).
    internal init(wrapping doc: YrsDoc) {
        document = doc
    }

    // MARK: - Identity Properties

    /// Whether this document will automatically load when accessed as a subdocument.
    public var autoLoad: Bool {
        document.autoLoad()
    }

    /// The client ID of this document.
    public var clientId: UInt64 {
        document.clientId()
    }

    /// The unique identifier (GUID) of this document.
    public var guid: String {
        document.guid()
    }

    /// Whether this document should be loaded when accessed.
    public var shouldLoad: Bool {
        document.shouldLoad()
    }

    /// The parent document if this is a subdocument, or nil if this is a root document.
    public var parentDocument: YDocument? {
        document.parentDoc().map { YDocument(wrapping: $0) }
    }

    // MARK: - Identity Methods

    /// Returns whether this document is the same instance as another document.
    /// - Parameter other: The document to compare with.
    /// - Returns: True if both documents reference the same underlying document.
    public func isSame(as other: YDocument) -> Bool {
        document.ptrEq(other: other.document)
    }

    // MARK: - Subdocument Lifecycle

    /// Loads a subdocument. Call this within a transaction of the parent document.
    /// - Parameter transaction: A transaction from the parent document.
    public func load(in transaction: YrsTransaction) {
        document.load(parentTxn: transaction)
    }

    /// Destroys and removes this subdocument from its parent. Call this within a transaction of the parent document.
    /// - Parameter transaction: A transaction from the parent document.
    public func destroy(in transaction: YrsTransaction) {
        document.destroy(parentTxn: transaction)
    }

    // MARK: - Subdocument Observation

    /// Registers a closure that is called when subdocuments are added, loaded, or removed.
    /// - Parameter body: A closure that receives the subdocs event.
    /// - Returns: A subscription that can be used to cancel the observation.
    public func observeSubdocs(_ body: @escaping (YSubdocsEvent) -> Void) -> YSubscription {
        let delegate = YSubdocsObservationDelegateWrapper(callback: body)
        return YSubscription(subscription: document.observeSubdocs(delegate: delegate))
    }

    /// Returns a publisher that emits subdocument lifecycle events.
    public func observeSubdocs() -> AnyPublisher<YSubdocsEvent, Never> {
        let subject = PassthroughSubject<YSubdocsEvent, Never>()
        let subscription = observeSubdocs { subject.send($0) }
        return subject.handleEvents(receiveCancel: {
            subscription.cancel()
        })
        .eraseToAnyPublisher()
    }

    /// Registers a closure that is called when this document is destroyed.
    /// - Parameter body: A closure that is called when the document is destroyed.
    /// - Returns: A subscription that can be used to cancel the observation.
    public func observeDestroy(_ body: @escaping () -> Void) -> YSubscription {
        let delegate = YDestroyObservationDelegateWrapper(callback: body)
        return YSubscription(subscription: document.observeDestroy(delegate: delegate))
    }

    /// Returns a publisher that emits when this document is destroyed.
    public func observeDestroy() -> AnyPublisher<Void, Never> {
        let subject = PassthroughSubject<Void, Never>()
        let subscription = observeDestroy { subject.send(()) }
        return subject.handleEvents(receiveCancel: {
            subscription.cancel()
        })
        .eraseToAnyPublisher()
    }

    // MARK: - Update Observation

    /// Registers a closure that is called after each transaction with the raw update bytes.
    /// This is the equivalent of JavaScript's `doc.on("update", callback)`.
    /// - Parameter body: A closure that receives the update bytes.
    /// - Returns: A subscription that can be used to cancel the observation.
    public func observeUpdate(_ body: @escaping ([UInt8]) -> Void) -> YSubscription {
        let delegate = YUpdateObservationDelegateWrapper(callback: body)
        return YSubscription(subscription: document.observeUpdateV1(delegate: delegate))
    }

    /// Returns a publisher that emits raw update bytes after each transaction.
    public func observeUpdate() -> AnyPublisher<[UInt8], Never> {
        let subject = PassthroughSubject<[UInt8], Never>()
        let subscription = observeUpdate { subject.send($0) }
        return subject.handleEvents(receiveCancel: {
            subscription.cancel()
        })
        .eraseToAnyPublisher()
    }

    // MARK: - Subdocument Queries (Async)

    /// Returns the GUIDs of all subdocuments in this document asynchronously.
    /// - Returns: An array of subdocument GUIDs.
    public func subdocGuidsAsync() async -> [String] {
        await transact { $0.subdocGuids() }
    }

    /// Returns all subdocuments in this document asynchronously.
    /// - Returns: An array of subdocuments.
    public func subdocsAsync() async -> [YDocument] {
        await transact { txn in
            txn.subdocs().map { YDocument(wrapping: $0) }
        }
    }

    // MARK: - Subdocument Queries (With Explicit Transaction)

    /// Returns the GUIDs of all subdocuments using an existing transaction.
    /// - Parameter transaction: The transaction to use.
    /// - Returns: An array of subdocument GUIDs.
    public func subdocGuids(transaction: YrsTransaction) -> [String] {
        transaction.subdocGuids()
    }

    /// Returns all subdocuments using an existing transaction.
    /// - Parameter transaction: The transaction to use.
    /// - Returns: An array of subdocuments.
    public func subdocs(transaction: YrsTransaction) -> [YDocument] {
        transaction.subdocs().map { YDocument(wrapping: $0) }
    }

    // MARK: - Subdocument Queries (Deprecated Sync)

    /// Returns the GUIDs of all subdocuments in this document.
    /// - Warning: Deprecated. Use async `subdocGuidsAsync()` or pass an explicit transaction.
    @available(*, deprecated, message: "Use async subdocGuidsAsync() instead")
    public func subdocGuids(transaction: YrsTransaction? = nil) -> [String] {
        if let transaction = transaction {
            return transaction.subdocGuids()
        } else {
            return transactSync { $0.subdocGuids() }
        }
    }

    /// Returns all subdocuments in this document.
    /// - Warning: Deprecated. Use async `subdocsAsync()` or pass an explicit transaction.
    @available(*, deprecated, message: "Use async subdocsAsync() instead")
    public func subdocs(transaction: YrsTransaction? = nil) -> [YDocument] {
        if let transaction = transaction {
            return transaction.subdocs().map { YDocument(wrapping: $0) }
        } else {
            return transactSync { txn in
                txn.subdocs().map { YDocument(wrapping: $0) }
            }
        }
    }

    /// Compares the state vector from another YSwift document to return a data buffer you can use to synchronize with another YSwift document.
    ///
    /// Use `transactionStateVector()` on a transaction to get a state buffer to compare with this method.
    ///
    /// - Parameters:
    ///   - txn: A transaction within which to compare the state of the document.
    ///   - state: A data buffer from another YSwift document.
    /// - Returns: A buffer that contains the diff you can use to synchronize another YSwift document.
    public func diff(txn: YrsTransaction, from state: [UInt8] = []) -> [UInt8] {
        try! document.encodeDiffV1(tx: txn, stateVector: state)
    }

    // MARK: - Async Transaction Methods (Preferred)

    /// Creates an asynchronous transaction using Swift concurrency.
    ///
    /// This is the preferred way to interact with the document. Uses AsyncQueue
    /// for proper Swift 6 concurrency integration.
    ///
    /// - Parameters:
    ///   - origin: Optional origin identifier for this transaction.
    ///   - changes: The closure in which you make changes to the document.
    /// - Returns: The value that you return from the closure.
    public func transact<T: Sendable>(origin: Origin? = nil, _ changes: @escaping @Sendable (YrsTransaction) -> T) async -> T {
        await asyncQueue.addOperation { [self] in
            let transaction = document.transact(origin: origin?.origin)
            defer { transaction.free() }
            return changes(transaction)
        }.value
    }

    /// Creates an asynchronous throwing transaction using Swift concurrency.
    public func transact<T: Sendable>(origin: Origin? = nil, _ changes: @escaping @Sendable (YrsTransaction) throws -> T) async throws -> T {
        try await asyncQueue.addOperation { [self] in
            let transaction = document.transact(origin: origin?.origin)
            defer { transaction.free() }
            return try changes(transaction)
        }.value
    }

    // MARK: - Sync Transaction Methods (Deprecated)

    /// Creates a synchronous transaction and provides that transaction to a trailing closure.
    ///
    /// - Warning: Deprecated. Use async `transact()` instead. Mixing sync and async
    ///   transaction methods on the same document will cause race conditions.
    ///
    /// - Parameters:
    ///   - origin: Optional origin identifier for this transaction.
    ///   - changes: The closure in which you make changes to the document.
    /// - Returns: The value that you return from the closure.
    @available(*, deprecated, message: "Use async transact() instead. Mixing sync/async causes races.")
    public func transactSync<T>(origin: Origin? = nil, _ changes: @escaping (YrsTransaction) -> T) -> T {
        dispatchPrecondition(condition: .notOnQueue(syncQueue))
        return syncQueue.sync {
            let transaction = document.transact(origin: origin?.origin)
            defer { transaction.free() }
            return changes(transaction)
        }
    }

    /// Creates an asynchronous transaction with completion handler.
    ///
    /// - Warning: Deprecated. Use async `transact()` instead.
    @available(*, deprecated, message: "Use async transact() instead")
    public func transactAsync<T>(_ origin: Origin? = nil, _ changes: @escaping (YrsTransaction) -> T, completion: @escaping (T) -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            let transaction = self.document.transact(origin: origin?.origin)
            defer { transaction.free() }
            let result = changes(transaction)
            completion(result)
        }
    }

    // MARK: - Factory methods

    /// Retrieves or creates a Text shared data type.
    /// - Parameter named: The key you use to reference the Text shared data type.
    /// - Returns: The text shared type.
    public func getOrCreateText(named: String) -> YText {
        YText(text: document.getText(name: named), document: self)
    }

    /// Retrieves or creates an Array shared data type.
    /// - Parameter named: The key you use to reference the Array shared data type.
    /// - Returns: The array shared type.
    public func getOrCreateArray<T: Codable>(named: String) -> YArray<T> {
        YArray(array: document.getArray(name: named), document: self)
    }

    /// Retrieves or creates a Map shared data type.
    /// - Parameter named: The key you use to reference the Map shared data type.
    /// - Returns: The map shared type.
    public func getOrCreateMap<T: Codable>(named: String) -> YMap<T> {
        YMap(map: document.getMap(name: named), document: self)
    }

    /// Creates an Undo Manager for a document with the collections that is tracks.
    /// - Parameter trackedRefs: The collections to track to undo and redo changes.
    /// - Returns: A reference to the undo manager to control those actions.
    public func undoManager<T: AnyObject>(trackedRefs: [YCollection]) -> YUndoManager<T> {
        let mapped = trackedRefs.map { $0.pointer() }
        return YUndoManager(manager: document.undoManager(trackedRefs: mapped))
    }

    // MARK: - JSON Path Queries (Async)

    /// Queries the document using JSON path syntax asynchronously.
    ///
    /// JSON path allows you to query nested document structures. Examples:
    /// - `$.users` - Get the "users" root-level collection
    /// - `$.users[0]` - Get the first user
    /// - `$.users[*].name` - Get all user names
    /// - `$..name` - Recursively find all "name" fields
    ///
    /// - Parameters:
    ///   - path: A JSON path expression (e.g., "$.users[*].name")
    /// - Returns: An array of JSON-encoded strings representing matching values.
    /// - Throws: `YrsJsonPathError` if the path expression is invalid.
    public func queryAsync(_ path: String) async throws -> [String] {
        try await transact { txn in
            try txn.jsonPath(path: path)
        }
    }

    /// Queries the document using JSON path syntax with an existing transaction.
    ///
    /// - Parameters:
    ///   - path: A JSON path expression (e.g., "$.users[*].name")
    ///   - transaction: The transaction to use.
    /// - Returns: An array of JSON-encoded strings representing matching values.
    /// - Throws: `YrsJsonPathError` if the path expression is invalid.
    public func query(_ path: String, transaction: YrsTransaction) throws -> [String] {
        try transaction.jsonPath(path: path)
    }

    // MARK: - JSON Path Queries (Deprecated Sync)

    /// Queries the document using JSON path syntax.
    /// - Warning: Deprecated. Use async `queryAsync(_:)` or pass an explicit transaction.
    @available(*, deprecated, message: "Use async queryAsync(_:) instead")
    public func query(_ path: String, transaction: YrsTransaction? = nil) throws -> [String] {
        if let transaction = transaction {
            return try transaction.jsonPath(path: path)
        } else {
            var result: Result<[String], Error>?
            transactSync { txn in
                do {
                    result = .success(try txn.jsonPath(path: path))
                } catch {
                    result = .failure(error)
                }
            }
            return try result!.get()
        }
    }
}
