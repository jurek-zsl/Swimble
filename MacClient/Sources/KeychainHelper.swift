import Foundation
import Security

/// Helper for securely persisting client identity certificates and server passwords.
/// Uses an Application Support JSON cache for instantaneous, non-blocking UI startup
/// and synchronizes with the macOS Keychain for system credential integration.
public enum KeychainHelper {
    public static let serviceIdentity = "com.swimble.identity"
    public static let serviceServers = "com.swimble.servers"
    public static let legacyServiceIdentity = "com.mumbleglass.identity"
    public static let legacyServiceServers = "com.mumbleglass.servers"

    private struct StoredIdentity: Codable {
        let certPem: String
        let keyPem: String
    }

    private static var appSupportDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("Swimble", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
            // Migrate legacy MumbleGlass identity if available
            let legacyDir = paths[0].appendingPathComponent("MumbleGlass", isDirectory: true)
            let legacyFile = legacyDir.appendingPathComponent("identity.json")
            if FileManager.default.fileExists(atPath: legacyFile.path) {
                try? FileManager.default.copyItem(at: legacyFile, to: dir.appendingPathComponent("identity.json"))
            }
        }
        return dir
    }

    private static var identityFileURL: URL {
        return appSupportDirectory.appendingPathComponent("identity.json")
    }

    private static var passwordsFileURL: URL {
        return appSupportDirectory.appendingPathComponent("passwords.json")
    }

    // MARK: - Client Identity (X.509 Certificate & Private Key)

    @discardableResult
    public static func saveClientIdentity(_ identity: ClientIdentity) -> Bool {
        // 1. Fast local persistence for instant non-blocking load
        let stored = StoredIdentity(certPem: identity.certPem, keyPem: identity.keyPem)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: identityFileURL, options: [.atomic])
        }

        // 2. Asynchronous Keychain backup to avoid blocking the main UI thread
        DispatchQueue.global(qos: .utility).async {
            guard let certData = identity.certPem.data(using: .utf8),
                  let keyData = identity.keyPem.data(using: .utf8) else { return }
            _ = saveToKeychain(account: "client_cert_pem", service: serviceIdentity, data: certData)
            _ = saveToKeychain(account: "client_key_pem", service: serviceIdentity, data: keyData)
        }
        return true
    }

    public static func loadClientIdentity() -> ClientIdentity? {
        // 1. Check local file cache first (0.01ms, non-blocking)
        if let data = try? Data(contentsOf: identityFileURL),
           let stored = try? JSONDecoder().decode(StoredIdentity.self, from: data),
           !stored.certPem.isEmpty, !stored.keyPem.isEmpty {
            return ClientIdentity(certPem: stored.certPem, keyPem: stored.keyPem)
        }

        // 2. Fallback to Keychain if file cache is empty
        for service in [serviceIdentity, legacyServiceIdentity] {
            if let certData = loadFromKeychain(account: "client_cert_pem", service: service),
               let keyData = loadFromKeychain(account: "client_key_pem", service: service),
               let certPem = String(data: certData, encoding: .utf8),
               let keyPem = String(data: keyData, encoding: .utf8),
               !certPem.isEmpty, !keyPem.isEmpty {
                let identity = ClientIdentity(certPem: certPem, keyPem: keyPem)
                // Cache locally for subsequent fast launches
                let stored = StoredIdentity(certPem: certPem, keyPem: keyPem)
                if let data = try? JSONEncoder().encode(stored) {
                    try? data.write(to: identityFileURL, options: [.atomic])
                }
                return identity
            }
        }

        return nil
    }

    // MARK: - Server Passwords

    @discardableResult
    public static func saveServerPassword(bookmarkId: UUID, password: String) -> Bool {
        // Fast local persistence
        var dict = loadPasswordsMap()
        dict[bookmarkId.uuidString] = password
        savePasswordsMap(dict)

        // Asynchronous Keychain backup
        DispatchQueue.global(qos: .utility).async {
            guard let data = password.data(using: .utf8) else { return }
            _ = saveToKeychain(account: bookmarkId.uuidString, service: serviceServers, data: data)
        }
        return true
    }

    public static func loadServerPassword(bookmarkId: UUID) -> String? {
        let dict = loadPasswordsMap()
        if let pwd = dict[bookmarkId.uuidString] {
            return pwd
        }
        // Fallback to Keychain
        for service in [serviceServers, legacyServiceServers] {
            if let data = loadFromKeychain(account: bookmarkId.uuidString, service: service),
               let pwd = String(data: data, encoding: .utf8) {
                return pwd
            }
        }
        return nil
    }

    @discardableResult
    public static func deleteServerPassword(bookmarkId: UUID) -> Bool {
        var dict = loadPasswordsMap()
        dict.removeValue(forKey: bookmarkId.uuidString)
        savePasswordsMap(dict)

        DispatchQueue.global(qos: .utility).async {
            _ = deleteFromKeychain(account: bookmarkId.uuidString, service: serviceServers)
            _ = deleteFromKeychain(account: bookmarkId.uuidString, service: legacyServiceServers)
        }
        return true
    }

    private static func loadPasswordsMap() -> [String: String] {
        guard let data = try? Data(contentsOf: passwordsFileURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }

    private static func savePasswordsMap(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: passwordsFileURL, options: [.atomic])
        }
    }

    // MARK: - Generic Keychain Primitives

    @discardableResult
    private static func saveToKeychain(account: String, service: String, data: Data) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func loadFromKeychain(account: String, service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    @discardableResult
    private static func deleteFromKeychain(account: String, service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
