import Foundation
import Security
#if SWIFT_PACKAGE
import QuotaCore
#endif

struct GLMCredential {
    let token: String
    let origin: URL
}

enum GLMCredentialResolver {
    static func resolve(fileManager: FileManager = .default) -> GLMCredential? {
        if let token = GLMKeychain.load(), !token.isEmpty {
            return GLMCredential(token: token, origin: URL(string: "https://open.bigmodel.cn")!)
        }
        let environment = ProcessInfo.processInfo.environment
        if let token = firstToken(in: environment) {
            return GLMCredential(token: token, origin: origin(from: environment["ANTHROPIC_BASE_URL"]))
        }
        let settings = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = object["env"] as? [String: Any] else { return nil }
        let values = env.compactMapValues { $0 as? String }
        guard let token = firstToken(in: values) else { return nil }
        return GLMCredential(token: token, origin: origin(from: values["ANTHROPIC_BASE_URL"]))
    }

    private static func firstToken(in values: [String: String]) -> String? {
        ["GLM_CODING_API_KEY", "ZAI_API_KEY", "ANTHROPIC_AUTH_TOKEN"]
            .compactMap { values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func origin(from baseURL: String?) -> URL {
        guard let baseURL, let url = URL(string: baseURL),
              let scheme = url.scheme, let host = url.host else {
            return URL(string: "https://open.bigmodel.cn")!
        }
        return URL(string: "\(scheme)://\(host)")!
    }
}

enum GLMKeychain {
    private static let service = "local.codex.quota-widget.glm"
    private static let account = "coding-plan-api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WidgetError.requestFailed("无法保存 GLM Key（Keychain \(status)）")
        }
    }
}

final class GLMProvider: QuotaProvider {
    let id = ProviderID.glm

    func fetch(now: Date) throws -> ProviderSnapshot {
        guard let credential = GLMCredentialResolver.resolve() else {
            throw WidgetError.glmCredentialMissing
        }
        let url = credential.origin.appendingPathComponent("api/monitor/usage/quota/limit")
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(credential.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh", forHTTPHeaderField: "Accept-Language")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>!
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error { result = .failure(error); return }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), let data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                result = .failure(WidgetError.network("GLM 额度查询失败（HTTP \(code)）"))
                return
            }
            result = .success(data)
        }.resume()
        guard semaphore.wait(timeout: .now() + 13) == .success else {
            throw WidgetError.network("GLM 额度查询超时")
        }
        let data = try result.get()
        return try GLMQuotaParser.parse(data: data, now: now)
    }
}
