# ``YSwift/YMap``

A shared key-value map data type.

## Overview

YMap provides a dictionary-like interface for storing key-value pairs that automatically sync across peers.

> Important: YSwift provides parallel sync and async APIs. The async APIs are preferred.
> The sync APIs are deprecated. Do not mix sync and async APIs on the same document.

### Async Usage (Preferred)

```swift
let doc = YDocument()
let map: YMap<String> = doc.getOrCreateMap(named: "settings")

// Set values
await map.set("dark", forKey: "theme")
await map.set("en", forKey: "language")

// Get values
let theme = await map.get(key: "theme")

// Check contents
let count = await map.length()
let hasTheme = await map.containsKey("theme")

// Get all data
let allSettings = await map.toMapAsync()
let allKeys = await map.keys()
let allValues = await map.values()

// Observe changes
for await changes in map.observeAsync() {
    for change in changes {
        print("Key \(change.key) changed")
    }
}
```

## Topics

### Async APIs (Preferred)

- ``YSwift/YMap/get(key:)-99817``
- ``YSwift/YMap/set(_:forKey:)``
- ``YSwift/YMap/length()-4k0vn``
- ``YSwift/YMap/containsKey(_:)-swift.method``
- ``YSwift/YMap/keys()-2xygi``
- ``YSwift/YMap/values()-8ct1c``
- ``YSwift/YMap/toMapAsync()``
- ``YSwift/YMap/removeValue(forKey:)-8xdnq``
- ``YSwift/YMap/removeAll()-3hg4c``
- ``YSwift/YMap/observeAsync()``

### Sync APIs (Deprecated)

- ``YSwift/YMap/subscript(_:)``
- ``YSwift/YMap/length(transaction:)``
- ``YSwift/YMap/containsKey(_:transaction:)``
- ``YSwift/YMap/get(key:transaction:)``
- ``YSwift/YMap/toMap(transaction:)``
- ``YSwift/YMap/updateValue(_:forKey:transaction:)``
- ``YSwift/YMap/removeValue(forKey:transaction:)``
- ``YSwift/YMap/removeAll(transaction:)``
- ``YSwift/YMap/observe()``
- ``YSwift/YMap/observe(_:)``

### Iterating over a Map

- ``YSwift/YMap/each(transaction:_:)``
- ``YSwift/YMap/keys(transaction:_:)``
- ``YSwift/YMap/values(transaction:_:)``
- ``YSwift/YMap/YMapIterator``

### Subdocuments

- ``YSwift/YMap/getSubdoc(forKey:transaction:)``
- ``YSwift/YMap/insertSubdoc(_:forKey:transaction:)``
