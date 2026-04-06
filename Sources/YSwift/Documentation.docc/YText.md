# ``YSwift/YText``

A shared text data type with rich text support.

## Overview

YText provides a text editing interface that automatically syncs across peers, with support for rich text formatting and embedded objects.

> Important: YSwift provides parallel sync and async APIs. The async APIs are preferred.
> The sync APIs are deprecated. Do not mix sync and async APIs on the same document.

### Async Usage (Preferred)

```swift
let doc = YDocument()
let text = doc.getOrCreateText(named: "content")

// Modify text
await text.append("Hello, ")
await text.append("World!")
await text.insert("beautiful ", at: 7)

// Get text content
let content = await text.getStringAsync()
let length = await text.lengthAsync()

// Rich text formatting
await text.format(at: 7, length: 9, attributes: ["bold": true])
await text.insertWithAttributes("styled", attributes: ["color": "red"], at: 0)

// Remove text
await text.removeRange(start: 0, length: 6)

// Observe changes
for await changes in text.observeAsync() {
    for change in changes {
        switch change {
        case .inserted(let value, let attrs):
            print("Inserted: \(value)")
        case .deleted(let count):
            print("Deleted \(count) characters")
        case .retained(let count, let attrs):
            print("Retained \(count) characters")
        }
    }
}
```

## Topics

### Async APIs (Preferred)

- ``YSwift/YText/append(_:)-7cwpz``
- ``YSwift/YText/insert(_:at:)-6l00w``
- ``YSwift/YText/insertWithAttributes(_:attributes:at:)-4jxqb``
- ``YSwift/YText/insertEmbed(_:at:)-3y8lv``
- ``YSwift/YText/insertEmbedWithAttributes(_:attributes:at:)-15v4t``
- ``YSwift/YText/removeRange(start:length:)-5h6jy``
- ``YSwift/YText/format(at:length:attributes:)-yk68``
- ``YSwift/YText/getStringAsync()``
- ``YSwift/YText/lengthAsync()``
- ``YSwift/YText/diffAsync()``
- ``YSwift/YText/applyDelta(_:)-3cqxc``
- ``YSwift/YText/observeAsync()``

### Sync APIs (Deprecated)

- ``YSwift/YText/append(_:in:)``
- ``YSwift/YText/insert(_:at:in:)``
- ``YSwift/YText/insertWithAttributes(_:attributes:at:in:)``
- ``YSwift/YText/insertEmbed(_:at:in:)``
- ``YSwift/YText/insertEmbedWithAttributes(_:attributes:at:in:)``
- ``YSwift/YText/removeRange(start:length:in:)``
- ``YSwift/YText/format(at:length:attributes:in:)``
- ``YSwift/YText/getString(in:)``
- ``YSwift/YText/length(in:)``
- ``YSwift/YText/diff(in:)``
- ``YSwift/YText/applyDelta(_:in:)``
- ``YSwift/YText/observe()``
- ``YSwift/YText/observe(_:)``

### Inspecting the Text

- ``YSwift/YText/description``

### Comparing Text

- ``YSwift/YText/!=(_:_:)``
- ``YSwift/YText/==(_:_:)``

### Text Changes

- ``YSwift/YTextChange``
- ``YSwift/YTextDiff``
