import CodexBarCore
import Foundation

// JSON contract of `codexbar hub accounts` / `hub switch` (schemaVersion 1). Optional fields encode as an
// explicit `null`, never omitted, so a reader can tell "not known" from "older CLI".

struct HubErrorPayload: Encodable, Equatable {
    let code: String
    let message: String
}

struct HubQuotaSummaryPayload: Encodable, Equatable {
    let label: String
    let usedPercent: Double
}

struct HubAccountPayload: Encodable {
    let idSuffix: String?
    let label: String?
    let email: String
    let active: Bool
    let paused: Bool
    let needsReauth: Bool
    let health: String?
    let quotaUnavailable: Bool
    let nearLimit: Bool
    let canSwitch: Bool
    let quotaSummary: [HubQuotaSummaryPayload]
    let usage: UsageSnapshot

    private enum CodingKeys: String, CodingKey {
        case idSuffix, label, email, active, paused, needsReauth, health, quotaUnavailable
        case nearLimit, canSwitch, quotaSummary, usage
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.idSuffix, forKey: .idSuffix)
        try container.encode(self.label, forKey: .label)
        try container.encode(self.email, forKey: .email)
        try container.encode(self.active, forKey: .active)
        try container.encode(self.paused, forKey: .paused)
        try container.encode(self.needsReauth, forKey: .needsReauth)
        try container.encode(self.health, forKey: .health)
        try container.encode(self.quotaUnavailable, forKey: .quotaUnavailable)
        try container.encode(self.nearLimit, forKey: .nearLimit)
        try container.encode(self.canSwitch, forKey: .canSwitch)
        try container.encode(self.quotaSummary, forKey: .quotaSummary)
        try container.encode(self.usage, forKey: .usage)
    }
}

struct HubRequestResultPayload: Encodable {
    let requestId: String
    let provider: String?
    let result: String
    let code: String?
    let reason: String?
    let at: Date?

    private enum CodingKeys: String, CodingKey { case requestId, provider, result, code, reason, at }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.requestId, forKey: .requestId)
        try container.encode(self.provider, forKey: .provider)
        try container.encode(self.result, forKey: .result)
        try container.encode(self.code, forKey: .code)
        try container.encode(self.reason, forKey: .reason)
        try container.encode(self.at, forKey: .at)
    }
}

struct HubPendingPayload: Encodable, Equatable {
    let requestId: String
    let resolution: String
    let code: String?
    let reason: String?

    private enum CodingKeys: String, CodingKey { case requestId, resolution, code, reason }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.requestId, forKey: .requestId)
        try container.encode(self.resolution, forKey: .resolution)
        try container.encode(self.code, forKey: .code)
        try container.encode(self.reason, forKey: .reason)
    }
}

struct HubAccountsPayload: Encodable {
    var schemaVersion = 1
    let provider: String
    var configured: Bool
    var origin: String?
    var hub: String?
    var updatedAt: Date?
    var stale: Bool?
    var switchable: Bool?
    var switchReason: String?
    var activeIdSuffix: String?
    var accounts: [HubAccountPayload] = []
    var lastRequests: [HubRequestResultPayload] = []
    var pending: HubPendingPayload?
    var error: HubErrorPayload?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, provider, configured, origin, hub, updatedAt, stale, switchable, switchReason
        case activeIdSuffix, accounts, lastRequests, pending, error
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.schemaVersion, forKey: .schemaVersion)
        try container.encode(self.provider, forKey: .provider)
        try container.encode(self.configured, forKey: .configured)
        try container.encode(self.origin, forKey: .origin)
        try container.encode(self.hub, forKey: .hub)
        try container.encode(self.updatedAt, forKey: .updatedAt)
        try container.encode(self.stale, forKey: .stale)
        try container.encode(self.switchable, forKey: .switchable)
        try container.encode(self.switchReason, forKey: .switchReason)
        try container.encode(self.activeIdSuffix, forKey: .activeIdSuffix)
        try container.encode(self.accounts, forKey: .accounts)
        try container.encode(self.lastRequests, forKey: .lastRequests)
        try container.encode(self.pending, forKey: .pending)
        try container.encode(self.error, forKey: .error)
    }
}

struct HubSwitchRequestPayload: Encodable, Equatable {
    let requestId: String
    let targetIdSuffix: String
    let targetEmail: String
    let requestedAt: Date
}

struct HubSwitchPayload: Encodable {
    var schemaVersion = 1
    let provider: String
    var outcome: String?
    var request: HubSwitchRequestPayload?
    var error: HubErrorPayload?

    private enum CodingKeys: String, CodingKey { case schemaVersion, provider, outcome, request, error }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.schemaVersion, forKey: .schemaVersion)
        try container.encode(self.provider, forKey: .provider)
        try container.encode(self.outcome, forKey: .outcome)
        try container.encode(self.request, forKey: .request)
        try container.encode(self.error, forKey: .error)
    }
}
