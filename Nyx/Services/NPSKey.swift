import Foundation
import Security

/// An NPS key the person registered themselves (free at nps.gov), used instead of the key every
/// install shares, so a heavy user or a reviewer is never held up by the shared hourly quota. It is
/// a credential, so it lives in the Keychain on this device only (never synced, never logged), and
/// it is readable after the first unlock so a background refresh can use it.
nonisolated struct NPSKeyStore: Sendable {
    let service: String
    init(service: String = "com.harrypakhale.nyx.nps-key") { self.service=service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "nps"]
    }
    var key: String? {
        var item: CFTypeRef?
        var search=query
        search[kSecReturnData as String]=true
        search[kSecMatchLimit as String]=kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data=item as? Data,
              let key=String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }
    /// Saves a trimmed key; an empty one removes it. False when the Keychain refused.
    @discardableResult func save(_ raw: String) -> Bool {
        let key=Self.clean(raw)
        guard !key.isEmpty else { return remove() }
        let data=Data(key.utf8)
        let update=SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add=query
        add[kSecValueData as String]=data
        add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    @discardableResult func remove() -> Bool {
        let status=SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    /// NPS keys are 40 letters and digits; spaces and line breaks from a paste are dropped.
    static func clean(_ raw: String) -> String { raw.filter { $0.isLetter || $0.isNumber } }
    static func plausible(_ raw: String) -> Bool { (20...64).contains(clean(raw).count) }
}
