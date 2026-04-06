import Yniffi

/// A type that contains a reference to a document and provides a convenience accessor to interacting with transactions from it.
protocol Transactable {
    /// The document used to coordinate transactions
    var document: YDocument { get }
}

extension Transactable {
    // MARK: - Async Transaction Helper (Preferred)

    /// Async convenience accessor for interacting with shared data types.
    ///
    /// - Parameters:
    ///   - changes: A closure that provides the transaction you use to interact with shared types.
    /// - Returns: Returns the returned value from the closure.
    func withTransaction<T: Sendable>(_ changes: @escaping @Sendable (YrsTransaction) -> T) async -> T {
        await document.transact(changes)
    }

    /// Uses an existing transaction or creates a new async one.
    ///
    /// - Parameters:
    ///   - transaction: An existing transaction to use.
    ///   - changes: A closure that provides the transaction you use to interact with shared types.
    /// - Returns: Returns the returned value from the closure.
    func withTransaction<T: Sendable>(_ transaction: YrsTransaction?, changes: @escaping @Sendable (YrsTransaction) -> T) async -> T {
        if let transaction = transaction {
            return changes(transaction)
        } else {
            return await document.transact(changes)
        }
    }

    // MARK: - Sync Transaction Helper (Deprecated)

    /// Sync convenience accessor for interacting with shared data types.
    ///
    /// - Warning: Deprecated. Use async `withTransaction` instead.
    @available(*, deprecated, message: "Use async withTransaction instead")
    func withTransactionSync<T>(_ transaction: YrsTransaction? = nil, changes: @escaping (YrsTransaction) -> T) -> T {
        if let transaction = transaction {
            return changes(transaction)
        } else {
            return document.transactSync(origin: .none, changes)
        }
    }

    /// Legacy sync transaction helper - used internally by deprecated sync APIs.
    func withTransaction<T>(_ transaction: YrsTransaction? = nil, changes: @escaping (YrsTransaction) -> T) -> T {
        if let transaction = transaction {
            return changes(transaction)
        } else {
            return document.transactSync(origin: .none, changes)
        }
    }
}
