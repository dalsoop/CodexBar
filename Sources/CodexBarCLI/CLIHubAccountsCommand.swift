import CodexBarCore
import Commander
import Foundation

extension CodexBarCLI {
    static func hubCommandDescriptor() -> CommandDescriptor {
        CommandDescriptor(
            name: "hub",
            abstract: "List or switch the opencodex hub's accounts (codex, claude)",
            discussion: nil,
            signature: CommandSignature(),
            subcommands: [
                CommandDescriptor(
                    name: "accounts",
                    abstract: "Print a provider's hub account pool",
                    discussion: nil,
                    signature: CommandSignature.describe(HubAccountsOptions()).flattened()),
                CommandDescriptor(
                    name: "switch",
                    abstract: "Switch the hub to an account (requires --confirm)",
                    discussion: nil,
                    signature: CommandSignature.describe(HubSwitchOptions()).flattened()),
            ],
            defaultSubcommandName: "accounts")
    }

    static func runHub(path: [String], values: ParsedValues) async {
        let output = CLIOutputPreferences.from(values: values)
        let exitCode: ExitCode
        do {
            switch path {
            case ["hub", "accounts"]:
                let request = try Self.hubAccountsRequest(from: values)
                let config = Self.loadConfig(output: output)
                let result = await Self.hubAccounts(
                    provider: request.provider, pending: request.pending, config: config)
                Self.printHub(result.payload, text: Self.hubAccountsText(result.payload), output: output)
                exitCode = result.exitCode
            case ["hub", "switch"]:
                let request = try Self.hubSwitchRequest(from: values)
                let config = Self.loadConfig(output: output)
                let result = await Self.hubSwitch(request, config: config)
                Self.printHub(result.payload, text: Self.hubSwitchText(result.payload), output: output)
                exitCode = result.exitCode
            default:
                throw CLIArgumentError("Unknown hub command; use hub accounts or hub switch.")
            }
        } catch {
            Self.exit(code: .usage, message: "Error: \(Self.hubErrorMessage(error))", output: output, kind: .args)
        }
        Self.exit(code: exitCode, output: output)
    }

    static func printHub(_ payload: some Encodable, text: String, output: CLIOutputPreferences) {
        if output.usesJSONOutput {
            Self.printJSON(payload, pretty: output.pretty)
        } else {
            print(text)
        }
    }

    static func hubAccountsRequest(from values: ParsedValues) throws
        -> (provider: HubCLIProvider, pending: OpenCodexHubPendingSwitch?)
    {
        let provider = try Self.hubProvider(from: values)
        let keys = ["pendingRequestId", "pendingTargetIdSuffix", "pendingTargetEmail", "pendingRequestedAt"]
        let given = keys.map { values.options[$0]?.last.flatMap(SettingsValue.cleaned) }
        if given.allSatisfy({ $0 == nil }) { return (provider, nil) }
        guard let requestID = given[0], let suffix = given[1], let email = given[2], let rawDate = given[3] else {
            throw CLIArgumentError(
                "--pending-request-id, --pending-target-id-suffix, --pending-target-email and " +
                    "--pending-requested-at must be given together.")
        }
        guard let requestedAt = Self.parseHubDate(rawDate) else {
            throw CLIArgumentError("--pending-requested-at must be an ISO 8601 date.")
        }
        let request = OpenCodexHubSwitchRequest(
            requestID: requestID,
            provider: provider.hubProvider,
            targetIDSuffix: suffix,
            targetEmail: email,
            requestedAt: requestedAt)
        return (provider, OpenCodexHubPendingSwitch(request: request))
    }

    static func hubProvider(from values: ParsedValues) throws -> HubCLIProvider {
        guard let provider = HubCLIProvider(argument: values.options["provider"]?.last) else {
            throw CLIArgumentError("--provider must be codex or claude.")
        }
        return provider
    }

    /// Reads `provider`'s hub pool. Exit 0 for a pool, `configured: false` and `noHubSource`; 1 for other errors.
    static func hubAccounts(
        provider: HubCLIProvider,
        pending: OpenCodexHubPendingSwitch?,
        config: CodexBarConfig,
        environment: HubCommandEnvironment = HubCommandEnvironment()) async
        -> (payload: HubAccountsPayload, exitCode: ExitCode)
    {
        let settings = HubProviderConfiguration.resolve(provider: provider, config: config)
        var payload = HubAccountsPayload(provider: provider.rawValue, configured: settings.configured)
        guard settings.configured else { return (payload, .success) }
        let now = environment.now()
        do {
            let read = try await OpenCodexHubReader.read(
                provider: provider.hubProvider,
                executablePath: settings.executablePath,
                snapshotPath: settings.snapshotPath,
                roleCache: environment.roleCache,
                now: now,
                timeout: environment.timeout)
            Self.fill(&payload, read: read, pending: pending, now: now)
            return (payload, .success)
        } catch {
            let code = Self.hubErrorCode(error)
            payload.error = HubErrorPayload(code: code, message: Self.hubErrorMessage(error))
            return (payload, code == "noHubSource" ? .success : .failure)
        }
    }

    private static func fill(
        _ payload: inout HubAccountsPayload,
        read: OpenCodexHubPoolRead,
        pending: OpenCodexHubPendingSwitch?,
        now: Date)
    {
        let pool = read.pool
        let stale = pool.isStale(now: now)
        switch read {
        case .live: payload.origin = "hubLocal"
        case .snapshot: payload.origin = "snapshot"
        case .linkedCopy: payload.origin = "linkedCopy"
        }
        payload.hub = pool.hubName
        payload.updatedAt = pool.snapshotUpdatedAt
        payload.stale = stale
        payload.switchable = pool.switchable
        payload.switchReason = pool.switchReason
        payload.activeIdSuffix = pool.activeAccount?.idSuffix
        payload.accounts = pool.accounts.map { account in
            HubAccountPayload(
                idSuffix: account.idSuffix,
                label: account.label,
                email: account.email,
                active: account.isActive,
                paused: account.isPaused,
                needsReauth: account.needsReauth,
                health: account.health,
                quotaUnavailable: account.quotaUnavailable,
                nearLimit: account.isNearLimit,
                canSwitch: pool.canSwitch(to: account) && !stale,
                quotaSummary: OpenCodexHubUsageProjection.summary(account.quota).map {
                    HubQuotaSummaryPayload(label: $0.label, usedPercent: $0.percent)
                },
                usage: OpenCodexHubUsageProjection.snapshot(
                    for: account,
                    provider: pool.provider,
                    fallbackUpdatedAt: pool.snapshotUpdatedAt ?? now))
        }
        payload.lastRequests = pool.lastRequests.map { result in
            HubRequestResultPayload(
                requestId: result.requestID,
                provider: result.provider?.rawValue,
                result: result.outcome.rawValue,
                code: result.code,
                reason: result.reason,
                at: result.at)
        }
        if let pending {
            payload.pending = Self.pendingPayload(pending, resolution: pending.resolution(in: pool, now: now))
        }
    }

    static func pendingPayload(
        _ pending: OpenCodexHubPendingSwitch,
        resolution: OpenCodexHubPendingSwitch.Resolution) -> HubPendingPayload
    {
        let id = pending.request.requestID
        switch resolution {
        case .pending: return HubPendingPayload(requestId: id, resolution: "pending", code: nil, reason: nil)
        case .done: return HubPendingPayload(requestId: id, resolution: "done", code: nil, reason: nil)
        case .expired: return HubPendingPayload(requestId: id, resolution: "expired", code: nil, reason: nil)
        case let .refused(code, reason):
            return HubPendingPayload(requestId: id, resolution: "refused", code: code, reason: reason)
        case let .failed(code, reason):
            return HubPendingPayload(requestId: id, resolution: "failed", code: code, reason: reason)
        }
    }

    static func hubAccountsText(_ payload: HubAccountsPayload) -> String {
        guard payload.configured else { return "\(payload.provider): opencodex hub not configured" }
        if let error = payload.error { return "\(payload.provider): \(error.message)" }
        var lines = ["\(payload.provider): \(payload.accounts.count) hub accounts (\(payload.origin ?? "unknown"))"]
        if payload.stale == true { lines.append("The hub list is out of date.") }
        if payload.switchable == false {
            lines.append(payload.switchReason ?? "Accounts in this pool are switched only on the hub.")
        }
        for account in payload.accounts {
            let summary = account.quotaSummary.map { "\($0.label): \(Int($0.usedPercent.rounded()))% used" }
            let mark = account.active ? "*" : " "
            lines.append("\(mark) \(account.label ?? account.email) \(summary.joined(separator: " · "))")
        }
        if let pending = payload.pending { lines.append("Pending switch: \(pending.resolution)") }
        return lines.joined(separator: "\n")
    }
}
