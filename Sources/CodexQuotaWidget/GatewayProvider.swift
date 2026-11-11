import Foundation
import Security
import CFNetwork
#if SWIFT_PACKAGE
import QuotaCore
#endif

private struct GatewayConfig: Decodable {
    let endpoint: String
    let gatewayId: String
    let quotaRuleId: String
    let subjectId: String

    func validate() throws {
        guard endpoint == "apig.cn-hangzhou.aliyuncs.com",
              gatewayId.range(of: #"^gw-[a-z0-9]+$"#, options: .regularExpression) != nil,
              quotaRuleId.range(of: #"^qr-[a-z0-9]+$"#, options: .regularExpression) != nil,
              subjectId.range(of: #"^cs-[a-z0-9]+$"#, options: .regularExpression) != nil
        else { throw GatewayProviderError.message("网关配置中的地址或资源编号无效") }
    }
}

private struct GatewayCredentials: Decodable {
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String?
}

private enum GatewayProviderError: LocalizedError {
    case message(String)
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .http(let code): return "网关额度查询失败（HTTP \(code)）"
        case .invalidResponse: return "网关返回了无法识别的额度数据"
        }
    }
}

private final class NoGatewayRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class GatewayProvider: QuotaProvider {
    let id = ProviderID.zcode
    private static let keychainService = "local.codex-quota-widget.apig"

    func fetch(now: Date) throws -> ProviderSnapshot {
        let directory = try Self.configDirectory()
        let config: GatewayConfig = try Self.readJSON(directory.appendingPathComponent("gateway-config.json"))
        try config.validate()
        let credentials = try Self.credentials(in: directory)
        let rulePath = "/v1/gateways/\(config.gatewayId)/quota-rules/\(config.quotaRuleId)"
        let rule = try Self.call(config: config, credentials: credentials,
                                 action: "GetGatewayQuotaRule", path: rulePath)
        let usage = try Self.call(config: config, credentials: credentials,
                                  action: "GetGatewayQuotaRuleSubjectUsage",
                                  path: "\(rulePath)/subjects/\(config.subjectId)/usage")
        let quota = try GatewayQuotaParser.parse(rule: rule, usage: usage)
        return ProviderSnapshot(provider: .zcode, planName: nil, windows: [],
                                gatewayQuota: quota, updatedAt: now,
                                sourceDescription: "企业网关所配置的消费者与规则")
    }

    private static func configDirectory() throws -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["CODEX_QUOTA_APIG_DIR"], !override.isEmpty {
            candidates = [URL(fileURLWithPath: override, isDirectory: true)]
        } else {
            candidates = [
                home.appendingPathComponent(".config/codex-quota-widget/apig", isDirectory: true),
                home.appendingPathComponent("Documents/code/codex-quota-widget/.local-apig", isDirectory: true)
            ]
        }
        guard let directory = candidates.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("gateway-config.json").path)
        }) else {
            throw GatewayProviderError.message("尚未配置企业网关额度查询")
        }
        return directory
    }

    private static func readJSON<T: Decodable>(_ url: URL) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url)) }
        catch { throw GatewayProviderError.message("企业网关本地配置无法读取，请检查配置文件") }
    }

    private static func credentials(in directory: URL) throws -> GatewayCredentials {
        let file = directory.appendingPathComponent("credentials.local.json")
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            guard let mode = (try? fm.attributesOfItem(atPath: file.path)[.posixPermissions]) as? NSNumber,
                  mode.intValue & 0o077 == 0 else {
                throw GatewayProviderError.message("网关凭据文件权限须设为 600")
            }
            let credentials: GatewayCredentials = try readJSON(file)
            guard !credentials.accessKeyId.isEmpty, !credentials.accessKeySecret.isEmpty else {
                throw GatewayProviderError.message("企业网关凭据不完整")
            }
            return credentials
        }
        func keychain(_ account: String) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var value: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
                  let data = value as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard let id = keychain("access-key-id"), !id.isEmpty,
              let secret = keychain("access-key-secret"), !secret.isEmpty else {
            throw GatewayProviderError.message("尚未配置企业网关只读凭据")
        }
        return GatewayCredentials(accessKeyId: id, accessKeySecret: secret,
                                  securityToken: keychain("security-token"))
    }

    private static func call(config: GatewayConfig, credentials: GatewayCredentials,
                             action: String, path: String) throws -> [String: Any] {
        var lastError: Error = GatewayProviderError.invalidResponse
        for direct in [false, true] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let request = try APIGRequestSigner.request(
                endpoint: config.endpoint, accessKeyID: credentials.accessKeyId,
                accessKeySecret: credentials.accessKeySecret, securityToken: credentials.securityToken,
                action: action, path: path, date: formatter.string(from: Date()),
                nonce: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            )
            do {
                let (data, response) = try perform(request, direct: direct)
                guard (200..<300).contains(response.statusCode) else {
                    if !direct && [407, 502, 503, 504].contains(response.statusCode) {
                        lastError = GatewayProviderError.http(response.statusCode)
                        continue
                    }
                    throw GatewayProviderError.http(response.statusCode)
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (object["success"] as? Bool) != false,
                      let data = object["data"] as? [String: Any] else {
                    throw GatewayProviderError.invalidResponse
                }
                return data
            } catch let error as GatewayProviderError {
                throw error
            } catch {
                lastError = error
                if direct { break }
            }
        }
        _ = lastError
        throw GatewayProviderError.message("企业网关连接失败，已尝试系统代理和直连")
    }

    private static func perform(_ request: URLRequest, direct: Bool) throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        if direct {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 0,
                kCFNetworkProxiesHTTPSEnable as String: 0,
                kCFNetworkProxiesSOCKSEnable as String: 0,
                kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
                kCFNetworkProxiesProxyAutoDiscoveryEnable as String: 0
            ]
        }
        let session = URLSession(configuration: configuration, delegate: NoGatewayRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, HTTPURLResponse), Error>?
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error { result = .failure(error); return }
            guard let data, let response = response as? HTTPURLResponse else {
                result = .failure(GatewayProviderError.invalidResponse); return
            }
            result = .success((data, response))
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 17) == .success, let result else {
            task.cancel()
            throw URLError(.timedOut)
        }
        return try result.get()
    }
}
