import CodexBarCore
import Commander
import Foundation

struct HubSwitchCLIRequest: Equatable, Sendable {
    let provider: HubCLIProvider
    let idSuffix: String
    let email: String
}

extension CodexBarCLI {
    static let hubSwitchConfirmMessage =
        "hub switch needs --confirm: a hub switch moves every machine that uses the hub to this account."

    /// Validates `hub switch` arguments. Without `--confirm` this throws before anything is read or written.
    static func hubSwitchRequest(from values: ParsedValues) throws -> HubSwitchCLIRequest {
        let provider = try Self.hubProvider(from: values)
        guard values.flags.contains("confirm") else { throw CLIArgumentError(Self.hubSwitchConfirmMessage) }
        guard let idSuffix = values.options["idSuffix"]?.last.flatMap(SettingsValue.cleaned) else {
            throw CLIArgumentError("--id-suffix is required.")
        }
        guard let email = values.options["email"]?.last.flatMap(SettingsValue.cleaned) else {
            throw CLIArgumentError("--email is required.")
        }
        return HubSwitchCLIRequest(provider: provider, idSuffix: idSuffix, email: email)
    }

    /// One switch through the core: at most one request file, no retry.
    static func hubSwitch(
        _ request: HubSwitchCLIRequest,
        config: CodexBarConfig,
        environment: HubCommandEnvironment = HubCommandEnvironment()) async
        -> (payload: HubSwitchPayload, exitCode: ExitCode)
    {
        var payload = HubSwitchPayload(provider: request.provider.rawValue)
        let settings = HubProviderConfiguration.resolve(provider: request.provider, config: config)
        guard settings.configured else {
            payload.error = HubErrorPayload(
                code: "notConfigured",
                message: "The opencodex hub is not configured for \(request.provider.rawValue).")
            return (payload, .failure)
        }
        let now = environment.now()
        do {
            let outcome = try await OpenCodexHubReader.switchAccount(
                provider: request.provider.hubProvider,
                idSuffix: request.idSuffix,
                email: request.email,
                executablePath: settings.executablePath,
                snapshotPath: settings.snapshotPath,
                roleCache: environment.roleCache,
                now: now,
                timeout: environment.timeout)
            switch outcome {
            case .alreadyActive:
                payload.outcome = "alreadyActive"
            case .switched:
                payload.outcome = "switched"
            case let .requested(written):
                payload.outcome = "requested"
                payload.request = HubSwitchRequestPayload(
                    requestId: written.requestID,
                    targetIdSuffix: written.targetIDSuffix,
                    targetEmail: written.targetEmail,
                    requestedAt: written.requestedAt)
            }
            return (payload, .success)
        } catch {
            let fallback = error is OpenCodexHubRequestError ? "requestFailed" : "readFailed"
            payload.error = HubErrorPayload(
                code: Self.hubErrorCode(error, fallback: fallback),
                message: Self.hubErrorMessage(error))
            return (payload, .failure)
        }
    }

    static func hubSwitchText(_ payload: HubSwitchPayload) -> String {
        if let error = payload.error { return "The hub could not switch: \(error.message)" }
        switch payload.outcome {
        case "requested": return "Asked the hub to switch; the result shows after the hub's next update."
        case "alreadyActive": return "The hub already uses this account."
        default: return "The hub switched accounts."
        }
    }
}
