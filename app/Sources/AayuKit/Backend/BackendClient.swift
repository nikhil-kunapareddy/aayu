import Foundation

/// The backend as the model sees it: typed requests in, decoded results out,
/// and the events it pushes. `Backend` runs the real helper; tests use a fake.
protocol BackendClient: Sendable {
    /// Send `request` and decode its result.
    func call<Request: BackendRequest>(_ request: Request) async throws -> Request.Result

    /// Events the backend pushes, e.g. "reloaded" after an auto-reload. Meant
    /// for a single listener (the model).
    var events: AsyncStream<String> { get }
}

/// One protocol method (`Server.METHODS` in backend/aayu_backend/server.py):
/// its name, its params — the encoded request, keyed exactly as the Python
/// method's arguments — and the type its result decodes to.
protocol BackendRequest: Encodable, Sendable {
    associatedtype Result: Decodable & Sendable
    static var method: String { get }
}

/// `open(folder)`: load the export at `folder`; returns its status, with any load error.
struct OpenRequest: BackendRequest {
    typealias Result = FolderStatus
    static let method = "open"
    let folder: String
}

/// `reload()`: re-read the open folder (⌘R). Params are `{}`.
struct ReloadRequest: BackendRequest {
    typealias Result = FolderStatus
    static let method = "reload"
}

/// `status(folder)`: what a folder contains, for the Settings status line.
struct StatusRequest: BackendRequest {
    typealias Result = FolderStatus
    static let method = "status"
    let folder: String
}

/// `dashboard(selection, units, default_range, night)`: everything the
/// dashboard shows. A nil `selection` (the default range) or `night` (the
/// window's last night) goes over as JSON null, never as a missing key.
struct DashboardRequest: BackendRequest, Equatable {
    typealias Result = Dashboard
    static let method = "dashboard"
    let selection: String?
    let units: Units
    let defaultRange: DefaultRange
    let night: String?

    private enum CodingKeys: String, CodingKey {
        case selection, units, night
        case defaultRange = "default_range"
    }

    // Written out because the synthesized version leaves nil keys out.
    func encode(to encoder: any Encoder) throws {
        var params = encoder.container(keyedBy: CodingKeys.self)
        if let selection { try params.encode(selection, forKey: .selection) } else { try params.encodeNil(forKey: .selection) }
        try params.encode(units, forKey: .units)
        try params.encode(defaultRange, forKey: .defaultRange)
        if let night { try params.encode(night, forKey: .night) } else { try params.encodeNil(forKey: .night) }
    }
}

/// `watch(enabled)`: turn auto-reload on or off. Returns null.
struct WatchRequest: BackendRequest {
    typealias Result = Ignored
    static let method = "watch"
    let enabled: Bool
}

/// A result we don't need (methods that return null).
struct Ignored: Decodable, Sendable {
    init() {}
    init(from decoder: any Decoder) throws {}
}
