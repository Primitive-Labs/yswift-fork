# ``YSwift/YDocument``

A type that wraps all Y-CRDT shared data types, and provides transactional interactions for them.

## Overview

A `YDocument` tracks and coordinates updates to Y-CRDT shared data types, such as ``YSwift/YText``, ``YSwift/YArray``, and ``YSwift/YMap``.
Make any changes to shared data types within a document within a transaction using ``YSwift/YDocument/transact(origin:_:)-1tadr``.

Interact with other copies of the shared data types by synchronizing documents.

To synchronize a remote document with a local one:

1. Retrieve the current state of remote document from within a transaction:
```swift
let remoteState = await remoteDocument.transact { txn in
    txn.transactionStateVector()
}
```

2. Use the remote state to calculate a difference from the local document:
```swift
let updateRemote = await localDocument.transact { txn in
    localDocument.diff(txn: txn, from: remoteState)
}
```

3. Apply the difference to the remote document within a transaction:
```swift
await remoteDocument.transact { txn in
    try! txn.transactionApplyUpdate(update: updateRemote)
}
```

For a more detailed example of synchronizing a document, see <doc:SynchronizingDocuments>.

> Important: YSwift provides parallel sync and async APIs. The async APIs (using Swift concurrency) are preferred.
> The sync APIs are deprecated and will be removed in a future version. Do not mix sync and async APIs on the same document.

## Topics

### Creating or loading a document

- ``YSwift/YDocument/init()``

### Creating Shared Data Types

- ``YSwift/YDocument/getOrCreateText(named:)``
- ``YSwift/YDocument/getOrCreateArray(named:)``
- ``YSwift/YDocument/getOrCreateMap(named:)``

### Creating Transactions

- ``YSwift/YDocument/transactSync(origin:_:)``
- ``YSwift/YDocument/transact(origin:_:)``
- ``YSwift/YDocument/transactAsync(_:_:completion:)``

### Comparing Documents for Synchronization

- ``YSwift/YDocument/diff(txn:from:)``

### Undo and Redo

- ``YSwift/YDocument/undoManager(trackedRefs:)``

### Subdocuments

Subdocuments allow you to nest documents within arrays or maps. This enables lazy loading of document sections and more granular synchronization.

```swift
let parentDoc = YDocument()
let subdoc = YDocument(options: YDocumentOptions(guid: "child-doc"))
let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

// Insert subdoc into parent
await parentDoc.transact { txn in
    array.insertSubdoc(at: 0, subdoc, transaction: txn)
}

// Retrieve subdocs asynchronously
let subdocs = await parentDoc.subdocsAsync()
let guids = await parentDoc.subdocGuidsAsync()
```

- ``YSwift/YDocument/init(options:)``
- ``YSwift/YDocumentOptions``
- ``YSwift/YDocument/guid``
- ``YSwift/YDocument/clientId``
- ``YSwift/YDocument/autoLoad``
- ``YSwift/YDocument/shouldLoad``
- ``YSwift/YDocument/parentDocument``
- ``YSwift/YDocument/isSame(as:)``
- ``YSwift/YDocument/subdocs(transaction:)``
- ``YSwift/YDocument/subdocGuids(transaction:)``
- ``YSwift/YDocument/load(in:)``
- ``YSwift/YDocument/destroy(in:)``
- ``YSwift/YDocument/observeSubdocs(_:)-31inz``
- ``YSwift/YDocument/observeDestroy(_:)-4ditl``

### JSON Path Queries

Query nested document structures using JSON path syntax:

```swift
let doc = YDocument()
let users: YArray<String> = doc.getOrCreateArray(named: "users")
await doc.transact { txn in
    users.append("{\"name\":\"Alice\"}", transaction: txn)
    users.append("{\"name\":\"Bob\"}", transaction: txn)
}

// Query all users asynchronously
let results = try await doc.queryAsync("$.users[*]")

// Supported syntax:
// $.field      - Access field
// $[0]         - Array index
// $[*]         - All array elements
// $..field     - Recursive descent
// $[1:3]       - Array slice
```

- ``YSwift/YDocument/queryAsync(_:)``
- ``YSwift/YDocument/query(_:transaction:)``
