# ``YSwift/YArray``

A shared list data type.

## Overview

YArray provides an array-like interface for storing ordered elements that automatically sync across peers.

> Important: YSwift provides parallel sync and async APIs. The async APIs are preferred.
> The sync APIs are deprecated. Do not mix sync and async APIs on the same document.

### Async Usage (Preferred)

```swift
let doc = YDocument()
let array: YArray<Int> = doc.getOrCreateArray(named: "numbers")

// Add elements
await array.append(1)
await array.prepend(0)
await array.insert(at: 1, value: 42)
await array.insertArray(at: 0, values: [10, 20, 30])

// Get elements
let first = await array.get(index: 0)
let all = await array.toArrayAsync()
let count = await array.lengthAsync()

// Remove elements
await array.remove(at: 0)
await array.removeRange(start: 1, length: 2)

// Observe changes
for await changes in array.observeAsync() {
    for change in changes {
        switch change {
        case .added(let elements):
            print("Added: \(elements)")
        case .removed(let count):
            print("Removed \(count) elements")
        case .retained(let count):
            print("Retained \(count) elements")
        }
    }
}
```

## Topics

### Async APIs (Preferred)

- ``YSwift/YArray/get(index:)-6k4t3``
- ``YSwift/YArray/append(_:)-2u3x9``
- ``YSwift/YArray/prepend(_:)-7a4vn``
- ``YSwift/YArray/insert(at:value:)-8wk5r``
- ``YSwift/YArray/insertArray(at:values:)-54q3o``
- ``YSwift/YArray/remove(at:)-3twqw``
- ``YSwift/YArray/removeRange(start:length:)-7fge7``
- ``YSwift/YArray/lengthAsync()``
- ``YSwift/YArray/toArrayAsync()``
- ``YSwift/YArray/observeAsync()``

### Sync APIs (Deprecated)

- ``YSwift/YArray/get(index:transaction:)``
- ``YSwift/YArray/append(_:transaction:)``
- ``YSwift/YArray/prepend(_:transaction:)``
- ``YSwift/YArray/insert(at:value:transaction:)``
- ``YSwift/YArray/insertArray(at:values:transaction:)``
- ``YSwift/YArray/remove(at:transaction:)``
- ``YSwift/YArray/removeRange(start:length:transaction:)``
- ``YSwift/YArray/length(transaction:)``
- ``YSwift/YArray/toArray(transaction:)``
- ``YSwift/YArray/observe()``
- ``YSwift/YArray/observe(_:)``

### Iterating over an Array

- ``YSwift/YArray/each(transaction:_:)``
- ``YSwift/YArray/YArrayIterator``

### Subdocuments

- ``YSwift/YArray/getSubdoc(at:transaction:)``
- ``YSwift/YArray/insertSubdoc(at:_:transaction:)``

### Nested Shared Types

- ``YSwift/YArray/getMap(at:transaction:)``
- ``YSwift/YArray/getArray(at:transaction:)``
- ``YSwift/YArray/getText(at:transaction:)``
- ``YSwift/YArray/insertMap(at:transaction:)``
- ``YSwift/YArray/insertArray(at:transaction:)-4h6cg``
- ``YSwift/YArray/insertText(at:transaction:)``
- ``YSwift/YArray/pushMap(transaction:)``
- ``YSwift/YArray/pushArray(transaction:)``
- ``YSwift/YArray/pushText(transaction:)``
- ``YSwift/YArray/move(from:to:transaction:)``
- ``YSwift/YArray/moveRange(from:to:target:transaction:)``
