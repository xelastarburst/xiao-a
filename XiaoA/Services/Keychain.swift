import Foundation
import Security

/// API keys, never in the app's code:
/// 1. this iPhone's Keychain (entered in Alex mode), else
/// 2. keys built into this build from `XiaoA/BundledKeys.json`, a file that exists only on
///    Alex's Mac (git ignores it), so Mom's phone works without anyone typing keys on it.
enum APIKeys {
    enum Kind: String, CaseIterable { case openAI = "openai", anthropic = "anthropic" }

    private static let service = "com.alexqi.xiaoa.apikeys"

    static func get(_ kind: Kind) -> String? {
        keychainValue(kind) ?? bundled[kind]
    }

    /// The key typed into Alex mode on this iPhone, if any.
    static func keychainValue(_ kind: Kind) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    static func set(_ value: String, for kind: Kind) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func masked(_ kind: Kind) -> String {
        if let key = keychainValue(kind) { return "Saved on this iPhone ···" + String(key.suffix(4)) }
        if let key = bundled[kind] { return "Built into the app ···" + String(key.suffix(4)) }
        return "Not set"
    }

    /// Keys from BundledKeys.json in the app, read once. Empty if the file is missing or blank.
    private static let bundled: [Kind: String] = {
        guard let url = Bundle.main.url(forResource: "BundledKeys", withExtension: "json"),
              var text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        // TextEdit may have turned the straight quotes into curly ones.
        text = text.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            print("[XA] BundledKeys.json isn't valid JSON; ignoring it")
            return [:]
        }
        var keys: [Kind: String] = [:]
        for kind in Kind.allCases {
            let value = (object[kind.rawValue] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 20 && !value.contains(" ") { keys[kind] = value }
        }
        if !keys.isEmpty { print("[XA] using built-in keys: \(keys.keys.map(\.rawValue).sorted().joined(separator: ", "))") }
        return keys
    }()
}
