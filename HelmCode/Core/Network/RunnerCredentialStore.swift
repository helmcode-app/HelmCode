//
//  RunnerCredentialStore.swift
//  HelmCode
//
//  Per-runner device token in the Keychain. Not UserDefaults.
//

import Foundation
import Security

enum RunnerCredentialStore {
    private static let service = "app.helmcode.runner"

    static func save(runnerId: String, token: String) {
        let account = runnerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !secret.isEmpty else { return }
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func token(runnerId: String) -> String? {
        let account = runnerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { return nil }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func delete(runnerId: String) {
        let account = runnerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { return }
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum RunnerAuthCopy {
    static let unauthorized =
        "This device is not authorized. Add it from another device, or on the runner run node dist/entrypoint.js setup:recover."

    static func message(for error: Error) -> String {
        if case HelmNetworkError.http(401, _) = error {
            return unauthorized
        }
        let text = error.localizedDescription
        if text.contains("401") || text.localizedCaseInsensitiveContains("unauthorized") {
            return unauthorized
        }
        return text
    }
}
