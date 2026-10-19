import Foundation

/// The Claude account adapter's view of the opencodex hub's Anthropic pool.
///
/// On the hub it runs `ocx account list anthropic --quota --json` and, for an explicit switch,
/// `ocx account use anthropic <id> --json` (fixed argument arrays, never a shell; see
/// `OpenCodexHubReader`). A Mac linked to a hub cannot list the hub's accounts: it reads the hub's
/// snapshot file and asks for a switch with a request file next to it. opencodex keeps the
/// credentials on the hub; CodexBar never reads or stores them, and full account ids stay in memory.
public enum OpenCodexAccountReader {
    public static func readAccountList(
        executablePath: String,
        snapshotPath: String?,
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> ClaudeSwapAccountList
    {
        let liveFailure: String
        if let binary = OpenCodexHubReader.resolvedExecutablePath(executablePath) {
            do {
                return try await self.readLiveList(binary: binary, timeout: timeout).list
            } catch let error as OpenCodexAccountListError {
                // A hub that answers with a malformed list is a real error, not a client.
                guard case let .hubAccountsUnavailable(details) = error else { throw error }
                liveFailure = details
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                liveFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        } else {
            liveFailure = "no ocx executable"
        }
        guard let snapshotPath = SettingsValue.cleaned(snapshotPath) else {
            throw OpenCodexAccountListError.hubAccountsUnavailable(liveFailure)
        }
        return try self.readSnapshot(path: snapshotPath).list
    }

    /// Reads the live hub list. Throws `.hubAccountsUnavailable` when opencodex answers without a list
    /// (for example `Error: not_found` on a linked client).
    public static func readLiveList(
        executablePath: String,
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> OpenCodexAccountListResult
    {
        let binary = try ClaudeSwapAccountReader.resolvedExecutablePath(executablePath)
        return try await self.readLiveList(binary: binary, timeout: timeout)
    }

    public static func readSnapshot(path: String) throws -> OpenCodexAccountListResult {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data: Data
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > ClaudeSwapAccountReader.maxOutputBytes {
                throw OpenCodexAccountListError.snapshotUnreadable("file is larger than the list limit")
            }
            data = try Data(contentsOf: url)
        } catch let error as OpenCodexAccountListError {
            throw error
        } catch {
            throw OpenCodexAccountListError.snapshotUnreadable("no readable file at \(url.lastPathComponent)")
        }
        return try OpenCodexAccountListParser.parseSnapshot(data)
    }

    /// Switches the hub's Anthropic pool to the account in `accountNumber`.
    ///
    /// On the hub the live list is read again so the slot is resolved against what the hub lists now;
    /// when `expectedEmail` is given the slot must still hold that (masked) account. Once launched,
    /// `ocx account use` runs to its natural exit. On another Mac the snapshot is read again with the
    /// same checks and a switch request is written for the hub (`reason == "requested"`).
    public static func switchAccount(
        executablePath: String,
        accountNumber: Int,
        expectedEmail: String?,
        snapshotPath: String? = nil,
        now: Date = Date(),
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> ClaudeSwapAccountSwitchResult
    {
        guard accountNumber > 0 else {
            throw OpenCodexAccountListError.accountNotFound(slot: accountNumber)
        }
        let snapshotPath = SettingsValue.cleaned(snapshotPath)
        if let binary = OpenCodexHubReader.resolvedExecutablePath(executablePath) {
            let current: OpenCodexAccountListResult?
            do {
                current = try await self.readLiveList(binary: binary, timeout: timeout)
            } catch let error as OpenCodexAccountListError {
                guard case .hubAccountsUnavailable = error, snapshotPath != nil else { throw error }
                current = nil
            }
            if let current {
                return try await self.switchOnHub(
                    current,
                    accountNumber: accountNumber,
                    expectedEmail: expectedEmail,
                    binary: binary)
            }
        }
        guard let snapshotPath else {
            throw OpenCodexAccountListError.hubAccountsUnavailable("no ocx executable")
        }
        let snapshot = try self.readSnapshot(path: snapshotPath)
        let (row, account) = try self.resolve(snapshot, accountNumber: accountNumber, expectedEmail: expectedEmail)
        let previous = snapshot.list.activeAccountNumber
        if row.isActive {
            return ClaudeSwapAccountSwitchResult(
                switched: false, fromAccountNumber: previous, toAccountNumber: accountNumber, reason: "already-active")
        }
        guard let idSuffix = account.idSuffix else {
            throw OpenCodexAccountListError.switchNotAllowed(nil)
        }
        let outcome: OpenCodexHubSwitchOutcome
        do {
            outcome = try OpenCodexHubReader.requestSwitch(
                pool: snapshot.pool,
                idSuffix: idSuffix,
                email: account.email,
                requestsDirectory: OpenCodexHubSwitchRequestWriter.requestsDirectory(forSnapshotPath: snapshotPath),
                now: now)
        } catch let error as OpenCodexHubReaderError {
            throw OpenCodexAccountListError(error, slot: accountNumber)
        }
        guard case let .requested(request) = outcome else {
            return ClaudeSwapAccountSwitchResult(
                switched: false, fromAccountNumber: previous, toAccountNumber: accountNumber, reason: "already-active")
        }
        return ClaudeSwapAccountSwitchResult(
            switched: false,
            fromAccountNumber: previous,
            toAccountNumber: accountNumber,
            reason: "requested",
            hubRequest: request)
    }

    // MARK: - Private

    private static func readLiveList(binary: String, timeout: TimeInterval) async throws -> OpenCodexAccountListResult {
        try Task.checkCancellation()
        let result = try await SubprocessRunner.run(
            binary: binary,
            arguments: OpenCodexAccountListParser.listArguments,
            environment: self.environment(for: binary),
            timeout: timeout,
            acceptsNonZeroExit: true,
            label: "opencodex list")
        let data = try OpenCodexHubReader.boundedOutput(result.stdout)
        guard OpenCodexHubPoolParser.looksLikeAccountList(data) else {
            throw OpenCodexAccountListError.hubAccountsUnavailable(OpenCodexHubReader.diagnostic(result))
        }
        return try OpenCodexAccountListParser.parseLiveList(data)
    }

    private static func resolve(
        _ current: OpenCodexAccountListResult,
        accountNumber: Int,
        expectedEmail: String?) throws -> (ClaudeSwapAccountRow, OpenCodexHubAccount)
    {
        guard let row = current.list.accounts.first(where: { $0.number == accountNumber }),
              current.pool.accounts.indices.contains(accountNumber - 1)
        else {
            throw OpenCodexAccountListError.accountNotFound(slot: accountNumber)
        }
        if let expectedEmail = SettingsValue.cleaned(expectedEmail), expectedEmail != row.email {
            throw OpenCodexAccountListError.accountChanged(slot: accountNumber)
        }
        return (row, current.pool.accounts[accountNumber - 1])
    }

    private static func switchOnHub(
        _ current: OpenCodexAccountListResult,
        accountNumber: Int,
        expectedEmail: String?,
        binary: String) async throws -> ClaudeSwapAccountSwitchResult
    {
        let (row, _) = try self.resolve(current, accountNumber: accountNumber, expectedEmail: expectedEmail)
        guard let accountID = current.accountIDs[accountNumber] else {
            throw OpenCodexAccountListError.accountNotFound(slot: accountNumber)
        }
        let previous = current.list.activeAccountNumber
        if row.isActive {
            return ClaudeSwapAccountSwitchResult(
                switched: false,
                fromAccountNumber: previous,
                toAccountNumber: accountNumber,
                reason: "already-active")
        }
        let result = try await SubprocessRunner.runToCompletion(
            binary: binary,
            arguments: ["account", "use", OpenCodexAccountListParser.provider, accountID, "--json"],
            environment: self.environment(for: binary),
            acceptsNonZeroExit: true,
            label: "opencodex switch")
        let activeID: String
        do {
            activeID = try OpenCodexAccountListParser
                .parseSwitchReceipt(OpenCodexHubReader.boundedOutput(result.stdout))
        } catch {
            throw OpenCodexAccountListError.switchFailed(OpenCodexHubReader.diagnostic(result))
        }
        guard activeID == accountID else {
            throw OpenCodexAccountListError.mismatchedTarget
        }
        return ClaudeSwapAccountSwitchResult(
            switched: true,
            fromAccountNumber: previous,
            toAccountNumber: accountNumber,
            reason: "switched")
    }

    static func environment(
        for binary: String,
        base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String]
    {
        OpenCodexHubReader.environment(for: binary, base: base)
    }
}
