import Foundation

/// Bounded adapter over the external `ocx` executable for the opencodex hub's
/// Anthropic account pool.
///
/// It runs only fixed argument arrays (never a shell): the list
/// `ocx account list anthropic --quota --json`, the version probe and, for an
/// explicit switch, `ocx account use anthropic <id> --json`. opencodex keeps the
/// credentials on the hub; CodexBar never reads or stores them, and the account
/// ids it uses to address a switch stay in memory.
///
/// A Mac linked to a hub cannot list the hub's accounts. There, when a snapshot
/// path is configured, the adapter reads that JSON file (a copy of the hub's list
/// taken on the hub) and presents it read-only.
public enum OpenCodexAccountReader {
    static let diagnosticLimit = 200

    public static func readAccountList(
        executablePath: String,
        snapshotPath: String?,
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> ClaudeSwapAccountList
    {
        let liveFailure: String
        do {
            return try await self.readLiveList(executablePath: executablePath, timeout: timeout).list
        } catch let error as OpenCodexAccountListError {
            // A hub that answers with a malformed list is a real error, not a client.
            guard case let .hubAccountsUnavailable(details) = error else { throw error }
            liveFailure = details
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            liveFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        guard let snapshotPath = SettingsValue.cleaned(snapshotPath) else {
            throw OpenCodexAccountListError.hubAccountsUnavailable(liveFailure)
        }
        return try self.readSnapshot(path: snapshotPath).list
    }

    /// Reads the live hub list. Throws `.hubAccountsUnavailable` when opencodex
    /// answers without a list (for example `Error: not_found` on a linked client).
    public static func readLiveList(
        executablePath: String,
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> OpenCodexAccountListResult
    {
        try Task.checkCancellation()
        let binary = try ClaudeSwapAccountReader.resolvedExecutablePath(executablePath)
        let result = try await SubprocessRunner.run(
            binary: binary,
            arguments: OpenCodexAccountListParser.listArguments,
            environment: self.environment(for: binary),
            timeout: timeout,
            acceptsNonZeroExit: true,
            label: "opencodex list")
        let data = try self.boundedOutput(result.stdout)
        guard OpenCodexAccountListParser.looksLikeAccountList(data) else {
            throw OpenCodexAccountListError.hubAccountsUnavailable(self.diagnostic(result))
        }
        return try OpenCodexAccountListParser.parseLiveList(data)
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
    /// The live list is read again first so the slot is resolved against what the
    /// hub lists now; when `expectedEmail` is given the slot must still hold that
    /// (masked) account. Once launched, `ocx account use` runs to its natural exit.
    public static func switchAccount(
        executablePath: String,
        accountNumber: Int,
        expectedEmail: String?,
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> ClaudeSwapAccountSwitchResult
    {
        guard accountNumber > 0 else {
            throw OpenCodexAccountListError.accountNotFound(slot: accountNumber)
        }
        let current = try await self.readLiveList(executablePath: executablePath, timeout: timeout)
        guard let row = current.list.accounts.first(where: { $0.number == accountNumber }),
              let accountID = current.accountIDs[accountNumber]
        else {
            throw OpenCodexAccountListError.accountNotFound(slot: accountNumber)
        }
        if let expectedEmail = SettingsValue.cleaned(expectedEmail), expectedEmail != row.email {
            throw OpenCodexAccountListError.accountChanged(slot: accountNumber)
        }
        let previous = current.list.activeAccountNumber
        if row.isActive {
            return ClaudeSwapAccountSwitchResult(
                switched: false,
                fromAccountNumber: previous,
                toAccountNumber: accountNumber,
                reason: "already-active")
        }
        let binary = try ClaudeSwapAccountReader.resolvedExecutablePath(executablePath)
        let result = try await SubprocessRunner.runToCompletion(
            binary: binary,
            arguments: ["account", "use", OpenCodexAccountListParser.provider, accountID, "--json"],
            environment: self.environment(for: binary),
            acceptsNonZeroExit: true,
            label: "opencodex switch")
        let activeID: String
        do {
            activeID = try OpenCodexAccountListParser.parseSwitchReceipt(self.boundedOutput(result.stdout))
        } catch {
            throw OpenCodexAccountListError.switchFailed(self.diagnostic(result))
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

    private static func boundedOutput(_ stdout: String) throws -> Data {
        guard stdout.utf8.count <= ClaudeSwapAccountReader.maxOutputBytes else {
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
