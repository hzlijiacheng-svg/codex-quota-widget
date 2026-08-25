import Foundation

public enum ProviderID: String, CaseIterable, Codable {
    case codex
    case glm

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .glm: return "GLM"
        }
    }
}

public enum QuotaWindowKind: String, Codable {
    case session
    case weekly

    public var shortLabel: String {
        switch self {
        case .session: return "5h"
        case .weekly: return "7d"
        }
    }
}

public enum ResetMode: String, Codable {
    case rollingRecovery
    case fixedCycle
}

public struct QuotaWindow: Equatable {
    public let kind: QuotaWindowKind
    public let usedPercent: Double
    public let resetAt: Date?
    public let durationSeconds: TimeInterval
    public let resetMode: ResetMode

    public init(
        kind: QuotaWindowKind,
        usedPercent: Double,
        resetAt: Date?,
        durationSeconds: TimeInterval,
        resetMode: ResetMode
    ) {
        self.kind = kind
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetAt = resetAt
        self.durationSeconds = durationSeconds
        self.resetMode = resetMode
    }

    public var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }
}

public struct TokenBreakdown: Equatable {
    public let input: Int64
    public let cachedInput: Int64
    public let output: Int64

    public init(input: Int64 = 0, cachedInput: Int64 = 0, output: Int64 = 0) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
    }

    public var total: Int64 { input + cachedInput + output }
}

public struct TokenPace: Equatable {
    public let todayTokens: Int64
    public let baselineTokens: Int64
    public let deltaTokens: Int64
    public let deltaPercent: Double
    public let sampleDays: Int
}

public struct QuotaPace: Equatable {
    public let elapsedPercent: Double
    public let usedPercent: Double
    public let deltaPercentagePoints: Double
}

public struct ProviderSnapshot: Equatable {
    public let provider: ProviderID
    public let planName: String?
    public let windows: [QuotaWindow]
    public let tokenBreakdown: TokenBreakdown?
    public let tokenPace: TokenPace?
    public let updatedAt: Date
    public let sourceDescription: String

    public init(
        provider: ProviderID,
        planName: String?,
        windows: [QuotaWindow],
        tokenBreakdown: TokenBreakdown? = nil,
        tokenPace: TokenPace? = nil,
        updatedAt: Date,
        sourceDescription: String
    ) {
        self.provider = provider
        self.planName = planName
        self.windows = windows
        self.tokenBreakdown = tokenBreakdown
        self.tokenPace = tokenPace
        self.updatedAt = updatedAt
        self.sourceDescription = sourceDescription
    }

    public var tightestWindow: QuotaWindow? {
        windows.min { $0.remainingPercent < $1.remainingPercent }
    }
}

public protocol QuotaProvider {
    var id: ProviderID { get }
    func fetch(now: Date) throws -> ProviderSnapshot
}
