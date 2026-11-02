import Foundation

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A Treehouse key must never follow a redirect to another service.
        completionHandler(nil)
    }
}

@MainActor
final class APIClient {
    static let production = URL(string: "https://workspace.example.com")!
    nonisolated static let maxFileSize = 25 * 1024 * 1024
    let endpoint: URL
    let isDemo: Bool
    let store: LocalStore
    private let key: String
    private let session: URLSession
    private let demo: DemoBackend?
    private let onUnauthorized: () -> Void
    private(set) var active = true
    private var downloadURLs: [Int: URL] = [:]
    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("treehouse-" + UUID().uuidString)

    init(endpoint: URL, key: String, demo: Bool = false, configuration: URLSessionConfiguration = .ephemeral,
         store: LocalStore? = nil, onUnauthorized: @escaping () -> Void = {}) {
        self.endpoint = endpoint
        self.key = key
        self.isDemo = demo
        self.demo = demo ? DemoBackend() : nil
        self.store = store ?? LocalStore()
        self.onUnauthorized = onUnauthorized
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    static func validatedEndpoint(_ text: String) throws -> URL {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw APIError.message("Enter a server origin, such as https://workspace.example.com.")
        }
        var allowed = components.scheme == "https"
        #if DEBUG
        allowed = allowed || (components.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
        #endif
        guard allowed, let url = components.url else { throw APIError.message("Use an HTTPS Treehouse server.") }
        return url
    }

    func deactivate() {
        active = false
        session.invalidateAndCancel()
        store.clear()
        downloadURLs.removeAll()
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func activeSessionFailed() {
        active = false
        session.invalidateAndCancel()
    }

    func request(_ path: String, method: String = "GET", query: [String: String] = [:],
                 body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        guard active else { throw CancellationError() }
        guard path.hasPrefix("/api/"), !path.contains("..") else { throw APIError.message("Invalid API path.") }
        if let demo { return try demo.respond(path: path, method: method, query: query, body: body) }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw APIError.message("Invalid server URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard active else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw APIError.message("The server didn’t send an HTTP response.") }
        if http.statusCode == 401 {
            onUnauthorized()
            throw APIError.unauthorized
        }
        if http.statusCode == 409 { throw APIError.conflict }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
            throw APIError.message(message ?? "Treehouse returned HTTP \(http.statusCode). Try again shortly.")
        }
        return data
    }

    private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder.treehouse.decode(type, from: data) }
        catch { throw APIError.message("This server response couldn’t be read. Check for a Treehouse app update.") }
    }
    func me() async throws -> String {
        struct Response: Decodable { let me: String }
        return try decode(Response.self, await request("/api/me")).me
    }
    func channels() async throws -> [Channel] {
        struct Response: Decodable { let channels: [Channel] }
        return try decode(Response.self, await request("/api/chat/channels")).channels
    }
    func messages(channel: String, thread: Int? = nil) async throws -> [ChatMessage] {
        struct Response: Decodable { let messages: [ChatMessage] }
        var query = ["channel": channel, "limit": "200"]
        if let thread { query["thread_id"] = String(thread) }
        return try decode(Response.self, await request("/api/chat/messages", query: query)).messages
    }
    func post(text: String, channel: String, replyTo: Int?, fileId: Int?) async throws -> ChatMessage {
        struct Response: Decodable { let posted: ChatMessage }
        guard text.utf16.count <= 10_000 else { throw APIError.message("Messages can be up to 10,000 characters.") }
        var body: [String: Any] = ["text": text, "channel": channel]
        if let replyTo { body["reply_to"] = replyTo }
        if let fileId { body["file_id"] = fileId }
        return try decode(Response.self, await request("/api/chat/messages", method: "POST", body: json(body))).posted
    }
    func markRead(channel: String) async throws {
        _ = try await request("/api/chat/read", method: "POST", body: json(["channel": channel]))
    }
    func notes() async throws -> [NoteNode] {
        struct Response: Decodable { let notes: [NoteNode] }
        return try decode(Response.self, await request("/api/notes")).notes
    }
    func note(id: Int) async throws -> Note {
        try decode(Note.self, await request("/api/notes/read", query: ["id": String(id)]))
    }
    func saveNote(path: String, text: String, original: Note? = nil) async throws {
        guard text.utf16.count <= 200_000 else { throw APIError.message("Notes can be up to 200,000 characters.") }
        if let original {
            let latest = try await note(id: original.id)
            // The deployed API has no conditional writes. Detect already-visible edits;
            // do not claim this preflight prevents a write racing the following PUT.
            guard latest.updatedAt == original.updatedAt, latest.body == original.body,
                  latest.path == original.path else { throw APIError.conflict }
        } else {
            let existing = try await notes().flatMap(\.flattened)
            guard !existing.contains(where: { $0.path == path }) else { throw APIError.message("A note already exists at that path. Open it to edit.") }
        }
        _ = try await request("/api/notes", method: "PUT", body: json(["path": path, "body": text]))
    }
    func moveNote(path: String, newPath: String) async throws {
        _ = try await request("/api/notes/move", method: "POST", body: json(["path": path, "new_path": newPath]))
    }
    func deleteNote(path: String, recursive: Bool) async throws {
        _ = try await request("/api/notes/delete", method: "POST", body: json(["path": path, "recursive": recursive]))
    }
    func files() async throws -> [TreehouseFile] {
        struct Response: Decodable { let files: [TreehouseFile] }
        return try decode(Response.self, await request("/api/files")).files
    }
    func upload(_ file: PendingUpload) async throws -> TreehouseFile {
        guard file.data.count <= Self.maxFileSize else { throw APIError.message("Files can be up to 25 MB.") }
        if let demo { return demo.upload(file) }
        struct Response: Decodable { let uploaded: TreehouseFile }
        let boundary = "Treehouse-" + UUID().uuidString
        let name = file.name.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        let type = file.contentType.contains("\n") || file.contentType.contains("\r") ? "application/octet-stream" : file.contentType
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(type)\r\n\r\n".utf8)
        body.append(file.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try decode(Response.self, await request("/api/files", method: "POST", body: body,
                                                     contentType: "multipart/form-data; boundary=\(boundary)")).uploaded
    }
    func deleteFile(id: Int) async throws {
        _ = try await request("/api/files/\(id)/delete", method: "POST", body: json([:]))
        if let url = downloadURLs.removeValue(forKey: id) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
    func download(_ file: TreehouseFile) async throws -> URL {
        if let url = downloadURLs[file.id], FileManager.default.fileExists(atPath: url.path) { return url }
        let data = try await request("/api/files/\(file.id)/content")
        guard active else { throw CancellationError() }
        let folder = temporaryDirectory.appendingPathComponent(String(file.id), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = (file.name as NSString).lastPathComponent
        let url = folder.appendingPathComponent(name.isEmpty || name == "." || name == ".." ? "attachment" : name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        downloadURLs[file.id] = url
        return url
    }
}
