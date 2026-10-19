import CoreFoundation
import Foundation

/// The result of translating an opencodex account list: the shared list model
/// plus, for live hub lists, the opencodex account id of each slot.
public struct OpenCodexAccountListResult: Equatable, Sendable {
    public let list: ClaudeSwapAccountList
    /// Slot number to opencodex account id. Held in memory only to address
    /// `ocx account use`; never persisted, logged or shown. Empty for snapshots.
    public let accountIDs: [Int: String]

    public init(list: ClaudeSwapAccountList, accountIDs: [Int: String]) {
        self.list = list
        self.accountIDs = accountIDs
    }
}

public enum OpenCodexAccountListError: LocalizedError, Equatable, Sendable {
    case notJSONObject
    case malformedShape(String)
    /// The live list is not available on this Mac (for example a client linked to a hub).
    case hubAccountsUnavailable(String)
    case snapshotUnreadable(String)
    case accountNotFound(slot: Int)
    case accountChanged(slot: Int)
    case switchFailed(String)
    case mismatchedTarget

    public var errorDescription: String? {
        switch self {
        case .notJSONObject:
            "opencodex returned output that is not a JSON object."
        case let .malformedShape(details):
            "opencodex account list is malformed: \(details)"
        case let .hubAccountsUnavailable(details):
            "This Mac cannot list the opencodex hub's Claude accounts (\(details)). " +
                "Accounts are managed on the hub; set a hub snapshot file to view them here."
        case let .snapshotUnreadable(details):
            "The opencodex hub snapshot could not be read: \(details)"
        case let .accountNotFound(slot):
            "opencodex no longer lists Claude account \(slot); refresh and try again."
        case let .accountChanged(slot):
            "opencodex lists a different account in slot \(slot) now; refresh and try again."
        case let .switchFailed(details):
            "opencodex could not switch the account: \(details)"
        case .mismatchedTarget:
            "opencodex reported a different active account than the one CodexBar requested."
        }
    }
}

/// Strict reader of `ocx account list anthropic --quota --json` and of hub
/// snapshots in the same shape.
///
/// Only allow-listed fields are read: `id` (live lists only, to address a switch),
/// `email`/`label` (opencodex already masks them), `active`, `paused`,
/// `needsReauth`, `health`, `quotaUnavailable` and the quota windows. Slots are
/// assigned 1, 2, … in the order opencodex lists the accounts; a switch re-reads
/// the live list and checks the slot still holds the same account.
public enum OpenCodexAccountListParser {
    public static let provider = "anthropic"
    public static let listArguments = ["account", "list", "anthropic", "--quota", "--json"]
    static let maxAccountIDLength = 128

    /// Parses a live hub list (`{accounts, notes}`).
    public static func parseLiveList(_ data: Data) throws -> OpenCodexAccountListResult {
        try self.parse(object: self.jsonObject(data), readOnly: false, defaultFetchedAt: nil, remoteCopy: nil)
    }

    /// Parses a read-only hub snapshot: the live list shape plus optional `fetchedAt`
    /// (ISO 8601 or epoch milliseconds) and `hub` (display name of the managing machine),
    /// either at the top level or inside a `state` envelope.
    public static func parseSnapshot(_ data: Data) throws -> OpenCodexAccountListResult {
        var object = try self.jsonObject(data)
        if let state = object["state"] as? [String: Any] {
            object = state
        }
        let fetchedAt = self.date(object["fetchedAt"])
        let hub = (object["hub"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteCopy = ClaudeSwapRemoteCopy(
            managerName: hub.flatMap { $0.isEmpty ? nil : $0 },
            fetchedAt: fetchedAt)
        return try self.parse(object: object, readOnly: true, defaultFetchedAt: fetchedAt, remoteCopy: remoteCopy)
    }

    /// `true` when the data is a JSON object with an `accounts` member, i.e. opencodex
    /// answered with a list rather than an error on stderr.
    static func looksLikeAccountList(_ data: Data) -> Bool {
        guard let object = try? self.jsonObject(data) else { return false }
        return object["accounts"] != nil
    }

    /// `ocx account use anthropic <id> --json` prints `{ok, provider, type, activeId}`.
    public static func parseSwitchReceipt(_ data: Data) throws -> String {
        let object = try self.jsonObject(data)
        guard object["ok"] as? Bool == true else {
            throw OpenCodexAccountListError.malformedShape("switch receipt is not ok")
        }
        guard let activeID = object["activeId"] as? String, !activeID.isEmpty else {
            throw OpenCodexAccountListError.malformedShape("switch receipt has no activeId")
        }
        return activeID
    }

    static func isValidAccountID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= self.maxAccountIDLength, let first = id.unicodeScalars.first else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:@+-"))
        return CharacterSet.alphanumerics.contains(first) && id.unicodeScalars.allSatisfy {
            $0.isASCII && allowed.contains($0)
        }
    }

    // MARK: - Private

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any]
        else {
            throw OpenCodexAccountListError.notJSONObject
        }
        return object
    }

    private static func parse(
        object: [String: Any],
        readOnly: Bool,
        defaultFetchedAt: Date?,
        remoteCopy: ClaudeSwapRemoteCopy?) throws -> OpenCodexAccountListResult
    {
        guard let rawAccounts = object["accounts"] as? [Any] else {
            throw OpenCodexAccountListError.malformedShape("missing accounts array")
        }
        var rows: [ClaudeSwapAccountRow] = []
        var accountIDs: [Int: String] = [:]
        var seenIDs: Set<String> = []
        for rawRow in rawAccounts {
            guard let row = rawRow as? [String: Any] else {
                throw OpenCodexAccountListError.malformedShape("account row is not an object")
            }
            // Only the Anthropic pool feeds Claude cards; other providers never leak in.
            if let provider = row["provider"] as? String, provider != self.provider { continue }
            let slot = rows.count + 1
            if !readOnly {
                guard let id = row["id"] as? String, self.isValidAccountID(id) else {
                    throw OpenCodexAccountListError.malformedShape("account \(slot) has no usable id")
                }
                guard seenIDs.insert(id).inserted else {
                    throw OpenCodexAccountListError.malformedShape("duplicate account id in slot \(slot)")
                }
                accountIDs[slot] = id
            }
            try rows.append(self.parseRow(row, slot: slot, defaultFetchedAt: defaultFetchedAt))
        }
        let activeSlots = rows.filter(\.isActive).map(\.number)
        guard activeSlots.count <= 1 else {
            throw OpenCodexAccountListError.malformedShape("more than one active account")
        }
        let list = ClaudeSwapAccountList(
            activeAccountNumber: activeSlots.first,
            accounts: rows,
            supportsAccountSwitching: !readOnly,
            remoteCopy: remoteCopy)
        return OpenCodexAccountListResult(list: list, accountIDs: accountIDs)
    }

    private static func parseRow(
        _ row: [String: Any],
        slot: Int,
        defaultFetchedAt: Date?) throws -> ClaudeSwapAccountRow
    {
        guard let isActive = row["active"] as? Bool else {
            throw OpenCodexAccountListError.malformedShape("account \(slot) has no active flag")
        }
        let email = self.trimmed(row["email"]) ?? self.trimmed(row["label"]) ?? ""
        let label = self.trimmed(row["label"])
        let quota = row["quota"] as? [String: Any]
        let fiveHour = self.window(percent: quota?["fiveHourPercent"], resetsAt: quota?["fiveHourResetAt"])
        let weekly = self.window(percent: quota?["weeklyPercent"], resetsAt: quota?["weeklyResetAt"])
        let scoped = self.scopedWindows(quota?["customWindows"])
        let hasWindows = fiveHour != nil || weekly != nil || !scoped.isEmpty
        return ClaudeSwapAccountRow(
            number: slot,
            email: email,
            alias: label.flatMap { $0 == email ? nil : $0 },
            isActive: isActive,
            usageStatus: self.usageStatus(row, hasWindows: hasWindows),
            fiveHour: fiveHour,
            sevenDay: weekly,
            scoped: scoped,
            usageFetchedAt: self.date(quota?["updatedAt"]) ?? defaultFetchedAt,
            isDisabled: row["paused"] as? Bool ?? false)
    }

    private static func usageStatus(_ row: [String: Any], hasWindows: Bool) -> ClaudeSwapUsageStatus {
        let health = (row["health"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if row["needsReauth"] as? Bool == true
            || health == "Reauthentication required"
            || health == "Verification required"
        {
            return .reloginRequired
        }
        if health == "Refresh failed" { return .tokenExpired }
        if row["quotaUnavailable"] as? Bool == true || !hasWindows { return .unavailable }
        return .ok
    }

    private static func window(percent rawPercent: Any?, resetsAt rawResetsAt: Any?) -> ClaudeSwapUsageWindow? {
        guard let percent = self.finiteDouble(rawPercent) else { return nil }
        return ClaudeSwapUsageWindow(usedPercent: min(max(percent, 0), 100), resetsAt: self.date(rawResetsAt))
    }

    /// `quota.customWindows` (for example the model-scoped Fable week) are additive;
    /// malformed rows are skipped so they cannot hide the account-wide windows.
    private static func scopedWindows(_ raw: Any?) -> [ClaudeSwapScopedUsageWindow] {
        guard let rows = raw as? [Any] else { return [] }
        return rows.compactMap { rawRow in
            guard let row = rawRow as? [String: Any],
                  let name = self.trimmed(row["label"]),
                  let percent = self.finiteDouble(row["percent"])
            else { return nil }
            return ClaudeSwapScopedUsageWindow(
                name: name,
                usedPercent: min(max(percent, 0), 100),
                resetsAt: self.date(row["resetAt"]))
        }
    }

    /// opencodex reports epoch milliseconds; snapshots may also carry ISO 8601 strings.
    static func date(_ raw: Any?) -> Date? {
        if let text = raw as? String {
            return ISO8601DateParser.parse(text)
        }
        guard let value = self.finiteDouble(raw), value > 0 else { return nil }
        // Values below 1e11 cannot be milliseconds after 1973; read them as seconds.
        return Date(timeIntervalSince1970: value >= 100_000_000_000 ? value / 1000 : value)
    }

    private static func trimmed(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func finiteDouble(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber else { return nil }
        // JSON booleans bridge to NSNumber too; only accept genuine numbers.
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }
}
