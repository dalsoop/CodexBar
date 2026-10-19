import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Codex and Grok cards that read an opencodex hub pool, and the Claude adapter's switch request on a
/// Mac that is not the hub.
@MainActor
struct OpenCodexHubCardTests {
    private static let snapshot = #"""
    {"app": "opencodex-hub-accounts", "updatedAt": "2026-10-19T03:15:00Z", "state": {
      "schemaVersion": 2, "hub": "hub-mac", "fetchedAt": "2026-10-19T03:14:58Z",
      "accounts": [],
      "providers": {
        "anthropic": {"switchable": true, "switchReason": null, "accounts": [
          {"idSuffix": "aaaa", "label": "a***a@example.invalid", "email": "a***a@example.invalid", "active": true,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"fiveHourPercent": 4, "weeklyPercent": 10, "updatedAt": 1792386686100}},
          {"idSuffix": "bbbb", "label": "b***b@example.invalid", "email": "b***b@example.invalid", "active": false,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"fiveHourPercent": 0, "weeklyPercent": 90, "updatedAt": 1792386686100}}
        ]},
        "openai": {"switchable": false, "switchReason": "Switched only on hub-mac.", "accounts": [
          {"idSuffix": "cccc", "label": "pro", "email": "a***a@example.invalid", "active": true, "paused": false,
           "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"weeklyPercent": 51, "weeklyResetAt": 1792889538000, "updatedAt": 1792386000000}},
          {"idSuffix": "dddd", "label": "go", "email": "b***b@example.invalid", "active": false, "paused": false,
           "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"monthlyPercent": 0, "updatedAt": 1792386000000}}
        ]},
        "xai": {"switchable": true, "switchReason": null, "accounts": [
          {"idSuffix": "eeee", "label": "a***a@example.invalid", "email": "a***a@example.invalid", "active": true,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"weeklyPercent": 43, "updatedAt": 1792386505020}},
          {"idSuffix": "ffff", "label": "b***b@example.invalid", "email": "b***b@example.invalid", "active": false,
           "paused": false, "needsReauth": false, "health": "Healthy", "quotaUnavailable": false,
           "quota": {"weeklyPercent": 0, "updatedAt": 1792386505020}}
        ]}
      },
      "lastRequests": []
    }}
    """#

    private func makeFixture() throws -> (CodexWorkspacesNavigationFixture, String, String) {
        let fixture = try CodexWorkspacesNavigationFixture(userDefaults: InMemoryUserDefaults())
        let snapshotURL = fixture.files.root.appendingPathComponent("opencodex-hub-accounts.json")
        try Self.snapshot.write(to: snapshotURL, atomically: true, encoding: .utf8)
        // A linked client: ocx answers without a list.
        let executable = fixture.files.root.appendingPathComponent("ocx")
        try "#!/bin/sh\necho 'Error: not_found' >&2\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (fixture, executable.path, snapshotURL.path)
    }

    private func requestFiles(_ fixture: CodexWorkspacesNavigationFixture) -> [String] {
        let directory = fixture.files.root.appendingPathComponent("opencodex-hub-requests")
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    @Test
    func `hub source is off by default and only Codex and Grok cards read it through these settings`() throws {
        let (fixture, _, _) = try self.makeFixture()
        defer { fixture.cleanup() }
        #expect(!fixture.settings.codexOpenCodexHubEnabled)
        #expect(!fixture.store.usesOpenCodexHub(for: .codex))
        fixture.settings.codexOpenCodexHubEnabled = true
        fixture.settings.setOpenCodexHubEnabled(true, for: .claude)
        #expect(fixture.store.usesOpenCodexHub(for: .codex))
        #expect(!fixture.store.usesOpenCodexHub(for: .grok))
        #expect(!fixture.store.usesOpenCodexHub(for: .claude))
    }

    @Test
    func `codex card renders the active hub account and gates switching when the pool is hub only`() async throws {
        let (fixture, executable, snapshotPath) = try self.makeFixture()
        defer { fixture.cleanup() }
        fixture.settings.codexOpenCodexHubEnabled = true
        fixture.settings.codexOpenCodexHubExecutablePath = executable
        fixture.settings.codexOpenCodexHubSnapshotPath = snapshotPath
        fixture.store.errors[UsageProvider.codex.instanceID] =
            "Codex is configured for a custom provider; ChatGPT rate limits are unavailable."

        await fixture.store.refreshOpenCodexHubCard(.codex, generation: nil)

        let snapshot = try #require(fixture.store.snapshots[UsageProvider.codex.instanceID])
        #expect(snapshot.primary?.usedPercent == 51)
        #expect(snapshot.primary?.windowMinutes == 7 * 24 * 60)
        #expect(fixture.store.errors[UsageProvider.codex.instanceID] == nil)
        #expect(fixture.store.lastSourceLabels[UsageProvider.codex.instanceID] == "opencodex")
        let state = try #require(fixture.store.openCodexHubCardState(for: .codex))
        let pool = try #require(state.pool)
        #expect(!pool.switchable)
        #expect(OpenCodexHubPresentation.poolNotices(pool, now: pool.snapshotUpdatedAt ?? .now)
            == [L("Accounts are managed on the hub %@.", "hub-mac"), "Switched only on hub-mac."])
        #expect(OpenCodexHubPresentation.poolNotices(pool, now: .distantFuture).count == 3)

        let target = pool.accounts[1]
        fixture.store.switchOpenCodexHubAccount(target, provider: .codex, label: "b")
        #expect(fixture.store.openCodexHubCardState(for: .codex)?.isSwitching == false)
        #expect(self.requestFiles(fixture).isEmpty)
    }

    @Test
    func `grok card asks the hub to switch and waits for the next snapshot`() async throws {
        let (fixture, executable, snapshotPath) = try self.makeFixture()
        defer {
            fixture.store.clearOpenCodexHubCardState(.grok)
            fixture.cleanup()
        }
        fixture.settings.grokOpenCodexHubEnabled = true
        fixture.settings.grokOpenCodexHubExecutablePath = executable
        fixture.settings.grokOpenCodexHubSnapshotPath = snapshotPath
        await fixture.store.refreshOpenCodexHubCard(.grok, generation: nil)
        let pool = try #require(fixture.store.openCodexHubCardState(for: .grok)?.pool)
        let target = pool.accounts[1]
        #expect(pool.canSwitch(to: target))

        fixture.store._test_providerRefreshOverride = { _ in }
        defer { fixture.store._test_providerRefreshOverride = nil }
        var progress = 0
        fixture.store.switchOpenCodexHubAccount(target, provider: .grok, label: "b***b") { progress += 1 }
        let deadline = Date().addingTimeInterval(10)
        while progress < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(progress == 2)
        let status = try #require(fixture.store.openCodexHubCardState(for: .grok)?.switchStatus)
        #expect(status.isPending)
        #expect(status.menuLines == [L("The hub is switching accounts…")])
        let files = self.requestFiles(fixture)
        #expect(files.count == 1)
        let requestID = try #require(files.first?.replacingOccurrences(of: ".json", with: ""))

        // The hub's next snapshot reports the request as done.
        let done = Self.snapshot.replacingOccurrences(
            of: #""lastRequests": []"#,
            with: #""lastRequests": [{"requestId": "\#(requestID)", "from": "client", "provider": "xai", "#
                + #""target": {"idSuffix": "ffff", "email": "b***b@example.invalid"}, "result": "done", "#
                + #""code": "switched", "reason": null, "at": "2026-10-19T03:16:00Z"}]"#)
        try done.write(toFile: snapshotPath, atomically: true, encoding: .utf8)
        await fixture.store.refreshOpenCodexHubCard(.grok, generation: nil)
        let resolved = try #require(fixture.store.openCodexHubCardState(for: .grok)?.switchStatus)
        #expect(!resolved.isPending)
        #expect(resolved.menuLines == [L("The hub switched to %@.", "b***b")])
    }

    @Test
    func `claude adapter on a linked Mac writes a request instead of switching`() async throws {
        let (fixture, executable, snapshotPath) = try self.makeFixture()
        defer {
            fixture.store.clearClaudeSwapAccountState()
            fixture.cleanup()
        }
        let metadata = try #require(ProviderRegistry.shared.metadata[.claude])
        fixture.settings.setProviderEnabled(provider: .claude, metadata: metadata, enabled: true)
        fixture.settings.claudeSwapExecutablePath = executable
        fixture.settings.claudeSwapSource = .openCodex
        fixture.settings.claudeSwapOpenCodexSnapshotPath = snapshotPath
        fixture.settings.claudeSwapEnabled = true
        let result = try OpenCodexAccountReader.readSnapshot(path: snapshotPath)
        fixture.store.claudeSwapRemoteCopy = result.list.remoteCopy
        fixture.store.claudeSwapAccountSnapshots = ClaudeSwapAccountProjection.accountSnapshots(
            from: result.list,
            source: .openCodex)
        let target = try #require(fixture.store.claudeSwapAccountSnapshots.first { !$0.isActive })
        #expect(target.canActivate)

        fixture.store.switchClaudeSwapAccount(target.id)
        let task = try #require(fixture.store.claudeSwapTransientState.task)
        await task.value

        #expect(fixture.store.claudeSwapTransientState.lastError == nil)
        #expect(fixture.store.claudeSwapHubSwitchStatus.isPending)
        #expect(self.requestFiles(fixture).count == 1)
    }
}
