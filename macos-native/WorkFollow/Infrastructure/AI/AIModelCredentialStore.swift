import Foundation
import Security

@MainActor
protocol AIModelCredentials {
    func read(_ id: UUID) throws -> String?
    func write(_ value: String?, for id: UUID) throws
}

@MainActor
struct KeychainAIModelCredentials: AIModelCredentials {
    private let service = "com.workfollow.native.ai-models"
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
    func read(_ id: UUID) throws -> String? {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AIModelConfigurationError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }
    func write(_ value: String?, for id: UUID) throws {
        let query = query(id)
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard [errSecSuccess, errSecItemNotFound].contains(status) else { throw AIModelConfigurationError.keychain(status) }
            return
        }
        let update = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(update) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AIModelConfigurationError.keychain(status) }
    }
}
