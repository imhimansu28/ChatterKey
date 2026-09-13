import Foundation
import LocalAuthentication
import Security

nonisolated enum KeychainStore {
    // v0.2 uses its own credential namespace so keys created by older local
    // builds cannot repeatedly trigger a macOS ACL password prompt.
    private static let service = "app.chatterkey.macos.credentials.v2"
    private static func query(account: String, service: String = service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let search = query(account: account)
        let update = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(search as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var insert = search
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.status(addStatus)
        }
    }

    static func read(account: String) -> String {
        read(account: account, service: service) ?? ""
    }

    static func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private static func read(account: String, service: String) -> String? {
        var search = query(account: account, service: service)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne

        let context = LAContext()
        context.interactionNotAllowed = true
        search[kSecUseAuthenticationContext as String] = context
        // Compatibility guard for legacy ACL-backed items. LAContext alone does
        // not suppress every Security.framework access prompt on macOS.
        search["u_AuthUI"] = "u_AuthUIF"

        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }
}

nonisolated enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? "Keychain operation failed (\(status))."
        }
    }
}
