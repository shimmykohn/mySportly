import Foundation
import Security
import CryptoKit

struct SourceSecrets: Codable, Sendable {
    var address = ""
    var username = ""
    var password = ""
    var guideAddress = ""
    var output = "m3u8"
    var isFile = false
}

enum KeychainStore {
    static func write(_ data: Data, account: String, sync: Bool = false) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.iska.mysportly", kSecAttrAccount as String: account, kSecAttrSynchronizable as String: sync]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var new = query; attributes.forEach { new[$0.key] = $0.value }
            guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else { throw SecureFailure.write }
        } else if result != errSecSuccess { throw SecureFailure.write }
    }
    static func read(_ account: String, sync: Bool = false) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.iska.mysportly", kSecAttrAccount as String: account, kSecAttrSynchronizable as String: sync, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureFailure.read }
        return result as? Data
    }
    static func remove(_ account: String, sync: Bool = false) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.iska.mysportly", kSecAttrAccount as String: account, kSecAttrSynchronizable as String: sync]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureFailure.write }
    }
    static func credentials(_ sourceID: UUID) throws -> SourceSecrets? {
        guard let data = try read("source.\(sourceID)") ?? read("source.\(sourceID)", sync: true) else { return nil }
        return try JSONDecoder().decode(SourceSecrets.self, from: data)
    }
    static func save(_ secrets: SourceSecrets, sourceID: UUID, sync: Bool = true) throws {
        let data = try JSONEncoder().encode(secrets)
        try write(data, account: "source.\(sourceID)")
        if sync { try write(data, account: "source.\(sourceID)", sync: true) }
    }
    enum SecureFailure: Error, LocalizedError {
        case read, write
        var errorDescription: String? { "The device Keychain is unavailable. Unlock your device and try again." }
    }
}

actor CatalogCache {
    private let directory: URL
    init() {
        directory = URL.applicationSupportDirectory.appending(path: "ProviderCache", directoryHint: .isDirectory)
    }
    private func key() throws -> SymmetricKey {
        if let data = try KeychainStore.read("catalog-encryption-key") { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        try KeychainStore.write(key.withUnsafeBytes { Data($0) }, account: "catalog-encryption-key")
        return key
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func load() throws -> CatalogSnapshot {
        let file = directory.appending(path: "catalog.sealed")
        guard FileManager.default.fileExists(atPath: file.path) else { return CatalogSnapshot() }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: file))
        return try CatalogCodec.decode(CatalogSnapshot.self, from: AES.GCM.open(sealed, using: key()))
    }
    func save(_ snapshot: CatalogSnapshot) throws {
        try prepare()
        let sealed = try AES.GCM.seal(CatalogCodec.encode(snapshot), using: key())
        guard let data = sealed.combined else { throw KeychainStore.SecureFailure.write }
        try data.write(to: directory.appending(path: "catalog.sealed"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func savePlaylist(_ text: String, sourceID: UUID) throws {
        try prepare()
        let sealed = try AES.GCM.seal(Data(text.utf8), using: key())
        guard let data = sealed.combined else { throw KeychainStore.SecureFailure.write }
        try data.write(to: directory.appending(path: "\(sourceID).sealed"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func playlist(_ sourceID: UUID) throws -> String {
        let data = try Data(contentsOf: directory.appending(path: "\(sourceID).sealed"))
        return String(decoding: try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key()), as: UTF8.self)
    }
    func removePlaylist(_ sourceID: UUID) throws {
        let file = directory.appending(path: "\(sourceID).sealed")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
