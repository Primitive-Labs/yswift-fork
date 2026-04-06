# Synchronizing Documents

Consistently merge content between two documents.

## Overview

One of the primary benefits of using `YSwift` is to be able to seamlessly and consistently synchronize data between two or more documents.
In this example, we show creating two instances of ``YSwift/YDocument`` and synchronizing between them, but in a real-world scenario the synchronization data would more likely be transmitted between two peers, or between a client application and server.

> Important: This guide uses the async APIs which are the preferred approach for Swift 6 concurrency.
> The sync APIs (`transactSync`) are deprecated and should not be mixed with async APIs on the same document.

### Establish the Documents

Once the library is imported, create an instance of ``YSwift/YDocument`` and use that instance to create the schema you wish to synchronize.
You can create ``YSwift/YText`` to synchronize text, or either of ``YSwift/YArray`` or ``YSwift/YMap`` to synchronize any `Codable` type you provide.
The keys for the schema are strings, and are required to match between two instances of ``YSwift/YDocument`` to synchronize the values.

```swift
import YSwift

let localDocument = YDocument()
let localText = localDocument.getOrCreateText(named: "example")
await localDocument.transact { txn in
    localText.append("hello, world!", in: txn)
}

let remoteDocument = YDocument()
let remoteText = remoteDocument.getOrCreateText(named: "example")
```

### Display the Initial State

To read, or update, values from within a ``YDocument``, do so from within a transaction.
The following sample uses ``YText/getStringAsync()`` to access the values asynchronously:

```swift
let localContent = await localText.getStringAsync()
print("local document text from `example`: \"\(localContent)\"")

let remoteContent = await remoteText.getStringAsync()
print("remote document text from `example`: \"\(remoteContent)\"")
```

### Synchronize the Document

The synchronization process follows a three step process:

1. Get the current state of document you want to which you want to synchronize data.
2. Compute an update from the document by comparing that state with another document.
3. Apply the computed update to the original document from which you retrieved the initial state.

The retrieved state and computed difference are raw byte buffers.
In the following example, we only synchronize in one direction - from the `localDocument` to `remoteDocument`.
In most scenarios, you likely should compute the state of both sides, compute the differences, and
synchronize in both directions:

```swift
print (" --> Synchronizing local to remote")
let remoteState = await remoteDocument.transact { txn in
    txn.transactionStateVector()
}
print("  . Size of the remote state is \(remoteState.count) bytes.")

let updateRemote = await localDocument.transact { txn in
    localDocument.diff(txn: txn, from: remoteState)
}
print("  . Size of the diff from remote state is \(updateRemote.count) bytes.")

await remoteDocument.transact { txn in
    try! txn.transactionApplyUpdate(update: updateRemote)
}
```

### Retrieve and display data

With the synchronization complete, the value of the current state of the shared data type can be extracted and used:

```swift
let localString = await localText.getStringAsync()
let remoteString = await remoteText.getStringAsync()

print("local document text from `example`: \"\(localString)\"")
print("remote document text from `example`: \"\(remoteString)\"")
```

For a more complete example that illustrates synchronizing a simple To-Do list, see the [examples directory in the YSwift repository](https://github.com/y-crdt/yswift/tree/main/examples).
