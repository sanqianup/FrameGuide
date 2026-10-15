import Foundation
import Security

enum RemoteKind: String, Codable, CaseIterable, Identifiable {
    case vision, editing
    var id: String { rawValue }
    var title: String { self == .vision ? "看图建议 / 调色参数" : "生成式图像编辑" }
}
enum KeyHeader: String, Codable, CaseIterable {
    case bearer, apiKey, xAPIKey
    var header: String {
        switch self { case .bearer: return "Authorization"; case .apiKey: return "api-key"; case .xAPIKey: return "x-api-key" }
    }
}
struct RemoteConfiguration: Codable, Equatable {
    var endpoint = ""
    var model = ""
    var timeout = 30.0
    var enabled = false
    var capabilityConfirmed = false
    var auth = KeyHeader.bearer
    var mimoOptions = false
    var disableThinking = true
    static var mimoOfficial: Self {
        var c = Self()
        c.endpoint = "https://api.xiaomimimo.com/v1/chat/completions"
        c.model = "mimo-v2.6-pro"
        c.auth = .apiKey
        c.mimoOptions = true
        return c // disabled, no key, no upload consent
    }
    func validate() throws -> URL {
        guard enabled, capabilityConfirmed, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (5...90).contains(timeout) else { throw RemoteError.notConfigured }
        return try CloudContract.endpoint(endpoint)
    }
    static func load(_ kind: RemoteKind) -> Self {
        guard let data = UserDefaults.standard.data(forKey: "remote.\(kind.rawValue)"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return kind == .vision ? .mimoOfficial : Self() }
        return value
    }
    func save(_ kind: RemoteKind) throws {
        if enabled { _ = try validate() }
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "remote.\(kind.rawValue)")
    }
}
enum RemoteError: LocalizedError {
    case notConfigured, keyMissing, keychain, http(Int), tooLarge, format, redirects, network, unsupportedTest
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "服务未配置或能力未确认；兼容聊天接口不等于支持看图或图像编辑"
        case .keyMissing: return "请在本机设置中保存此服务的密钥"
        case .keychain: return "无法访问本机 Keychain，密钥未保存"
        case .http(let code): return "服务返回 HTTP \(code)。请核对端点、模型、权限和服务能力；未生成结果"
        case .tooLarge: return "服务响应超过安全大小，已停止接收"
        case .format: return "服务返回格式或调色参数不符合约定；未应用结果"
        case .redirects: return "端点尝试重定向，已阻止以保护密钥和照片"
        case .network: return "请求失败、超时或已取消；没有自动重试，请在服务端核对是否已计费"
        case .unsupportedTest: return "此编辑接口不能用无照片文本请求验证；请先核对服务文档"
        }
    }
}

enum SecretStore {
    private static let service = "FrameGuide.remote.credentials"
    private static func account(_ kind: RemoteKind, endpoint: URL) -> String {
        "\(kind.rawValue)|https://\(endpoint.host?.lowercased() ?? ""):\(endpoint.port ?? 443)"
    }
    static func hasKey(_ kind: RemoteKind, endpoint: URL) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account(kind, endpoint: endpoint),
            kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    static func read(_ kind: RemoteKind, endpoint: URL) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account(kind, endpoint: endpoint),
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status == errSecSuccess, let bytes = value as? Data,
              let key = String(data: bytes, encoding: .utf8), !key.isEmpty else { throw RemoteError.keyMissing }
        return key
    }
    static func save(_ key: String, for kind: RemoteKind, endpoint: URL) throws {
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw RemoteError.keyMissing }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account(kind, endpoint: endpoint)]
        let changes: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw RemoteError.keychain }
        } else if status != errSecSuccess { throw RemoteError.keychain }
    }
}
