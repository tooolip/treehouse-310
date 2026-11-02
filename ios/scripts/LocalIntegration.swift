import Foundation

/// Compile alongside Core/*.swift and run only against an isolated local Worker.
@main struct LocalIntegration {
    @MainActor static func main() async throws {
        let endpoint = URL(string: "http://127.0.0.1:8787")!
        let store = LocalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("TreehouseIntegration-" + UUID().uuidString))
        let api = APIClient(endpoint: endpoint, key: "local-member-two-key", store: store)
        defer { api.deactivate() }
        let person = try await api.me()
        precondition(person == "member-two")
        let channel = "ios-test-" + UUID().uuidString.prefix(8).lowercased()
        let root = try await api.post(text: "Local iOS integration test", channel: channel, replyTo: nil, fileId: nil)
        let uploaded = try await api.upload(PendingUpload(name: "ios-test.txt", contentType: "text/plain", data: Data("Round trip verified".utf8)))
        let reply = try await api.post(text: "A reply with a file", channel: channel, replyTo: root.id, fileId: uploaded.id)
        let thread = try await api.messages(channel: channel, thread: root.id)
        precondition(thread.contains { $0.id == reply.id && $0.fileId == uploaded.id })
        let download = try await api.download(uploaded)
        let content = try String(contentsOf: download, encoding: .utf8)
        precondition(content == "Round trip verified")
        try await api.markRead(channel: channel)
        let channels = try await api.channels()
        precondition(channels.contains { $0.channel == channel && $0.unread == 0 })
        let path = "iOS integration " + UUID().uuidString.prefix(8)
        try await api.saveNote(path: path, text: "# Local test\n\nOriginal note")
        let notes = try await api.notes().flatMap(\.flattened)
        let node = notes.first { $0.path == path }!
        let note = try await api.note(id: node.id)
        try await api.saveNote(path: path, text: "# Local test\n\nUpdated note", original: note)
        try await api.moveNote(path: path, newPath: path + " renamed")
        let updated = try await api.note(id: node.id)
        precondition(updated.title.hasSuffix("renamed"))
        try await api.deleteNote(path: updated.path, recursive: false)
        try await api.deleteFile(id: uploaded.id)
        let after = try await api.messages(channel: channel, thread: root.id)
        precondition(after.first { $0.id == reply.id }?.fileId == nil)
        print("PASS: local Worker identity, channels, messages, reply, multipart upload, authenticated download, read state, notes create/read/update/move/delete, and file deletion.")
    }
}
