import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

final class KeychainStore {
    private enum SecretSlot: String {
        case username
        case password
        case userID
    }

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier.map { "\($0).api-keys" } ?? "BooruBar.api-keys") {
        self.service = service
    }

    // Keep the API-key account name unchanged for backwards compatibility with
    // keys saved by older BooruBar/iBooruBar builds.
    func apiKey(for siteID: UUID) -> String? {
        read(account: siteID.uuidString)
    }

    func saveAPIKey(_ apiKey: String, for siteID: UUID) throws {
        try save(apiKey, account: siteID.uuidString)
    }

    func deleteAPIKey(for siteID: UUID) {
        delete(account: siteID.uuidString)
    }

    func username(for siteID: UUID) -> String? {
        read(account: account(for: siteID, slot: .username))
    }

    func password(for siteID: UUID) -> String? {
        read(account: account(for: siteID, slot: .password))
    }

    func userID(for siteID: UUID) -> String? {
        read(account: account(for: siteID, slot: .userID))
    }

    func saveUsername(_ value: String, for siteID: UUID) throws {
        try save(value, account: account(for: siteID, slot: .username))
    }

    func savePassword(_ value: String, for siteID: UUID) throws {
        try save(value, account: account(for: siteID, slot: .password))
    }

    func saveUserID(_ value: String, for siteID: UUID) throws {
        try save(value, account: account(for: siteID, slot: .userID))
    }

    func deleteUsername(for siteID: UUID) {
        delete(account: account(for: siteID, slot: .username))
    }

    func deletePassword(for siteID: UUID) {
        delete(account: account(for: siteID, slot: .password))
    }

    func deleteUserID(for siteID: UUID) {
        delete(account: account(for: siteID, slot: .userID))
    }

    func deleteAuthentication(for siteID: UUID) {
        deleteAPIKey(for: siteID)
        deleteUsername(for: siteID)
        deletePassword(for: siteID)
        deleteUserID(for: siteID)
    }

    private func account(for siteID: UUID, slot: SecretSlot) -> String {
        "\(siteID.uuidString).\(slot.rawValue)"
    }

    private func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func save(_ value: String, account: String) throws {
        guard !value.isEmpty else {
            delete(account: account)
            return
        }

        let encodedValue = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: encodedValue
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = encodedValue

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unhandledStatus(addStatus)
            }
            return
        }

        throw KeychainStoreError.unhandledStatus(updateStatus)
    }

    private func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
