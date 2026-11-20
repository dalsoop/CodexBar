import CodexBarCore
import Commander
import Foundation
import Testing
@testable import CodexBarCLI

/// Synthetic hub fixtures only: snapshot files in a temporary directory, an injected role probe and a fixed
/// clock. No real `ocx`, account, snapshot or request folder is touched.
private struct HubFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    let root: URL
    let snapshot: URL

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-hub-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        self.snapshot = self.root.appendingPathComponent("opencodex-hub-accounts.json")
    }

    var requests: URL {
        self.root.appendingPathComponent(OpenCodexHubSwitchRequestWriter.requestsDirectoryName, isDirectory: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: self.root)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static let openAIAccounts = """
    [{"idSuffix": "1a2b", "label": "pro", "email": "a***e@example.invalid", "active": true,
      "quota": {"weeklyPercent": 12, "monthlyPercent": 51}},
     {"idSuffix": "3c4d", "label": "b***b@example.invalid", "email": "b***b@example.invalid", "active": false,
      "quota": {"weeklyPercent": 85}},
     {"idSuffix": "5e6f", "email": "c***c@example.invalid", "active": false, "paused": true}]
    """

    static let anthropicAccounts = """
    [{"idSuffix": "aa11", "email": "d***d@example.invalid", "active": true,
      "quota": {"fiveHourPercent": 4, "weeklyPercent": 10}},
     {"idSuffix": "bb22", "email": "e***e@example.invalid", "active": false,
      "quota": {"fiveHourPercent": 0, "weeklyPercent": 20}}]
    """

    func writeSnapshot(
        updatedAt: Date = HubFixture.now.addingTimeInterval(-60),
        switchable: Bool = true,
        switchReason: String? = nil,
        lastRequests: String = "[]") throws
    {
        let reason = switchReason.map { "\"\($0)\"" } ?? "null"
        let body = """
        {"app": "synthetic", "updatedAt": "\(Self.iso(updatedAt))",
         "state": {"schemaVersion": 2, "hub": "hub-test", "fetchedAt": "\(Self.iso(updatedAt))",
           "providers": {
             "openai": {"switchable": \(switchable), "switchReason": \(reason), "accounts": \(Self.openAIAccounts)},
             "anthropic": {"switchable": \(switchable), "switchReason": \(reason),
                           "accounts": \(Self.anthropicAccounts)}},
           "lastRequests": \(lastRequests)}}
        """
        try body.write(to: self.snapshot, atomically: true, encoding: .utf8)
    }

    func codexConfig(enabled: Bool? = true, executable: String = "/usr/bin/false") -> CodexBarConfig {
        var provider = ProviderConfig(id: .codex)
        provider.openCodexHubEnabled = enabled
        provider.openCodexHubExecutablePath = executable
        provider.openCodexHubSnapshotPath = self.snapshot.path
        return CodexBarConfig(providers: [provider])
    }

    func claudeConfig(
        swapEnabled: Bool? = true,
        source: String? = "opencodex",
        hubEnabled: Bool? = nil,
        executable: String = "/usr/bin/false") -> CodexBarConfig
    {
        var provider = ProviderConfig(id: .claude)
        provider.claudeSwapEnabled = swapEnabled
        provider.claudeSwapSource = source
        provider.openCodexHubEnabled = hubEnabled
        provider.claudeSwapExecutablePath = executable
        provider.openCodexHubSnapshotPath = self.snapshot.path
        return CodexBarConfig(providers: [provider])
    }

    static func environment(role: OpenCodexRuntimeRole = .unknown) -> HubCommandEnvironment {
        HubCommandEnvironment(
            roleCache: OpenCodexRuntimeRoleCache(probe: { _ in role }),
            now: { HubFixture.now },
            timeout: 5)
    }

    func requestFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: self.requests.path)) ?? []
    }
}

private func parse(_ arguments: [String]) throws -> ParsedValues {
    let program = Program(descriptors: CodexBarCLI.commandDescriptors())
    return try program.resolve(arguments: arguments).parsedValues
}

private func jsonObject(_ payload: some Encodable) throws -> [String: Any] {
    let text = try #require(CodexBarCLI.encodeJSON(payload, pretty: false))
    return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private func pending(
    _ id: String = "req-1",
    suffix: String = "3c4d",
    email: String = "b***b@example.invalid",
    requestedAt: Date = HubFixture.now.addingTimeInterval(-60)) -> OpenCodexHubPendingSwitch
{
    OpenCodexHubPendingSwitch(request: OpenCodexHubSwitchRequest(
        requestID: id,
        provider: .openai,
        targetIDSuffix: suffix,
        targetEmail: email,
        requestedAt: requestedAt))
}

struct CLIHubCommandTests {
    @Test
    func `a provider without a configured hub reports configured false with null fields`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try fixture.writeSnapshot()
        let result = await CodexBarCLI.hubAccounts(
            provider: .codex, pending: nil, config: fixture.codexConfig(enabled: nil),
            environment: HubFixture.environment())
        #expect(result.exitCode == .success)
        let object = try jsonObject(result.payload)
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["provider"] as? String == "codex")
        #expect(object["configured"] as? Bool == false)
        for key in ["origin", "hub", "updatedAt", "stale", "switchable", "switchReason", "activeIdSuffix",
                    "pending", "error"]
        {
            #expect(object[key] is NSNull, "\(key) should be null")
        }
        #expect((object["accounts"] as? [Any])?.isEmpty == true)
        #expect((object["lastRequests"] as? [Any])?.isEmpty == true)
    }

    @Test
    func `claude is configured only by claudeSwapEnabled with the opencodex source`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try fixture.writeSnapshot()
        let env = HubFixture.environment()
        let cases: [(CodexBarConfig, Bool)] = [
            (fixture.claudeConfig(), true),
            (fixture.claudeConfig(swapEnabled: nil, source: "opencodex", hubEnabled: true), false),
            (fixture.claudeConfig(swapEnabled: true, source: "claude-swap", hubEnabled: true), false),
            (fixture.claudeConfig(swapEnabled: false, source: "opencodex"), false),
        ]
        for (config, configured) in cases {
            let result = await CodexBarCLI.hubAccounts(provider: .claude, pending: nil, config: config, environment: env)
            #expect(result.payload.configured == configured)
            #expect(result.exitCode == .success)
        }
        let claude = await CodexBarCLI.hubAccounts(
            provider: .claude, pending: nil, config: fixture.claudeConfig(), environment: env)
        #expect(claude.payload.accounts.map(\.idSuffix) == ["aa11", "bb22"])
        // Codex's own key never configures Claude.
        let codexOnly = await CodexBarCLI.hubAccounts(
            provider: .claude, pending: nil, config: fixture.codexConfig(), environment: env)
        #expect(codexOnly.payload.configured == false)
    }

    @Test
    func `a current snapshot pool is listed in hub order with the pinned fields`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try fixture.writeSnapshot(lastRequests: """
        [{"requestId": "old-1", "provider": "openai", "result": "refused", "code": "openai_hub_only",
          "reason": "Only on the hub", "at": "\(HubFixture.iso(HubFixture.now.addingTimeInterval(-120)))"}]
        """)
        let result = await CodexBarCLI.hubAccounts(
            provider: .codex, pending: nil, config: fixture.codexConfig(), environment: HubFixture.environment())
        #expect(result.exitCode == .success)
        let payload = result.payload
        #expect(payload.configured)
        #expect(payload.origin == "snapshot")
        #expect(payload.hub == "hub-test")
        #expect(payload.updatedAt == HubFixture.now.addingTimeInterval(-60))
        #expect(payload.stale == false)
        #expect(payload.switchable == true)
        #expect(payload.activeIdSuffix == "1a2b")
        #expect(payload.accounts.map(\.idSuffix) == ["1a2b", "3c4d", "5e6f"])
        #expect(payload.accounts.map(\.canSwitch) == [false, true, false])
        #expect(payload.accounts.map(\.nearLimit) == [false, true, false])
        #expect(payload.accounts.map(\.paused) == [false, false, true])
        #expect(payload.accounts[0].quotaSummary == [
            HubQuotaSummaryPayload(label: "Weekly", usedPercent: 12),
            HubQuotaSummaryPayload(label: "Monthly", usedPercent: 51),
        ])
        #expect(payload.accounts[0].usage.primary?.usedPercent == 12)
        #expect(payload.accounts[0].usage.secondary?.usedPercent == 51)
        #expect(payload.lastRequests.map(\.provider) == ["openai"])
        #expect(payload.lastRequests.first?.result == "refused")
        #expect(payload.error == nil)

        let object = try jsonObject(payload)
        #expect(object["provider"] as? String == "codex")
        #expect(object["pending"] is NSNull)
        #expect(object["error"] is NSNull)
        let account = try #require((object["accounts"] as? [[String: Any]])?.first)
        #expect(Set(account.keys) == [
            "idSuffix", "label", "email", "active", "paused", "needsReauth", "health", "quotaUnavailable",
            "nearLimit", "canSwitch", "quotaSummary", "usage",
        ])
        #expect(account["health"] is NSNull)
        let usage = try #require(account["usage"] as? [String: Any])
        #expect((usage["primary"] as? [String: Any])?["usedPercent"] as? Double == 12)
        // No full account id reaches the output.
        let text = try #require(CodexBarCLI.encodeJSON(payload, pretty: false))
        #expect(!text.contains("\"id\""))
    }

    @Test
    func `a stale snapshot is shown but nothing can be switched to`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try fixture.writeSnapshot(updatedAt: HubFixture.now.addingTimeInterval(-600))
        let result = await CodexBarCLI.hubAccounts(
            provider: .codex, pending: nil, config: fixture.codexConfig(), environment: HubFixture.environment())
        #expect(result.exitCode == .success)
        #expect(result.payload.stale == true)
        #expect(result.payload.accounts.count == 3)
        #expect(result.payload.accounts.allSatisfy { !$0.canSwitch })
    }

    @Test
    func `a pool that is not switchable passes the hub's reason through`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try fixture.writeSnapshot(switchable: false, switchReason: "Switched only on the hub")
        let result = await CodexBarCLI.hubAccounts(
            provider: .codex, pending: nil, config: fixture.codexConfig(), environment: HubFixture.environment())
        #expect(result.payload.switchable == false)
        #expect(result.payload.switchReason == "Switched only on the hub")
        #expect(result.payload.accounts.allSatisfy { !$0.canSwitch })
    }

    @Test
    func `no hub source is reported with exit zero and no accounts`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        let result = await CodexBarCLI.hubAccounts(
            provider: .codex, pending: nil, config: fixture.codexConfig(), environment: HubFixture.environment())
        #expect(result.exitCode == .success)
        #expect(result.payload.configured)
        #expect(result.payload.error?.code == "noHubSource")
        #expect(result.payload.accounts.isEmpty)
        #expect(result.payload.origin == nil)
    }

    @Test
    func `other read errors exit one with the reader case name or readFailed`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try "not json".write(to: fixture.snapshot, atomically: true, encoding: .utf8)
        let malformed = await CodexBarCLI.hubAccounts(
            provider: .codex, pending: nil, config: fixture.codexConfig(), environment: HubFixture.environment())
        #expect(malformed.exitCode == .failure)
        #expect(malformed.payload.error?.code == "readFailed")
        #expect(malformed.payload.accounts.isEmpty)

        // A client role whose own list answers nothing (/usr/bin/false) and no snapshot: a read error, not
        // "no source".
        try FileManager.default.removeItem(at: fixture.snapshot)
        let client = await CodexBarCLI.hubAccounts(
            provider: .codex, pending: nil, config: fixture.codexConfig(),
            environment: HubFixture.environment(role: .client))
        #expect(client.exitCode == .failure)
        #expect(client.payload.error?.code == "hubAccountsUnavailable")
    }
}

struct CLIHubCommandTestsPending {
    private func resolve(_ switchRequest: OpenCodexHubPendingSwitch, lastRequests: String = "[]") async throws
        -> HubPendingPayload?
    {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try fixture.writeSnapshot(lastRequests: lastRequests)
        let result = await CodexBarCLI.hubAccounts(
            provider: .codex, pending: switchRequest, config: fixture.codexConfig(),
            environment: HubFixture.environment())
        return result.payload.pending
    }

    @Test
    func `pending resolutions follow the core against the pool just read`() async throws {
        #expect(try await self.resolve(pending())?.resolution == "pending")
        #expect(try await self.resolve(pending(suffix: "1a2b", email: "a***e@example.invalid"))?.resolution == "done")
        #expect(try await self.resolve(pending(requestedAt: HubFixture.now.addingTimeInterval(-12 * 60)))?
            .resolution == "expired")
        let refused = try await self.resolve(pending(), lastRequests: """
        [{"requestId": "req-1", "provider": "openai", "result": "refused", "code": "superseded", "reason": "Newer"}]
        """)
        #expect(refused == HubPendingPayload(requestId: "req-1", resolution: "refused", code: "superseded",
                                             reason: "Newer"))
        let failed = try await self.resolve(pending(), lastRequests: """
        [{"requestId": "req-1", "provider": "openai", "result": "failed", "code": "use_failed"}]
        """)
        #expect(failed?.resolution == "failed")
        #expect(failed?.code == "use_failed")
        #expect(failed?.reason == nil)
        let done = try await self.resolve(pending(), lastRequests: """
        [{"requestId": "req-1", "provider": "openai", "result": "done", "code": "switched"}]
        """)
        #expect(done?.resolution == "done")
    }

    @Test
    func `pending flags are all or nothing`() throws {
        let none = try CodexBarCLI.hubAccountsRequest(from: parse(["hub", "accounts", "--provider", "codex"]))
        #expect(none.provider == .codex)
        #expect(none.pending == nil)
        let all = try CodexBarCLI.hubAccountsRequest(from: parse([
            "hub", "accounts", "--provider", "claude",
            "--pending-request-id", "req-9", "--pending-target-id-suffix", "bb22",
            "--pending-target-email", "e***e@example.invalid", "--pending-requested-at", "2027-01-15T08:00:00Z",
        ]))
        #expect(all.pending?.request.requestID == "req-9")
        #expect(all.pending?.request.provider == .anthropic)
        let expectedDate = try #require(CodexBarCLI.parseHubDate("2027-01-15T08:00:00Z"))
        #expect(all.pending?.request.requestedAt == expectedDate)
        #expect(throws: CLIArgumentError.self) {
            try CodexBarCLI.hubAccountsRequest(from: parse([
                "hub", "accounts", "--provider", "codex", "--pending-request-id", "req-9",
            ]))
        }
        #expect(throws: CLIArgumentError.self) {
            try CodexBarCLI.hubAccountsRequest(from: parse([
                "hub", "accounts", "--provider", "codex",
                "--pending-request-id", "req-9", "--pending-target-id-suffix", "bb22",
                "--pending-target-email", "e***e@example.invalid", "--pending-requested-at", "yesterday",
            ]))
        }
    }

    @Test
    func `an unknown or missing provider is a usage error`() throws {
        for arguments in [["hub", "accounts"], ["hub", "accounts", "--provider", "gemini"]] {
            #expect(throws: CLIArgumentError.self) {
                try CodexBarCLI.hubAccountsRequest(from: parse(arguments))
            }
        }
    }
}

struct CLIHubCommandTestsSwitch {
    private func request(_ suffix: String = "3c4d", email: String = "b***b@example.invalid") -> HubSwitchCLIRequest {
        HubSwitchCLIRequest(provider: .codex, idSuffix: suffix, email: email)
    }

    @Test
    func `switch without confirm is a usage error and writes nothing`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try fixture.writeSnapshot()
        let values = try parse([
            "hub", "switch", "--provider", "codex", "--id-suffix", "3c4d", "--email", "b***b@example.invalid",
        ])
        #expect(throws: CLIArgumentError.self) { try CodexBarCLI.hubSwitchRequest(from: values) }
        do {
            _ = try CodexBarCLI.hubSwitchRequest(from: values)
        } catch {
            #expect(error.localizedDescription.contains("every machine"))
        }
        #expect(fixture.requestFiles().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.requests.path))
        let confirmed = try CodexBarCLI.hubSwitchRequest(from: parse([
            "hub", "switch", "--provider", "codex", "--id-suffix", "3c4d", "--email", "b***b@example.invalid",
            "--confirm",
        ]))
        #expect(confirmed == self.request())
        for arguments in [
            ["hub", "switch", "--provider", "codex", "--email", "b***b@example.invalid", "--confirm"],
            ["hub", "switch", "--provider", "codex", "--id-suffix", "3c4d", "--confirm"],
            ["hub", "switch", "--provider", "grok", "--id-suffix", "3c4d", "--email", "x", "--confirm"],
        ] {
            #expect(throws: CLIArgumentError.self) { try CodexBarCLI.hubSwitchRequest(from: parse(arguments)) }
        }
    }

    @Test
    func `a switch on the request path writes one private request file`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        try fixture.writeSnapshot()
        let result = await CodexBarCLI.hubSwitch(
            self.request(), config: fixture.codexConfig(), environment: HubFixture.environment())
        #expect(result.exitCode == .success)
        #expect(result.payload.outcome == "requested")
        let written = try #require(result.payload.request)
        #expect(written.targetIdSuffix == "3c4d")
        #expect(written.targetEmail == "b***b@example.invalid")
        #expect(written.requestedAt == HubFixture.now)

        let files = fixture.requestFiles()
        #expect(files == ["\(written.requestId).json"])
        #expect(!files.contains { $0.hasPrefix(".") })
        let file = fixture.requests.appendingPathComponent(files[0])
        let directoryMode = try FileManager.default.attributesOfItem(atPath: fixture.requests.path)[.posixPermissions]
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((directoryMode as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(((fileAttributes[.size] as? NSNumber)?.intValue ?? .max) <= 4096)
        let body = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(body["schemaVersion"] as? Int == 1)
        #expect(body["provider"] as? String == "openai")
        #expect(body["requestId"] as? String == written.requestId)
        #expect(body["targetIdSuffix"] as? String == "3c4d")

        let object = try jsonObject(result.payload)
        #expect(object["provider"] as? String == "codex")
        #expect(object["error"] is NSNull)
        #expect(Set(try #require(object["request"] as? [String: Any]).keys) == [
            "requestId", "targetIdSuffix", "targetEmail", "requestedAt",
        ])
    }

    @Test
    func `refused switches write nothing and report the reader case`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        let env = HubFixture.environment()

        try fixture.writeSnapshot()
        let active = await CodexBarCLI.hubSwitch(
            self.request("1a2b", email: "a***e@example.invalid"), config: fixture.codexConfig(), environment: env)
        #expect(active.exitCode == .success)
        #expect(active.payload.outcome == "alreadyActive")
        #expect(active.payload.request == nil)

        let missing = await CodexBarCLI.hubSwitch(
            self.request(email: "z***z@example.invalid"), config: fixture.codexConfig(), environment: env)
        #expect(missing.exitCode == .failure)
        #expect(missing.payload.outcome == nil)
        #expect(missing.payload.error?.code == "accountNotFound")

        let paused = await CodexBarCLI.hubSwitch(
            self.request("5e6f", email: "c***c@example.invalid"), config: fixture.codexConfig(), environment: env)
        #expect(paused.payload.error?.code == "switchNotAllowed")

        try fixture.writeSnapshot(switchable: false, switchReason: "Switched only on the hub")
        let locked = await CodexBarCLI.hubSwitch(self.request(), config: fixture.codexConfig(), environment: env)
        #expect(locked.exitCode == .failure)
        #expect(locked.payload.error == HubErrorPayload(code: "switchNotAllowed", message: "Switched only on the hub"))

        try fixture.writeSnapshot(updatedAt: HubFixture.now.addingTimeInterval(-600))
        let stale = await CodexBarCLI.hubSwitch(self.request(), config: fixture.codexConfig(), environment: env)
        #expect(stale.payload.error?.code == "snapshotNotCurrent")

        let notConfigured = await CodexBarCLI.hubSwitch(
            self.request(), config: fixture.codexConfig(enabled: false), environment: env)
        #expect(notConfigured.exitCode == .failure)
        #expect(notConfigured.payload.error?.code == "notConfigured")

        try FileManager.default.removeItem(at: fixture.snapshot)
        let noSource = await CodexBarCLI.hubSwitch(self.request(), config: fixture.codexConfig(), environment: env)
        #expect(noSource.exitCode == .failure)
        #expect(noSource.payload.error?.code == "noHubSource")

        #expect(fixture.requestFiles().isEmpty)
    }

    @Test
    func `on the hub itself the live list is read and switched with a synthetic ocx`() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanup() }
        let list = fixture.root.appendingPathComponent("ocx-list.json")
        try """
        {"accounts": [
          {"provider": "openai", "id": "acct-live-1111", "email": "a***e@example.invalid", "active": true},
          {"provider": "openai", "id": "acct-live-3c4d", "email": "b***b@example.invalid", "active": false}
        ]}
        """.write(to: list, atomically: true, encoding: .utf8)
        let executable = fixture.root.appendingPathComponent("ocx")
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$0.calls"
        case "$1 $2" in
          "account list") cat '\(list.path)' ;;
          "account use") printf '{"ok":true,"provider":"openai","activeId":"%s"}\\n' "$4" ;;
          *) exit 64 ;;
        esac
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let config = fixture.codexConfig(executable: executable.path)
        let env = HubFixture.environment(role: .hub)

        let accounts = await CodexBarCLI.hubAccounts(provider: .codex, pending: nil, config: config, environment: env)
        #expect(accounts.exitCode == .success)
        #expect(accounts.payload.origin == "hubLocal")
        #expect(accounts.payload.updatedAt == nil)
        #expect(accounts.payload.stale == false)
        let text = try #require(CodexBarCLI.encodeJSON(accounts.payload, pretty: false))
        #expect(!text.contains("acct-live"))

        let suffix = try #require(accounts.payload.accounts.last?.idSuffix)
        let switched = await CodexBarCLI.hubSwitch(
            HubSwitchCLIRequest(provider: .codex, idSuffix: suffix, email: "b***b@example.invalid"),
            config: config, environment: env)
        #expect(switched.exitCode == .success)
        #expect(switched.payload.outcome == "switched")
        #expect(switched.payload.request == nil)
        #expect(fixture.requestFiles().isEmpty)
        let calls = try String(contentsOfFile: executable.path + ".calls", encoding: .utf8)
        #expect(calls.split(separator: "\n").last == "account use openai acct-live-3c4d --json")
    }
}
