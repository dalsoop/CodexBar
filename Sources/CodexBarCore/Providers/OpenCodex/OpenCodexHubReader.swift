import Foundation

public enum OpenCodexHubReaderError: LocalizedError, Equatable, Sendable {
    /// This Mac cannot list the hub's accounts (for example a client linked to a hub) and has no snapshot.
    case hubAccountsUnavailable(String)
    case snapshotUnreadable(String)
    case accountNotFound
    case switchNotAllowed(String?)
    case switchFailed(String)
    case mismatchedTarget

    public var errorDescription: String? {
        switch self {
        case let .hubAccountsUnavailable(details):
            "This Mac cannot list the opencodex hub's accounts (\(details)). " +
                "Accounts are managed on the hub; set a hub snapshot file to view them here."
        case let .snapshotUnreadable(details):
            "The opencodex hub snapshot could not be read: \(details)"
        case .accountNotFound:
            "The hub no longer lists this account; refresh and try again."
        case let .switchNotAllowed(reason):
            reason ?? "This pool cannot be switched from this Mac."
        case let .switchFailed(details):
            "opencodex could not switch the account: \(details)"
        case .mismatchedTarget:
            "opencodex reported a different active account than the one CodexBar requested."
        }
    }
}

/// What a switch did: switched on the hub itself, or left a request for the hub.
public enum OpenCodexHubSwitchOutcome: Equatable, Sendable {
    case alreadyActive
    case switched
    case requested(OpenCodexHubSwitchRequest)
}

/// Bounded adapter over the opencodex hub's account pools.
///
/// On the hub, `ocx account list <provider> --quota --json` lists a pool and
/// `ocx account use <provider> <id> --json` switches it; only those fixed argument arrays run, never a
/// shell. A Mac linked to a hub cannot list the hub's accounts: it reads the snapshot file the hub
/// writes and asks for a switch by writing a request file next to it. opencodex keeps the credentials
/// on the hub; CodexBar never reads or stores them, and full account ids stay in memory.
public enum OpenCodexHubReader {
    public static let defaultTimeout: TimeInterval = 30
    public static let maxOutputBytes = 262_144
    static let diagnosticLimit = 200
    /// Where `ocx` is looked for when no executable path is configured.
    public static let executableSearchPaths = [
        "/opt/homebrew/bin/ocx",
        "/usr/local/bin/ocx",
        "~/.local/bin/ocx",
    ]

    /// The configured executable, or the first `ocx` found in the usual install locations.
    public static func resolvedExecutablePath(
        _ configured: String?,
        fileManager: FileManager = .default) -> String?
    {
        if let configured = SettingsValue.cleaned(configured) {
            return (configured as NSString).expandingTildeInPath
        }
        return self.executableSearchPaths
            .map { ($0 as NSString).expandingTildeInPath }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// Reads a pool: the live list when this Mac is the hub, otherwise the snapshot file.
    public static func readPool(
        provider: OpenCodexHubProvider,
        executablePath: String?,
        snapshotPath: String?,
        timeout: TimeInterval = OpenCodexHubReader.defaultTimeout) async throws -> OpenCodexHubPool
    {
        let liveFailure: String
        if let binary = self.resolvedExecutablePath(executablePath) {
            do {
                return try await self.readLivePool(provider: provider, binary: binary, timeout: timeout).pool
            } catch let error as OpenCodexHubReaderError {
                guard case let .hubAccountsUnavailable(details) = error else { throw error }
                liveFailure = details
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as OpenCodexHubPoolError {
                // A hub that answers with a malformed list is a real error, not a client.
                throw error
            } catch {
                liveFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        } else {
            liveFailure = "no ocx executable"
        }
        guard let snapshotPath = SettingsValue.cleaned(snapshotPath) else {
            throw OpenCodexHubReaderError.hubAccountsUnavailable(liveFailure)
        }
        return try self.readSnapshot(provider: provider, path: snapshotPath).pool
    }

    /// Reads the live hub list. Throws `.hubAccountsUnavailable` when opencodex answers without a list
    /// (for example `Error: not_found` on a linked client).
    public static func readLivePool(
        provider: OpenCodexHubProvider,
        binary: String,
        timeout: TimeInterval = OpenCodexHubReader.defaultTimeout) async throws -> OpenCodexHubLivePool
    {
        try Task.checkCancellation()
        let result = try await SubprocessRunner.run(
            binary: binary,
            arguments: provider.listArguments,
            environment: self.environment(for: binary),
            timeout: timeout,
            acceptsNonZeroExit: true,
            label: "opencodex list")
        let data = try self.boundedOutput(result.stdout)
        guard OpenCodexHubPoolParser.looksLikeAccountList(data) else {
            throw OpenCodexHubReaderError.hubAccountsUnavailable(self.diagnostic(result))
        }
        return try OpenCodexHubPoolParser.parseLiveList(data, provider: provider)
    }

    public static func readSnapshot(provider: OpenCodexHubProvider, path: String) throws -> OpenCodexHubSnapshotPool {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data: Data
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > self.maxOutputBytes {
                throw OpenCodexHubReaderError.snapshotUnreadable("file is larger than the list limit")
            }
            data = try Data(contentsOf: url)
        } catch let error as OpenCodexHubReaderError {
            throw error
        } catch {
            throw OpenCodexHubReaderError.snapshotUnreadable("no readable file at \(url.lastPathComponent)")
        }
        return try OpenCodexHubPoolParser.parseSnapshot(data, provider: provider)
    }

    /// Switches `provider`'s pool to the account with this id suffix and masked email.
    ///
    /// On the hub the live list is read again so the account is resolved against what the hub lists now,
    /// then `ocx account use` runs to its natural exit. On another Mac the snapshot is read again, the
    /// target is checked against it and a request file is written for the hub's next pass.
    public static func switchAccount(
        provider: OpenCodexHubProvider,
        idSuffix: String,
        email: String,
        executablePath: String?,
        snapshotPath: String?,
        now: Date = Date(),
        timeout: TimeInterval = OpenCodexHubReader.defaultTimeout) async throws -> OpenCodexHubSwitchOutcome
    {
        if let binary = self.resolvedExecutablePath(executablePath) {
            let live: OpenCodexHubLivePool?
            do {
                live = try await self.readLivePool(provider: provider, binary: binary, timeout: timeout)
            } catch let error as OpenCodexHubPoolError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Not the hub (or ocx unusable here): fall back to a request when a snapshot is configured.
                guard SettingsValue.cleaned(snapshotPath) != nil else { throw error }
                live = nil
            }
            if let live {
                return try await self.switchOnHub(live, idSuffix: idSuffix, email: email, binary: binary)
            }
        }
        guard let snapshotPath = SettingsValue.cleaned(snapshotPath) else {
            throw OpenCodexHubReaderError.hubAccountsUnavailable("no ocx executable")
        }
        let pool = try self.readSnapshot(provider: provider, path: snapshotPath).pool
        return try self.requestSwitch(
            pool: pool,
            idSuffix: idSuffix,
            email: email,
            requestsDirectory: OpenCodexHubSwitchRequestWriter.requestsDirectory(forSnapshotPath: snapshotPath),
            now: now)
    }

    /// Writes a switch request for the hub after checking the target against `pool`.
    public static func requestSwitch(
        pool: OpenCodexHubPool,
        idSuffix: String,
        email: String,
        requestsDirectory: URL,
        requestID: String = UUID().uuidString,
        now: Date = Date()) throws -> OpenCodexHubSwitchOutcome
    {
        let matches = pool.accounts.filter { $0.idSuffix == idSuffix && $0.email == email }
        guard matches.count == 1, let account = matches.first else {
            throw OpenCodexHubReaderError.accountNotFound
        }
        if account.isActive { return .alreadyActive }
        guard pool.switchable else { throw OpenCodexHubReaderError.switchNotAllowed(pool.switchReason) }
        guard pool.canSwitch(to: account) else { throw OpenCodexHubReaderError.switchNotAllowed(nil) }
        let request = OpenCodexHubSwitchRequest(
            requestID: requestID,
            provider: pool.provider,
            targetIDSuffix: idSuffix,
            targetEmail: email,
            requestedAt: now)
        try OpenCodexHubSwitchRequestWriter.write(request, to: requestsDirectory)
        return .requested(request)
    }

    static func switchOnHub(
        _ live: OpenCodexHubLivePool,
        idSuffix: String,
        email: String,
        binary: String) async throws -> OpenCodexHubSwitchOutcome
    {
        let matches = live.pool.accounts.indices.filter {
            live.pool.accounts[$0].idSuffix == idSuffix && live.pool.accounts[$0].email == email
        }
        guard matches.count == 1, let index = matches.first else {
            throw OpenCodexHubReaderError.accountNotFound
        }
        if live.pool.accounts[index].isActive { return .alreadyActive }
        let accountID = live.accountIDs[index]
        let result = try await SubprocessRunner.runToCompletion(
            binary: binary,
            arguments: ["account", "use", live.pool.provider.rawValue, accountID, "--json"],
            environment: self.environment(for: binary),
            acceptsNonZeroExit: true,
            label: "opencodex switch")
        let activeID: String
        do {
            activeID = try OpenCodexHubPoolParser.parseSwitchReceipt(self.boundedOutput(result.stdout))
        } catch {
            throw OpenCodexHubReaderError.switchFailed(self.diagnostic(result))
        }
        guard activeID == accountID else { throw OpenCodexHubReaderError.mismatchedTarget }
        return .switched
    }

    /// `ocx` is a Node launcher (`#!/usr/bin/env node`). A menu bar app inherits launchd's short PATH, so
    /// the directory the executable was configured in (for example `/opt/homebrew/bin`, where Homebrew
    /// also links `node`) goes first.
    static func environment(
        for binary: String,
        base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String]
    {
        var environment = base
        let directory = (binary as NSString).deletingLastPathComponent
        guard !directory.isEmpty else { return environment }
        let existing = environment["PATH"].map { ":" + $0 } ?? ""
        environment["PATH"] = directory + existing
        return environment
    }

    static func boundedOutput(_ stdout: String) throws -> Data {
        guard stdout.utf8.count <= self.maxOutputBytes else {
            throw ClaudeSwapAccountReaderError.outputTooLarge(byteCount: stdout.utf8.count)
        }
        return Data(stdout.utf8)
    }

    /// The first non-empty stderr line (opencodex prints `Error: <code>` there), bounded.
    static func diagnostic(_ result: SubprocessResult) -> String {
        let line = result.stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return "no account list" }
        return String(line.prefix(self.diagnosticLimit))
    }
}
