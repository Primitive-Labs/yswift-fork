import Combine
import Yniffi

/// An event emitted when subdocuments are added, loaded, or removed from a parent document.
public struct YSubdocsEvent {
    /// Subdocuments that were added to the parent document.
    public let added: [YDocument]

    /// Subdocuments that were loaded.
    public let loaded: [YDocument]

    /// Subdocuments that were removed from the parent document.
    public let removed: [YDocument]

    init(from event: YrsSubdocsEvent) {
        self.added = event.added.map { YDocument(wrapping: $0) }
        self.loaded = event.loaded.map { YDocument(wrapping: $0) }
        self.removed = event.removed.map { YDocument(wrapping: $0) }
    }
}

/// Internal delegate for observing subdocument lifecycle changes.
class YSubdocsObservationDelegateWrapper: YrsSubdocsObservationDelegate {
    private let callback: (YSubdocsEvent) -> Void

    init(callback: @escaping (YSubdocsEvent) -> Void) {
        self.callback = callback
    }

    func call(event: YrsSubdocsEvent) {
        callback(YSubdocsEvent(from: event))
    }
}

/// Internal delegate for observing document update events.
class YUpdateObservationDelegateWrapper: YrsUpdateObservationDelegate {
    private let callback: ([UInt8]) -> Void

    init(callback: @escaping ([UInt8]) -> Void) {
        self.callback = callback
    }

    func call(event: YrsUpdateEvent) {
        callback(event.update)
    }
}

/// Internal delegate for observing document destroy events.
class YDestroyObservationDelegateWrapper: YrsDestroyObservationDelegate {
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func call() {
        callback()
    }
}
