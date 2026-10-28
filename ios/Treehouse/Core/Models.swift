import Foundation
import UniformTypeIdentifiers

struct Channel: Codable, Identifiable, Hashable {
    var channel: String
    var messages: Int
    var threads: Int
    var lastMessageAt: String
    var unread: Int
    var id: String { channel }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: Int
    var channel: String
    var parentId: Int?
    var author: String
    var via: String
    var text: String
    var fileId: Int?
    var fileName: String?
    var fileType: String?
    var createdAt: String
    var replyCount: Int?
    var authorLabel: String { author.capitalized + (via == "claude" ? "’s Claude" : "") }
    var attachment: TreehouseFile? {
        guard let fileId else { return nil }
        return TreehouseFile(id: fileId, name: fileName ?? "Attachment", description: "",
                             contentType: fileType ?? "application/octet-stream", size: 0,
                             uploadedBy: author, createdAt: createdAt)
    }
}

struct NoteNode: Codable, Identifiable, Hashable {
    var id: Int
    var parentId: Int?
    var title: String
    var updatedBy: String
    var updatedAt: String
    var path: String
    var children: [NoteNode]
    var descendants: Int { children.reduce(0) { $0 + 1 + $1.descendants } }
    var flattened: [NoteNode] { [self] + children.flatMap(\.flattened) }
}

struct Note: Codable, Identifiable, Hashable {
    var id: Int
    var parentId: Int?
    var title: String
    var body: String
    var createdBy: String
    var updatedBy: String
    var createdAt: String
    var updatedAt: String
    var path: String
    var children: [String]
}

struct TreehouseFile: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var description: String
    var contentType: String
    var size: Int
    var uploadedBy: String
    var createdAt: String
    var isImage: Bool { ["image/png", "image/jpeg", "image/gif", "image/heic", "image/webp"].contains(contentType) }
    var canPreview: Bool { isImage || contentType == "application/pdf" || contentType.hasPrefix("text/plain") || contentType == "text/markdown" }
    var symbol: String {
        if isImage { return "photo" }
        if contentType == "application/pdf" { return "doc.richtext" }
        return "doc.text"
    }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
}

struct PendingUpload: Identifiable {
    let id = UUID()
    let name: String
    let contentType: String
    let data: Data
    var uploaded: TreehouseFile?

    static func read(_ url: URL) throws -> PendingUpload {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= APIClient.maxFileSize else { throw APIError.message("Files can be up to 25 MB.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= APIClient.maxFileSize else { throw APIError.message("Files can be up to 25 MB.") }
        return PendingUpload(name: url.lastPathComponent,
                             contentType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream",
                             data: data)
    }
}

enum ServerDate {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func label(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

extension JSONDecoder {
    static var treehouse: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case message(String)
    case conflict
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your key is no longer valid. Paste your current Treehouse key to reconnect."
        case .message(let text): return text
        case .conflict: return "This note changed since you opened it. Your draft is safe. Reload the latest version before saving."
        }
    }
}
