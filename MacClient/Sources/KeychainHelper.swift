import Foundation
import Security

/// Persistent secrets live only in Keychain. Legacy disk copies are removed
/// only after a successful migration, so a locked Keychain cannot lose an identity.
public enum KeychainHelper {
    public static let serviceIdentity = "com.swimble.identity"
    public static let serviceServers = "com.swimble.servers"
    public static let legacyServiceIdentity = "com.mumbleglass.identity"
    public static let legacyServiceServers = "com.mumbleglass.servers"
    private struct StoredIdentity: Codable { let certPem: String; let keyPem: String }
    private static func legacyFiles(_ name: String) -> [URL] {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ["Swimble", "MumbleGlass"].map { root.appendingPathComponent($0).appendingPathComponent(name) }
    }
    @discardableResult
    public static func saveClientIdentity(_ identity: ClientIdentity) -> Bool {
        guard let data = try? JSONEncoder().encode(StoredIdentity(certPem: identity.certPem, keyPem: identity.keyPem)),
              saveToKeychain(account: "identity", service: serviceIdentity, data: data) else { return false }
        for file in legacyFiles("identity.json") { try? FileManager.default.removeItem(at: file) }
        for service in [serviceIdentity, legacyServiceIdentity] {
            _ = deleteFromKeychain(account: "client_cert_pem", service: service)
            _ = deleteFromKeychain(account: "client_key_pem", service: service)
        }
        return true
    }
    /// Stored identity data exists but cannot be used. Callers must not replace it silently.
    public struct CorruptIdentityError: LocalizedError {
        public let source: String
        public var errorDescription: String? {
            "The stored client identity (\(source)) is damaged or incomplete. It was left untouched; restore it from a backup or import/generate a new identity in Certificate settings."
        }
    }
    private static func validIdentity(certPem: String, keyPem: String) -> Bool {
        certPem.contains("-----BEGIN CERTIFICATE-----") && keyPem.contains("-----BEGIN") && keyPem.contains("PRIVATE KEY-----")
    }
    /// Returns nil only when no identity exists anywhere. Present-but-unusable data throws.
    public static func loadClientIdentity() throws -> ClientIdentity? {
        if let data = try checkedLoad(account: "identity", service: serviceIdentity) {
            guard let stored = try? JSONDecoder().decode(StoredIdentity.self, from: data),
                  validIdentity(certPem: stored.certPem, keyPem: stored.keyPem) else {
                throw CorruptIdentityError(source: "Keychain item")
            }
            // Also retry cleanup left by an interrupted previous migration.
            for file in legacyFiles("identity.json") { try? FileManager.default.removeItem(at: file) }
            return ClientIdentity(certPem: stored.certPem, keyPem: stored.keyPem)
        }
        for file in legacyFiles("identity.json") {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            guard let data = try? Data(contentsOf: file) else { throw CocoaError(.fileReadNoPermission) }
            guard let value = try? JSONDecoder().decode(StoredIdentity.self, from: data),
                  validIdentity(certPem: value.certPem, keyPem: value.keyPem) else {
                throw CorruptIdentityError(source: "legacy file \(file.lastPathComponent)")
            }
            let identity = ClientIdentity(certPem: value.certPem, keyPem: value.keyPem)
            guard saveClientIdentity(identity) else { throw CocoaError(.fileWriteNoPermission) }
            return identity
        }
        for service in [serviceIdentity, legacyServiceIdentity] {
            let cert = try checkedLoad(account: "client_cert_pem", service: service)
            let key = try checkedLoad(account: "client_key_pem", service: service)
            if cert == nil && key == nil { continue }
            guard let cert, let key,
                  let certPem = String(data: cert, encoding: .utf8), let keyPem = String(data: key, encoding: .utf8),
                  validIdentity(certPem: certPem, keyPem: keyPem) else {
                throw CorruptIdentityError(source: "legacy Keychain items")
            }
            let identity = ClientIdentity(certPem: certPem, keyPem: keyPem)
            guard saveClientIdentity(identity) else { throw CocoaError(.fileWriteNoPermission) }
            return identity
        }
        return nil
    }
    // MARK: Access tokens (scoped per server, never shared between servers)
    public static let serviceTokens = "com.swimble.access-tokens"
    private static let legacyTokensAccount = "__legacy-unassigned__"
    private static let tokenLock = NSLock()
    private static func readTokens(account: String) -> [String] {
        guard let data = loadFromKeychain(account: account, service: serviceTokens),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }
    private static func writeTokens(_ tokens: [String], account: String) -> Bool {
        if tokens.isEmpty { return deleteFromKeychain(account: account, service: serviceTokens) }
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        return saveToKeychain(account: account, service: serviceTokens, data: data)
    }
    public static func loadAccessTokens(serverKey: String) -> [String] {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return readTokens(account: serverKey)
    }
    /// Atomic read-modify-write so concurrent windows on one server do not lose edits.
    @discardableResult
    public static func updateAccessTokens(serverKey: String, _ change: (inout [String]) -> Void) -> [String] {
        tokenLock.lock(); defer { tokenLock.unlock() }
        var list = readTokens(account: serverKey)
        change(&list)
        _ = writeTokens(list, account: serverKey)
        return list
    }
    /// Moves the old global token preference into Keychain without assigning it to any server.
    /// The plaintext copy is removed only after the Keychain write succeeds.
    public static func migrateLegacyAccessTokens() {
        tokenLock.lock(); defer { tokenLock.unlock() }
        let key = "Swimble_AccessTokens"
        guard let old = UserDefaults.standard.stringArray(forKey: key) else { return }
        var merged = readTokens(account: legacyTokensAccount)
        for t in old where !merged.contains(t) { merged.append(t) }
        if writeTokens(merged, account: legacyTokensAccount) { UserDefaults.standard.removeObject(forKey: key) }
    }
    public static func loadLegacyUnassignedTokens() -> [String] {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return readTokens(account: legacyTokensAccount)
    }
    public static func clearLegacyUnassignedTokens() {
        tokenLock.lock(); defer { tokenLock.unlock() }
        _ = writeTokens([], account: legacyTokensAccount)
    }
    public static func loadServerFingerprint(host: String, port: UInt16) -> String? {
        loadFromKeychain(account: "\(host.lowercased()):\(port)", service: "com.swimble.server-trust").flatMap { String(data: $0, encoding: .utf8) }
    }
    public static func saveServerFingerprint(host: String, port: UInt16, fingerprint: String) -> Bool {
        saveToKeychain(account: "\(host.lowercased()):\(port)", service: "com.swimble.server-trust", data: Data(fingerprint.utf8))
    }
    public static func forgetServerFingerprint(host: String, port: UInt16) -> Bool {
        deleteFromKeychain(account: "\(host.lowercased()):\(port)", service: "com.swimble.server-trust")
    }
    @discardableResult
    public static func saveServerPassword(bookmarkId: UUID, password: String) -> Bool {
        saveToKeychain(account: bookmarkId.uuidString, service: serviceServers, data: Data(password.utf8))
    }
    /// Migrates all entries before deleting either legacy password cache.
    public static func migratePasswords() {
        for file in legacyFiles("passwords.json") {
            guard let data = try? Data(contentsOf: file), let map = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            var complete = true
            for (id, password) in map {
                if !saveToKeychain(account: id, service: serviceServers, data: Data(password.utf8)) { complete = false }
            }
            if complete { try? FileManager.default.removeItem(at: file) }
        }
    }
    public static func loadServerPassword(bookmarkId: UUID) -> String? {
        for service in [serviceServers, legacyServiceServers] {
            if let data = loadFromKeychain(account: bookmarkId.uuidString, service: service) { return String(data: data, encoding: .utf8) }
        }
        return nil
    }
    @discardableResult
    public static func deleteServerPassword(bookmarkId: UUID) -> Bool {
        let current = deleteFromKeychain(account: bookmarkId.uuidString, service: serviceServers)
        let legacy = deleteFromKeychain(account: bookmarkId.uuidString, service: legacyServiceServers)
        return current && legacy
    }
    private static func saveToKeychain(account: String, service: String, data: Data) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query; item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    private static func loadFromKeychain(account: String, service: String) -> Data? { try? checkedLoad(account: account, service: service) }
    private static func checkedLoad(account: String, service: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return item as? Data
    }
    private static func deleteFromKeychain(account: String, service: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
