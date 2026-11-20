import CodexBarCore
import Commander
import Foundation

struct HubAccountsOptions: CommanderParsable {
    @OptionGroup var common: CLICommonOptions

    @Option(name: .long("provider"), help: "Hub pool to read: codex | claude")
    var provider: String?

    @Option(name: .long("pending-request-id"), help: "Pending switch request id to resolve")
    var pendingRequestId: String?

    @Option(name: .long("pending-target-id-suffix"), help: "Pending switch target id suffix")
    var pendingTargetIdSuffix: String?

    @Option(name: .long("pending-target-email"), help: "Pending switch target masked email")
    var pendingTargetEmail: String?

    @Option(name: .long("pending-requested-at"), help: "Pending switch request time (ISO 8601)")
    var pendingRequestedAt: String?
}

struct HubSwitchOptions: CommanderParsable {
    @OptionGroup var common: CLICommonOptions

    @Option(name: .long("provider"), help: "Hub pool to switch: codex | claude")
    var provider: String?

    @Option(name: .long("id-suffix"), help: "Target account id suffix as the hub lists it")
    var idSuffix: String?

    @Option(name: .long("email"), help: "Target account masked email as the hub lists it")
    var email: String?

    @Flag(name: .long("confirm"), help: "Required: a hub switch moves every machine on the hub")
    var confirm: Bool = false
}

/// The two CLI providers that have an opencodex hub pool on this command.
enum HubCLIProvider: String, Sendable {
    case codex
    case claude

    init?(argument: String?) {
        guard let argument else { return nil }
        self.init(rawValue: argument.trimmingCharacters(in: .whitespaces).lowercased())
    }

    var hubProvider: OpenCodexHubProvider {
        // Provider-specific by design: the hub names its pools by upstream vendor, so the two hub CLI providers map
        // to opencodex's `openai` and `anthropic` pools.
        switch self {
        case .codex: .openai
        case .claude: .anthropic
        }
    }
}

/// Where a provider's hub pool is read from, as `config.json` says.
struct HubProviderConfiguration: Equatable, Sendable {
    let configured: Bool
    let executablePath: String?
    let snapshotPath: String?

    /// Codex: `openCodexHubEnabled`. Claude: only `claudeSwapEnabled` with `claudeSwapSource == "opencodex"`.
    static func resolve(provider: HubCLIProvider, config: CodexBarConfig) -> HubProviderConfiguration {
        // Provider-specific by design: Codex reads the hub keys, while Claude's hub list is driven by its claude-swap
        // adapter keys (the keys the fleet's config writer sets), so each provider resolves different fields.
        switch provider {
        case .codex:
            let entry = config.providerConfig(for: .codex)
            return HubProviderConfiguration(
                configured: entry?.openCodexHubEnabled == true,
                executablePath: entry?.sanitizedOpenCodexHubExecutablePath,
                snapshotPath: entry?.resolvedOpenCodexHubSnapshotPath ?? OpenCodexHubDefaults.snapshotPath)
        case .claude:
            let entry = config.providerConfig(for: .claude)
            return HubProviderConfiguration(
                configured: entry?.claudeSwapEnabled == true && entry?.claudeSwapSource == "opencodex",
                executablePath: entry?.sanitizedClaudeSwapExecutablePath,
                snapshotPath: entry?.resolvedOpenCodexHubSnapshotPath ?? OpenCodexHubDefaults.snapshotPath)
        }
    }
}

/// Injectable dependencies so tests never probe a real `ocx` or depend on the wall clock.
struct HubCommandEnvironment: Sendable {
    var roleCache: OpenCodexRuntimeRoleCache = .shared
    var now: @Sendable () -> Date = { Date() }
    var timeout: TimeInterval = OpenCodexHubReader.defaultTimeout
}

extension CodexBarCLI {
    /// The `error.code` of a hub failure: the `OpenCodexHubReaderError` case name, else `fallback`.
    static func hubErrorCode(_ error: Error, fallback: String = "readFailed") -> String {
        guard let error = error as? OpenCodexHubReaderError else { return fallback }
        switch error {
        case .hubAccountsUnavailable: return "hubAccountsUnavailable"
        case .noHubSource: return "noHubSource"
        case .snapshotUnreadable: return "snapshotUnreadable"
        case .snapshotNotCurrent: return "snapshotNotCurrent"
        case .accountNotFound: return "accountNotFound"
        case .switchNotAllowed: return "switchNotAllowed"
        case .switchFailed: return "switchFailed"
        case .mismatchedTarget: return "mismatchedTarget"
        }
    }

    static func hubErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func parseHubDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
