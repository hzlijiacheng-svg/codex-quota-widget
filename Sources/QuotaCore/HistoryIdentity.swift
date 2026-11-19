import Foundation
import CryptoKit

enum HistoryIdentity {
    static func hash(_ parts: [String]) -> String {
        let data = Data(parts.joined(separator: "\u{1f}").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
