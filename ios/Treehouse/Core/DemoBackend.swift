import Foundation

/// Isolated, in-memory sample space. It never makes a network request.
@MainActor
final class DemoBackend {
    private var chat: [ChatMessage] = []
    private var pages: [Note] = []
    private var uploads: [TreehouseFile] = []
    private var bytes: [Int: Data] = [:]
    private var nextId = 100
    private var now: String { ISO8601DateFormatter().string(from: Date()) }

    init() {
        let date = "2026-10-28T13:41:00.000Z"
        chat = [
            ChatMessage(id: 1, channel: "general", author: "alex", via: "web", text: "A little place for all our plans. 🌿\nChat, notes, and the things we want to keep.", createdAt: date, replyCount: 2),
            ChatMessage(id: 2, channel: "general", parentId: 1, author: "sam", via: "web", text: "Made it up the ladder!", createdAt: date),
            ChatMessage(id: 3, channel: "general", parentId: 1, author: "alex", via: "claude", text: "Everything’s organized and ready for you both.", createdAt: date),
            ChatMessage(id: 4, channel: "general", author: "sam", via: "web", text: "Saturday idea: coffee, the farmers market, and a long walk. ☕️", createdAt: date, replyCount: 1),
            ChatMessage(id: 5, channel: "general", parentId: 4, author: "alex", via: "web", text: "Yes to all three. Let’s take the scenic route.", createdAt: date),
            ChatMessage(id: 6, channel: "general", author: "alex", via: "web", text: "A first sketch for our little corner of the internet.", fileId: 1, fileName: "Treehouse sketch.png", fileType: "image/png", createdAt: date, replyCount: 0),
            ChatMessage(id: 7, channel: "weekend-plans", author: "sam", via: "web", text: "Keeping our next adventure in here. Any ideas?", createdAt: date, replyCount: 0),
            ChatMessage(id: 8, channel: "little-things", author: "alex", via: "web", text: "The basil has a new leaf. Small victories. 🌱", createdAt: date, replyCount: 0)
        ]
        pages = [
            Note(id: 1, title: "Welcome to the Treehouse", body: "# A shared little space\n\nFor our conversations, half-formed ideas, and things worth keeping.\n\n## Make yourself at home\n\n- Chat about your day\n- Plant an idea in Notes\n- Keep a photo or a useful file\n\nEverything has a place up here. 🌿", createdBy: "alex", updatedBy: "alex", createdAt: date, updatedAt: date, path: "Welcome to the Treehouse", children: []),
            Note(id: 2, title: "Weekend plans", body: "# A slow Saturday\n\nA few good things, with room to wander.\n\n- Coffee at 9\n- Pick up something fresh at the market\n- Walk through the park\n- Cook dinner together\n\n## Bring along\n\nA tote bag, a camera, and no particular hurry.", createdBy: "sam", updatedBy: "sam", createdAt: date, updatedAt: date, path: "Weekend plans", children: ["Things to cook"]),
            Note(id: 3, parentId: 2, title: "Things to cook", body: "# Something seasonal\n\n- Roasted squash soup\n- A very good grilled cheese\n- Apple crumble\n\nSave a little for tomorrow.", createdBy: "alex", updatedBy: "alex", createdAt: date, updatedAt: date, path: "Weekend plans/Things to cook", children: [])
        ]
        let image = Bundle.main.url(forResource: "SampleSketch", withExtension: "png").flatMap { try? Data(contentsOf: $0) } ?? Data()
        bytes[1] = image
        bytes[2] = Data("A slow Saturday\nCoffee, the market, a walk, and dinner together.\n".utf8)
        uploads = [
            TreehouseFile(id: 1, name: "Treehouse sketch.png", description: "A little home among the leaves", contentType: "image/png", size: image.count, uploadedBy: "alex", createdAt: date),
            TreehouseFile(id: 2, name: "Saturday list.txt", description: "A few good things to do together", contentType: "text/plain", size: bytes[2]!.count, uploadedBy: "sam", createdAt: date)
        ]
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(value)
    }
    private func object(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func tree(parent: Int? = nil) -> [NoteNode] {
        pages.filter { $0.parentId == parent }.map {
            NoteNode(id: $0.id, parentId: $0.parentId, title: $0.title, updatedBy: $0.updatedBy,
                     updatedAt: $0.updatedAt, path: $0.path, children: tree(parent: $0.id))
        }
    }
    func respond(path: String, method: String, query: [String: String], body: Data?) throws -> Data {
        let args = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        switch (path, method) {
        case ("/api/me", _): return try object(["me": "sam"])
        case ("/api/chat/channels", _):
            let channels = ["general", "weekend-plans", "little-things"].map { name in
                let messages = chat.filter { $0.channel == name }
                return Channel(channel: name, messages: messages.count, threads: messages.filter { $0.parentId == nil }.count,
                               lastMessageAt: messages.last?.createdAt ?? now, unread: name == "general" ? 2 : 0)
            }
            return try encode(["channels": channels])
        case ("/api/chat/messages", "GET"):
            let thread = query["thread_id"].flatMap(Int.init)
            let result = chat.filter { thread != nil ? ($0.id == thread || $0.parentId == thread) : $0.channel == query["channel"] }
            return try encode(["messages": result])
        case ("/api/chat/messages", "POST"):
            nextId += 1
            let parent = args["reply_to"] as? Int
            let file = uploads.first { $0.id == args["file_id"] as? Int }
            let message = ChatMessage(id: nextId, channel: args["channel"] as? String ?? "general", parentId: parent,
                                      author: "sam", via: "web", text: args["text"] as? String ?? "", fileId: file?.id,
                                      fileName: file?.name, fileType: file?.contentType, createdAt: now, replyCount: 0)
            chat.append(message)
            if let index = chat.firstIndex(where: { $0.id == parent }) { chat[index].replyCount = (chat[index].replyCount ?? 0) + 1 }
            return try encode(["posted": message])
        case ("/api/chat/read", _): return try object(["channels_marked": 1])
        case ("/api/notes", "GET"): return try encode(["notes": tree()])
        case ("/api/notes/read", _):
            guard var note = pages.first(where: { String($0.id) == query["id"] }) else { throw APIError.message("Note not found.") }
            note.children = pages.filter { $0.parentId == note.id }.map(\.title)
            return try encode(note)
        case ("/api/notes", "PUT"):
            let path = args["path"] as? String ?? "Untitled"
            if let index = pages.firstIndex(where: { $0.path == path }) {
                pages[index].body = args["body"] as? String ?? ""
                pages[index].updatedAt = now
                pages[index].updatedBy = "sam"
            } else {
                nextId += 1
                let parentPath = path.split(separator: "/").dropLast().joined(separator: "/")
                let parent = pages.first { $0.path == parentPath }?.id
                pages.append(Note(id: nextId, parentId: parent, title: path.split(separator: "/").last.map(String.init) ?? path,
                                  body: args["body"] as? String ?? "", createdBy: "sam", updatedBy: "sam", createdAt: now,
                                  updatedAt: now, path: path, children: []))
            }
            return try object(["saved": true])
        case ("/api/notes/move", _):
            let old = args["path"] as? String ?? ""
            let new = args["new_path"] as? String ?? ""
            for index in pages.indices where pages[index].path == old || pages[index].path.hasPrefix(old + "/") {
                pages[index].path = new + pages[index].path.dropFirst(old.count)
                pages[index].title = pages[index].path.split(separator: "/").last.map(String.init) ?? new
            }
            if let index = pages.firstIndex(where: { $0.path == new }) {
                let parentPath = new.split(separator: "/").dropLast().joined(separator: "/")
                pages[index].parentId = pages.first(where: { $0.path == parentPath })?.id
            }
            return try object(["moved": true])
        case ("/api/notes/delete", _):
            let path = args["path"] as? String ?? ""
            pages.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
            return try object(["deleted": true])
        case ("/api/files", "GET"): return try encode(["files": uploads])
        default:
            let parts = path.split(separator: "/")
            if parts.count == 4, parts[1] == "files", let id = Int(parts[2]) {
                if parts[3] == "content", let data = bytes[id] { return data }
                if parts[3] == "delete" {
                    uploads.removeAll { $0.id == id }; bytes[id] = nil
                    for index in chat.indices where chat[index].fileId == id { chat[index].fileId = nil }
                    return try object(["deleted": true])
                }
            }
            throw APIError.message("This action isn’t available in the sample space.")
        }
    }
    func upload(_ upload: PendingUpload) -> TreehouseFile {
        nextId += 1
        let file = TreehouseFile(id: nextId, name: upload.name, description: "", contentType: upload.contentType,
                                size: upload.data.count, uploadedBy: "sam", createdAt: now)
        uploads.insert(file, at: 0); bytes[file.id] = upload.data
        return file
    }
}
