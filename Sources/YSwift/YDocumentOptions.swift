import Yniffi

/// Options for creating a YDocument with custom configuration.
public struct YDocumentOptions: Sendable {
    /// When set to true, the document will automatically load when accessed as a subdocument.
    public var autoLoad: Bool

    /// A custom client ID for this document. If not provided, a random one will be generated.
    public var clientId: UInt64?

    /// A custom GUID for this document. If not provided, a random UUID will be generated.
    public var guid: String?

    /// Whether the document should be loaded when accessed. Defaults to true.
    public var shouldLoad: Bool

    /// Creates document options with the specified configuration.
    /// - Parameters:
    ///   - autoLoad: When true, the document will automatically load when accessed as a subdocument.
    ///   - clientId: A custom client ID. If nil, a random one will be generated.
    ///   - guid: A custom GUID. If nil, a random UUID will be generated.
    ///   - shouldLoad: Whether the document should be loaded when accessed. Defaults to true.
    public init(
        autoLoad: Bool = false,
        clientId: UInt64? = nil,
        guid: String? = nil,
        shouldLoad: Bool = true
    ) {
        self.autoLoad = autoLoad
        self.clientId = clientId
        self.guid = guid
        self.shouldLoad = shouldLoad
    }

    /// Converts to the internal YrsDocOptions type.
    internal var yrsOptions: YrsDocOptions {
        YrsDocOptions(
            autoLoad: autoLoad,
            clientId: clientId,
            guid: guid,
            shouldLoad: shouldLoad
        )
    }
}
