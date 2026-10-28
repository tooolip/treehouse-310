import Foundation
import Security

struct Credentials: Codable {
    var endpoint: URL
    var key: String
}

enum CredentialStore {
    private static let service = "house.tree310.ios.credentials"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "personal-key"]
    }
    static func load() -> Credentials? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }
    static func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let update = [kSecValueData as String: data,
                      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            update.forEach { attributes[$0.key] = $0.value }
            let inserted = SecItemAdd(attributes as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw APIError.message("Couldn’t save your key securely (\(inserted)).") }
        } else if status != errSecSuccess {
            throw APIError.message("Couldn’t save your key securely (\(status)).")
        }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

@MainActor
final class LocalStore {
    let directory: URL
    private(set) var active = true
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Treehouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var location = self.directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? location.setResourceValues(values)
    }
    private func url(_ key: String) -> URL {
        let encoded = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(encoded + ".json")
    }
    func read<T: Decodable>(_ key: String, as: T.Type = T.self) -> T? {
        guard active, let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    func write<T: Encodable>(_ value: T, key: String) {
        guard active, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(key), options: [.atomic, .completeFileProtection])
    }
    func remove(_ key: String) { try? FileManager.default.removeItem(at: url(key)) }
    func clear() {
        active = false
        try? FileManager.default.removeItem(at: directory)
    }
}
