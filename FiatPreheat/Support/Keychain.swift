import Foundation
import Security

/// Stores the Fiat account in the Keychain. Readable after first unlock so scheduled
/// preheats can run from the background while the phone is locked.
enum AccountStore {
    private static let service = "dk.koster.FiatPreheat.account"
    private static let key = "uconnect"

    static func load() -> UconnectAccount? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let fields = try? JSONDecoder().decode([String: String].self, from: data),
              let email = fields["email"], let password = fields["password"], let pin = fields["pin"] else {
            return nil
        }
        return UconnectAccount(email: email, password: password, pin: pin)
    }

    static func save(_ account: UconnectAccount) {
        delete()
        let data = try! JSONEncoder().encode(["email": account.email, "password": account.password, "pin": account.pin])
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
