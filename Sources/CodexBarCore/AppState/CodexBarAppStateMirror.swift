import Foundation

/// The app's agent-readable state mirror: what the menu shows, as a small JSON file other tools read instead of
/// screenshots (`~/.swift-app-state/codexbar.json`).
///
/// The file follows the StateMirror envelope (`{"app", "updatedAt", "state"}`); `state.status` is `ok` or `error`
/// and `state.lastError` is left out when there is no error. It holds summaries only: provider ids, sources,
/// refresh times, sanitized error text, masked account labels and quota percentages. Never tokens, cookies, full
/// account ids or unmasked emails. The app rewrites it atomically after each refresh; `codexbar app-state` prints it.
public enum CodexBarAppStateMirror {
    public static let appSlug = "codexbar"
    public static let schemaVersion = 1
    /// `SWIFT_APP_STATE_DIRECTORY` replaces `~/.swift-app-state` (tests and other state roots).
    public static let directoryOverrideKey = "SWIFT_APP_STATE_DIRECTORY"
    static let maxErrorLength = 300

    public struct Envelope: Codable, Equatable, Sendable {
        public var app: String
        public var updatedAt: String
        public var state: State

        public init(app: String = CodexBarAppStateMirror.appSlug, updatedAt: String, state: State) {
            self.app = app
            self.updatedAt = updatedAt
            self.state = state
        }
    }

    public struct State: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        /// `ok`, or `error` when any enabled provider shows an error.
        public var status: String
        /// The first enabled provider's error as `<provider>: <message>`; absent when `status` is `ok`.
        public var lastError: String?
        public var appVersion: String?
        public var appBuild: String?
        public var bundleID: String?
        public var gitCommit: String?
        public var multiAccountMenuLayout: String?
        /// How this Mac reaches the opencodex hub, from the hub-backed cards: `hub`, `client` (reads the hub's
        /// snapshot) or `client-local-copy` (no current snapshot; this Mac's own read-only list). Absent when no
        /// card reads a hub.
        public var hubRole: String?
        public var providers: [Provider]

        public init(
            appVersion: String?,
            appBuild: String?,
            bundleID: String?,
            gitCommit: String?,
            multiAccountMenuLayout: String?,
            hubRole: String?,
            providers: [Provider])
        {
            self.schemaVersion = CodexBarAppStateMirror.schemaVersion
            self.appVersion = appVersion
            self.appBuild = appBuild
            self.bundleID = bundleID
            self.gitCommit = gitCommit
            self.multiAccountMenuLayout = multiAccountMenuLayout
            self.hubRole = hubRole
            self.providers = providers
            let failing = providers.first { $0.enabled && ($0.error != nil || $0.accountError != nil) }
            self.status = failing == nil ? "ok" : "error"
            self.lastError = failing.map { "\($0.id): \($0.error ?? $0.accountError ?? "")" }
        }
    }

    public struct Provider: Codable, Equatable, Sendable {
        public var id: String
        public var enabled: Bool
        /// The source the card read: `opencodex-hub`, `opencodex` (Claude account adapter) or the provider's own
        /// source label.
        public var source: String?
        public var lastRefreshAt: String?
        /// When the card last had usage (the shown snapshot's time).
        public var lastSuccessAt: String?
        public var error: String?
        /// Where the account list comes from (`opencodex-hub`, `opencodex`, `claude-swap`, `codex-accounts`).
        public var accountSource: String?
        /// The account list's own error (the Claude account adapter keeps its last list and reports this).
        public var accountError: String?
        /// The shown data is older than the source's freshness limit (a hub snapshot over five minutes old).
        public var stale: Bool
        public var windows: [Window]
        public var accounts: [Account]

        public init(
            id: String,
            enabled: Bool,
            source: String?,
            lastRefreshAt: Date?,
            lastSuccessAt: Date?,
            error: String?,
            accountSource: String? = nil,
            accountError: String? = nil,
            stale: Bool,
            windows: [Window],
            accounts: [Account])
        {
            self.id = id
            self.accountSource = accountSource
            self.accountError = accountError.flatMap(CodexBarAppStateMirror.sanitizedError)
            self.enabled = enabled
            self.source = source
            self.lastRefreshAt = lastRefreshAt.map(CodexBarAppStateMirror.timestamp)
            self.lastSuccessAt = lastSuccessAt.map(CodexBarAppStateMirror.timestamp)
            self.error = error.flatMap(CodexBarAppStateMirror.sanitizedError)
            self.stale = stale
            self.windows = windows
            self.accounts = accounts
        }
    }

    public struct Account: Codable, Equatable, Sendable {
        /// Masked: emails keep their first and last character before `@`.
        public var label: String
        public var active: Bool
        public var windows: [Window]
        public var error: String?

        public init(label: String, active: Bool, windows: [Window], error: String? = nil) {
            self.label = CodexBarAppStateMirror.maskedLabel(label)
            self.active = active
            self.windows = windows
            self.error = error.flatMap(CodexBarAppStateMirror.sanitizedError)
        }
    }

    public struct Window: Codable, Equatable, Sendable {
        public var name: String
        public var usedPercent: Double
        public var resetAt: String?

        public init(name: String, usedPercent: Double, resetAt: Date?) {
            self.name = name
            self.usedPercent = (usedPercent * 10).rounded() / 10
            self.resetAt = resetAt.map(CodexBarAppStateMirror.timestamp)
        }
    }

    // MARK: - File

    public static func directoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()) -> URL
    {
        if let override = environment[self.directoryOverrideKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".swift-app-state", isDirectory: true)
    }

    public static func fileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()) -> URL
    {
        self.directoryURL(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent("\(self.appSlug).json")
    }

    public static func encode(_ state: State, now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(updatedAt: self.timestamp(now), state: state))
    }

    /// Writes the envelope atomically (temporary file, then rename) and creates the directory when missing.
    public static func write(_ state: State, to url: URL, now: Date = Date()) throws {
        let data = try self.encode(state, now: now)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> Envelope {
        try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
    }

    // MARK: - Sanitizing

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// One line, at most `maxErrorLength` characters, with anything that looks like a credential replaced.
    public static func sanitizedError(_ message: String) -> String? {
        var text = message.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let patterns = [
            #"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]+"#,
            #"(?i)\b(sk-ant-|sk-|ocx_[a-z]+_|xai-|ghp_|glpat-)[A-Za-z0-9._-]+"#,
            #"(?i)\b(token|cookie|secret|password|api[_-]?key|authorization)\b(\s*[:=]\s*)\S+"#,
            #"\b[A-Za-z0-9_-]{32,}\b"#,
            #"\beyJ[A-Za-z0-9._-]+"#,
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        text = self.maskEmails(in: text)
        if text.count > self.maxErrorLength {
            text = String(text.prefix(self.maxErrorLength - 1)) + "…"
        }
        return text
    }

    /// An account label as the menu shows it, with any unmasked email masked.
    public static func maskedLabel(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "account" : self.maskEmails(in: trimmed)
    }

    static func maskEmails(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z0-9._%+*-]+)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})"#)
        else { return text }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let local = source.substring(with: match.range(at: 1))
            let domain = source.substring(with: match.range(at: 2))
            result += "\(self.maskedLocalPart(local))@\(domain)"
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    static func maskedLocalPart(_ local: String) -> String {
        if local.contains("*") { return local }
        guard let first = local.first, let last = local.last, local.count > 1 else { return "*" }
        return "\(first)***\(last)"
    }
}
