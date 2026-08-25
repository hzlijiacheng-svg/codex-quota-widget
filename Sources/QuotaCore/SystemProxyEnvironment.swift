import Foundation

enum SystemProxyEnvironment {
    private static let proxyKeys = [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "all_proxy"
    ]

    static func variables(from settings: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        addProxy(scheme: "http", enabledKey: "HTTPEnable", hostKey: "HTTPProxy",
                 portKey: "HTTPPort", upperKey: "HTTP_PROXY", settings: settings, result: &result)
        addProxy(scheme: "http", enabledKey: "HTTPSEnable", hostKey: "HTTPSProxy",
                 portKey: "HTTPSPort", upperKey: "HTTPS_PROXY", settings: settings, result: &result)
        addProxy(scheme: "socks5", enabledKey: "SOCKSEnable", hostKey: "SOCKSProxy",
                 portKey: "SOCKSPort", upperKey: "ALL_PROXY", settings: settings, result: &result)

        if let exceptions = settings["ExceptionsList"] as? [String], !exceptions.isEmpty {
            let value = exceptions.joined(separator: ",")
            result["NO_PROXY"] = value
            result["no_proxy"] = value
        }
        return result
    }

    static func applying(_ variables: [String: String],
                         to base: [String: String]) -> [String: String] {
        var environment = removingProxyVariables(from: base)
        variables.forEach { environment[$0.key] = $0.value }
        return environment
    }

    static func candidates(base: [String: String], systemSettings: [String: Any])
        -> [[String: String]] {
        var result: [[String: String]] = []
        if proxyKeys.contains(where: { !(base[$0] ?? "").isEmpty }) {
            result.append(base)
        }

        let systemVariables = variables(from: systemSettings)
        if !systemVariables.isEmpty {
            let systemEnvironment = applying(systemVariables, to: base)
            if !result.contains(systemEnvironment) { result.append(systemEnvironment) }
        }

        let direct = removingProxyVariables(from: base)
        if !result.contains(direct) { result.append(direct) }
        return result
    }

    static func removingProxyVariables(from base: [String: String]) -> [String: String] {
        var environment = base
        for key in proxyKeys + ["NO_PROXY", "no_proxy"] {
            environment.removeValue(forKey: key)
        }
        return environment
    }

    private static func addProxy(scheme: String, enabledKey: String, hostKey: String,
                                 portKey: String, upperKey: String,
                                 settings: [String: Any], result: inout [String: String]) {
        guard (settings[enabledKey] as? NSNumber)?.boolValue == true,
              let host = settings[hostKey] as? String, !host.isEmpty,
              let port = settings[portKey] as? NSNumber else { return }
        let value = "\(scheme)://\(host):\(port.intValue)"
        result[upperKey] = value
        result[upperKey.lowercased()] = value
    }
}
