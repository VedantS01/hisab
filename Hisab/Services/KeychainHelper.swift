import Foundation
import Security
import HisabCore

/// Per-source statement passwords, kept in the iOS keychain.
enum KeychainHelper {
    private static func query(for source: Source) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.vedants.hisab.statement-password",
         kSecAttrAccount as String: source.rawValue]
    }

    static func password(for source: Source) -> String? {
        var query = query(for: source)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Every remembered statement password, for pre-detection unlock
    /// attempts (the source isn't known until the file parses).
    static func allPasswords() -> [String] {
        let query: [String: Any] =
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: "com.vedants.hisab.statement-password",
             kSecReturnData as String: true,
             kSecMatchLimit as String: kSecMatchLimitAll]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let datas = items as? [Data] else { return [] }
        var seen = Set<String>()
        return datas.compactMap { String(data: $0, encoding: .utf8) }
            .filter { seen.insert($0).inserted }
    }

    static func setPassword(_ password: String, for source: Source) {
        let base = query(for: source)
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
