import Foundation

/// Serializes Keychain access away from the main actor and shares one identity
/// across server windows. A failed load never silently rotates the user's key.
actor CredentialRepository {
    static let shared = CredentialRepository()
    private var identity: ClientIdentity?
    func loadIdentity() throws -> ClientIdentity {
        if let identity { return identity }
        let value: ClientIdentity
        if let saved = try KeychainHelper.loadClientIdentity() { value = saved }
        else {
            value = generateClientIdentity(commonName: "Swimble User")
            guard KeychainHelper.saveClientIdentity(value) else { throw CocoaError(.fileWriteNoPermission) }
        }
        KeychainHelper.migratePasswords()
        identity = value
        return value
    }
    func replaceIdentity(_ value: ClientIdentity) throws {
        guard KeychainHelper.saveClientIdentity(value) else { throw CocoaError(.fileWriteNoPermission) }
        identity = value
    }
}
