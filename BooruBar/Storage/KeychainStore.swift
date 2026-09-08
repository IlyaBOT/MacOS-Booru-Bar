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
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier.map { "\($0).api-keys" } ?? "BooruBar.api-keys") {
        self.service = service
    }

    func apiKey(for siteID: UUID) -> String? {
        var query = baseQuery(for: siteID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ apiKey: String, for siteID: UUID) throws {
        guard !apiKey.isEmpty else {
            deleteAPIKey(for: siteID)
            return
        }

        let encodedKey = Data(apiKey.utf8)
        let query = baseQuery(for: siteID)
        let attributes: [String: Any] = [
            kSecValueData as String: encodedKey
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = encodedKey

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unhandledStatus(addStatus)
            }
            return
        }

        throw KeychainStoreError.unhandledStatus(updateStatus)
    }

    func deleteAPIKey(for siteID: UUID) {
        let query = baseQuery(for: siteID)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(for siteID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: siteID.uuidString
        ]
    }
}
