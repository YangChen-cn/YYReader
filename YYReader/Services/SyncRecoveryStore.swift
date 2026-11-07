import Foundation
#if os(iOS)
import Security
#endif

struct SyncRecoveryConfiguration: Codable, Equatable, Sendable {
    let bookmark: Data
    let enabled: Bool
    let displayPath: String?
}

protocol SyncRecoveryPersisting: Actor {
    func load() throws -> SyncRecoveryConfiguration?
    func save(_ configuration: SyncRecoveryConfiguration) throws
    func clear() throws
}

#if os(iOS)
actor SyncRecoveryStore: SyncRecoveryPersisting {
    private let service: String
    init(service: String = "com.yyreader.ios.folderSync.recovery") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "folder", kSecAttrSynchronizable as String: false]
    }

    func load() throws -> SyncRecoveryConfiguration? {
        try Task.checkCancellation()
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONDecoder().decode(SyncRecoveryConfiguration.self, from: data)
    }

    func save(_ configuration: SyncRecoveryConfiguration) throws {
        try Task.checkCancellation()
        let values: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(configuration),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil))
        } else { try check(status) }
    }

    func clear() throws {
        try Task.checkCancellation()
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
#endif
