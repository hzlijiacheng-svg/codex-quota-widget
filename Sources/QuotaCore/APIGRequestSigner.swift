import Foundation
import CryptoKit

enum APIGRequestError: LocalizedError {
    case invalidEndpoint
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "不支持的网关管理接口地址"
        case .invalidPath: return "网关额度查询路径无效"
        }
    }
}

enum APIGRequestSigner {
    static func request(endpoint: String, accessKeyID: String, accessKeySecret: String,
                        securityToken: String?, action: String, path: String,
                        query: [String: String] = [:], date: String, nonce: String) throws -> URLRequest {
        guard endpoint == "apig.cn-hangzhou.aliyuncs.com" else { throw APIGRequestError.invalidEndpoint }
        let allowedPath = #"^/v1/gateways/gw-[a-z0-9]+/quota-rules/qr-[a-z0-9]+(/subjects/cs-[a-z0-9]+/usage)?$"#
        guard path.range(of: allowedPath, options: .regularExpression) != nil,
              (action == "GetGatewayQuotaRule" && !path.hasSuffix("/usage")) ||
                (action == "GetGatewayQuotaRuleSubjectUsage" && path.hasSuffix("/usage"))
        else { throw APIGRequestError.invalidPath }

        let canonicalQuery = query.keys.sorted().map { "\(encode($0))=\(encode(query[$0]!))" }
            .joined(separator: "&")
        let payloadHash = sha256(Data())
        var headers = [
            "host": endpoint, "x-acs-action": action, "x-acs-version": "2024-03-27",
            "x-acs-date": date, "x-acs-signature-nonce": nonce,
            "x-acs-content-sha256": payloadHash
        ]
        if let securityToken, !securityToken.isEmpty { headers["x-acs-security-token"] = securityToken }
        let signedKeys = headers.keys.sorted()
        let canonicalHeaders = signedKeys.map { "\($0):\(headers[$0]!)\n" }.joined()
        let signedHeaders = signedKeys.joined(separator: ";")
        let canonical = ["GET", path, canonicalQuery, canonicalHeaders, signedHeaders, payloadHash]
            .joined(separator: "\n")
        let toSign = "ACS3-HMAC-SHA256\n" + sha256(Data(canonical.utf8))
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(toSign.utf8), using: SymmetricKey(data: Data(accessKeySecret.utf8))
        ).map { String(format: "%02x", $0) }.joined()
        headers["authorization"] = "ACS3-HMAC-SHA256 Credential=\(accessKeyID),SignedHeaders=\(signedHeaders),Signature=\(signature)"
        let suffix = canonicalQuery.isEmpty ? "" : "?\(canonicalQuery)"
        guard let url = URL(string: "https://\(endpoint)\(path)\(suffix)")
        else { throw APIGRequestError.invalidPath }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return request
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
