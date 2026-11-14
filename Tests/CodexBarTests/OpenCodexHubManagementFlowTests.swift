import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OpenCodexHubManagementFlowTests {
    @Test
    func `a browser handoff is deduplicated and does not claim authentication success`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        var continuation: CheckedContinuation<URL, any Error>?
        var resolutions = 0
        var opened: [URL] = []
        let first = Task { @MainActor in
            await store.openHubAccountManagement(
                .codex,
                resolveURL: { _, provider in
                    #expect(provider == .openai)
                    resolutions += 1
                    return try await withCheckedThrowingContinuation { continuation = $0 }
                },
                openURL: { opened.append($0); return true })
        }
        while continuation == nil {
            await Task.yield()
        }
        #expect(store.openCodexHubManagementState(for: .codex)?.phase == .opening)
        await store.openHubAccountManagement(
            .codex,
            resolveURL: { _, _ in
                resolutions += 1
                return self.url
            },
            openURL: { opened.append($0); return true })
        #expect(resolutions == 1)
        continuation?.resume(returning: self.url)
        await first.value
        #expect(opened == [self.url])
        #expect(store.openCodexHubManagementState(for: .codex)?.phase == .awaitingReturn)
    }

    @Test(arguments: [false, true])
    func `changing the source or cancelling while opening never launches a late browser`(cancel: Bool) async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        var continuation: CheckedContinuation<URL, any Error>?
        var opens = 0
        let task = Task { @MainActor in
            await fixture.store.openHubAccountManagement(
                .codex,
                resolveURL: { _, _ in
                    try await withCheckedThrowingContinuation { continuation = $0 }
                },
                openURL: { _ in opens += 1; return true })
        }
        while continuation == nil {
            await Task.yield()
        }
        if cancel {
            task.cancel()
        } else {
            let previousPath = fixture.settings.codexOpenCodexHubSnapshotPath
            fixture.settings.codexOpenCodexHubSnapshotPath = "/synthetic/new-connection.json"
            fixture.settings.codexOpenCodexHubSnapshotPath = previousPath
        }
        continuation?.resume(returning: self.url)
        await task.value
        #expect(opens == 0)
        #expect(fixture.store.openCodexHubManagementState(for: .codex) == nil)
    }

    @Test
    func `cancelled destination resolution does not display an error or open the browser`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        let message = await fixture.store.openHubAccountManagement(
            .codex,
            resolveURL: { _, _ in
                throw CancellationError()
            },
            openURL: { _ in Issue.record("Cancellation must not open a browser"); return false })
        #expect(message == nil)
        #expect(fixture.store.openCodexHubManagementState(for: .codex) == nil)
    }

    @Test
    func `browser and connection errors have localized closed messages`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        await CodexBarLocalizationOverride.$appLanguage.withValue("ko") {
            let transportError = await fixture.store.openHubAccountManagement(
                .codex,
                resolveURL: { _, _ in
                    throw NSError(domain: "private-output-token", code: 1)
                },
                openURL: { _ in Issue.record("An unavailable destination must not open"); return false })
            #expect(transportError == L("Could not reach the account manager. Check the hub connection and try again."))
            #expect(transportError?.contains("private-output-token") == false)
            let browserError = await fixture.store.openHubAccountManagement(
                .codex,
                resolveURL: { _, _ in self.url },
                openURL: { _ in false })
            #expect(browserError == L("Could not open your browser. Try opening the account manager again."))
        }
    }

    @Test(arguments: [false, true])
    func `returning checks the list once and distinguishes an outdated copy`(stale: Bool) async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        var reads = 0
        store._test_openCodexHubRefreshOverride = { provider in
            reads += 1
            store.applyOpenCodexHubPool(self.pool(stale: stale), provider: provider)
        }
        await store.openHubAccountManagement(.codex, resolveURL: { _, _ in self.url }, openURL: { _ in true })
        store.checkHubAccountsAfterBrowserReturn()
        store.checkHubAccountsAfterBrowserReturn()
        while store.openCodexHubManagementState(for: .codex)?.phase == .awaitingReturn
            || store.openCodexHubManagementState(for: .codex)?.phase == .checking
        {
            await Task.yield()
        }
        #expect(reads == 1)
        #expect(store.openCodexHubManagementState(for: .codex)?.phase == (stale ? .waitingForSync : .checked))
        store.checkHubAccountsAfterBrowserReturn()
        await Task.yield()
        #expect(reads == 1)
    }

    @Test
    func `a successful native link read checks membership without waiting for snapshot sync`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let accounts = (0..<3).map { index in
            OpenCodexHubAccount(
                idSuffix: String(format: "%04x", index),
                label: nil,
                email: "a\(index)***e@example.com",
                isActive: index == 0,
                quota: .init())
        }
        var reads = 0
        store._test_openCodexHubRefreshOverride = { provider in
            reads += 1
            store.applyOpenCodexHubPool(OpenCodexHubPool(
                provider: .openai,
                accounts: accounts,
                switchable: false,
                origin: .linkedCopy(hubName: "fixture")), provider: provider)
        }
        await store.openHubAccountManagement(.codex, resolveURL: { _, _ in self.url }, openURL: { _ in true })
        await store.refreshHubAccountList(.codex)
        let management = try #require(store.openCodexHubManagementState(for: .codex))
        let pool = try #require(store.openCodexHubCardState(for: .codex)?.pool)
        #expect(reads == 1)
        #expect(management.phase == .checked)
        #expect(!management.needsAttention)
        #expect(pool.accounts.count == 3)
        #expect(pool.isLinkedCopy)
        #expect(!pool.switchable)
        #expect(pool.accounts.allSatisfy { $0.quota.isEmpty && !pool.canSwitch(to: $0) })
        #expect(pool.snapshotUpdatedAt == nil)
        #expect(management.message == L("Account list checked. Confirm that your account appears; " +
                "opening the browser does not complete sign-in."))
    }

    @Test
    func `failed list refresh does not ask the user to repeat a possibly successful login`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        fixture.store._test_openCodexHubRefreshOverride = { _ in }
        await fixture.store.openHubAccountManagement(.codex, resolveURL: { _, _ in self.url }, openURL: { _ in true })
        await fixture.store.refreshHubAccountList(.codex)
        let message = try #require(fixture.store.openCodexHubManagementState(for: .codex)?.message)
        #expect(message == L("Could not refresh the account list. " +
                "Your browser sign-in may still have succeeded. Try refreshing again."))
    }

    @Test
    func `an unavailable hub never turns an account list check into a native provider fetch`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        fixture.settings.codexOpenCodexHubExecutablePath = fixture.files.root.appendingPathComponent("missing-ocx").path
        fixture.settings.codexOpenCodexHubSnapshotPath = fixture.files.root.appendingPathComponent("missing.json").path
        await fixture.store.refreshHubAccountList(.codex)
        #expect(fixture.store.lastFetchAttempts[UsageProvider.codex.instanceID] == nil)
        #expect(fixture.store.openCodexHubCardState(for: .codex) == nil)
        #expect(fixture.store.openCodexHubManagementState(for: .codex)?.needsAttention == true)
    }

    @Test
    func `source times and explicit used percentages stay honest for cached lists`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let stale = self.pool(stale: true)
            #expect(OpenCodexHubPresentation.listStatus(stale, now: now).contains(L("The hub list is out of date.")))
            let linked = OpenCodexHubPool(
                provider: .openai,
                accounts: [],
                switchable: false,
                origin: .linkedCopy(hubName: "fixture"))
            #expect(OpenCodexHubPresentation.listStatus(linked).contains("last hub update is unknown"))
            let quota = OpenCodexHubQuota(monthly: .init(usedPercent: 0, resetsAt: nil))
            #expect(OpenCodexHubPresentation.quotaSummary(quota) == "Monthly: 0% used")
            #expect(OpenCodexHubPresentation.quotaSummary(.init()) == nil)
        }
    }

    private var url: URL {
        URL(string: "https://hub.example/#codex-set")!
    }

    @Test
    func `management settings reject credential input and invalidate an in flight browser destination`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        #expect(fixture.settings.setOpenCodexHubManagementOrigin("https://management.example", for: .codex))
        #expect(!fixture.settings.setOpenCodexHubManagementOrigin("https://user:private@hub.example", for: .codex))
        #expect(fixture.settings.openCodexHubManagementOrigin(for: .codex) == "https://management.example")
        var continuation: CheckedContinuation<URL, any Error>?
        var opens = 0
        let task = Task { @MainActor in
            await fixture.store.openHubAccountManagement(
                .codex,
                resolveURL: { _, _ in try await withCheckedThrowingContinuation { continuation = $0 } },
                openURL: { _ in opens += 1; return true })
        }
        while continuation == nil {
            await Task.yield()
        }
        #expect(fixture.settings.setOpenCodexHubManagementOrigin("https://other.example", for: .codex))
        #expect(fixture.settings.setOpenCodexHubManagementOrigin("https://management.example", for: .codex))
        continuation?.resume(returning: self.url)
        await task.value
        #expect(opens == 0)
    }

    @Test
    func `a real shaped link status uses the saved management origin without opening the tunnel`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        let executable = fixture.files.root.appendingPathComponent("ocx")
        let status = #"""
        {
          "schemaVersion": 1,
          "runtimeRole": "client",
          "proxy": {
            "running": true
          },
          "connection": {
            "state": "connected",
            "transport": "link",
            "managementUrl": "http://127.0.0.1:65130"
          }
        }
        """#
        try "#!/bin/sh\nprintf '%s' '\(status)'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        fixture.settings.codexOpenCodexHubExecutablePath = executable.path
        var opened: [URL] = []
        #expect(fixture.settings.setOpenCodexHubManagementOrigin("https://management.example", for: .codex))
        let result = await fixture.store.openHubAccountManagement(.codex, openURL: { opened.append($0); return true })
        #expect(result == nil)
        #expect(opened.map(\.absoluteString) == ["https://management.example/#codex-set"])
        #expect(fixture.settings.setOpenCodexHubManagementOrigin("", for: .codex))
        let message = await fixture.store.openHubAccountManagement(.codex, openURL: { opened.append($0); return true })
        let addressRequired = L("Set the hub's HTTPS management address in Settings. " +
            "The local data tunnel cannot open the account manager.")
        #expect(message == addressRequired)
        // Without an address the local role picks the guidance, even from a stopped runtime or a failing exit.
        let unreachable = L("Could not reach the account manager. Check the hub connection and try again.")
        let cases: [(status: String, exitCode: Int, expected: String)] = [
            (#"{"schemaVersion":1,"runtimeRole":"hub","proxy":{"running":false}}"#, 0, addressRequired),
            (#"{"schemaVersion":1,"runtimeRole":"hub","proxy":{"running":false}}"#, 1, addressRequired),
            (#"{"schemaVersion":1,"runtimeRole":"client","proxy":{"running":true}}"#, 0, addressRequired),
            (#"{"schemaVersion":1,"runtimeRole":"standalone","proxy":{"running":false}}"#, 0, unreachable),
            ("not json", 1, unreachable),
        ]
        for (status, exitCode, expected) in cases {
            try "#!/bin/sh\nprintf '%s' '\(status)'\nexit \(exitCode)\n"
                .write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let result = await fixture.store.openHubAccountManagement(.codex, openURL: { _ in true })
            #expect(result == expected)
        }
        fixture.settings.codexOpenCodexHubExecutablePath = fixture.files.root.appendingPathComponent("missing-ocx").path
        let missing = await fixture.store.openHubAccountManagement(.codex, openURL: { opened.append($0); return true })
        #expect(missing == addressRequired)
        #expect(opened.count == 1)
    }

    @Test
    func `management origin rejects invalid input without changing a valid override`() throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        let provider = UsageProvider.codex
        let settings = fixture.settings
        settings.setOpenCodexHubEnabled(true, for: provider)
        settings.setOpenCodexHubSnapshotPath("/synthetic/accounts.json", for: provider)
        #expect(settings.setOpenCodexHubManagementOrigin(" https://management.example/ \n", for: provider))
        let revision = settings.providerConfigRevision(for: provider)
        let saved = settings.openCodexHubManagementOrigin(for: provider)
        // The full URL rejection matrix belongs to Core; here verify settings are not overwritten.
        for invalid in ["\"https://other.example\"", "''"] {
            #expect(!settings.setOpenCodexHubManagementOrigin(invalid, for: provider))
            #expect(settings.openCodexHubManagementOrigin(for: provider) == saved)
            #expect(settings.providerConfigRevision(for: provider) == revision)
        }
        let data = try JSONEncoder().encode(settings.configSnapshot)
        let roundTrip = try JSONDecoder().decode(CodexBarConfig.self, from: data)
        let entry = try #require(roundTrip.providerConfig(for: provider.instanceID))
        #expect(entry.sanitizedOpenCodexHubManagementOrigin == saved)
        #expect(entry.resolvedOpenCodexHubEnabled)
        #expect(entry.sanitizedOpenCodexHubSnapshotPath == "/synthetic/accounts.json")
        #expect(settings.setOpenCodexHubManagementOrigin(" \n\t", for: provider))
        #expect(settings.configSnapshot.providerConfig(for: provider.instanceID)?.openCodexHubManagementOrigin == nil)
        #expect(settings.openCodexHubManagementOrigin(for: provider) == (OpenCodexHubDefaults.managementOrigin ?? ""))
        #expect(settings.openCodexHubEnabled(for: provider))
        #expect(settings.openCodexHubSnapshotPath(for: provider) == "/synthetic/accounts.json")
        // Saving the packaged default (compared canonically) clears the override instead of pinning a copy.
        let packaged = "https://central.example"
        func stored() -> String? {
            settings.configSnapshot.providerConfig(for: provider.instanceID)?.openCodexHubManagementOrigin
        }
        for variant in [packaged, "HTTPS://Central.Example:443/", " https://central.example/\n"] {
            #expect(settings.setOpenCodexHubManagementOrigin(
                "https://other.example", for: provider, packagedDefault: packaged))
            #expect(stored() == "https://other.example")
            #expect(settings.setOpenCodexHubManagementOrigin(variant, for: provider, packagedDefault: packaged))
            #expect(stored() == nil)
        }
        #expect(settings.setOpenCodexHubManagementOrigin(
            "https://central.example:8443", for: provider, packagedDefault: packaged))
        #expect(stored() == "https://central.example:8443")
        #expect(!settings.setOpenCodexHubManagementOrigin(
            "http://central.example", for: provider, packagedDefault: packaged))
        #expect(stored() == "https://central.example:8443")
        #expect(settings.setOpenCodexHubManagementOrigin("", for: provider, packagedDefault: packaged))
        #expect(stored() == nil)
    }

    @Test
    func `saved invalid upper origins fail closed without opening a browser`() async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        let provider = UsageProvider.codex
        fixture.settings.setOpenCodexHubEnabled(true, for: provider)
        fixture.settings.setOpenCodexHubExecutablePath(
            fixture.files.root.appendingPathComponent("missing-ocx").path, for: provider)
        for invalid in ["\"https://management.example\"", "''"] {
            fixture.settings.updateProviderConfig(provider: provider) { $0.openCodexHubManagementOrigin = invalid }
            var opens = 0
            var nativeCalls = 0
            let message = await fixture.store.performProviderAccountAction(
                provider,
                openURL: { _ in opens += 1; return true },
                nativeAction: { nativeCalls += 1 })
            #expect(opens == 0)
            #expect(nativeCalls == 0)
            #expect(message == L("Set the hub's HTTPS management address in Settings. " +
                    "The local data tunnel cannot open the account manager."))
            #expect(fixture.store.openCodexHubManagementState(for: provider)?.needsAttention == true)
        }
    }

    @Test(arguments: [UsageProvider.codex, .claude, .grok], [false, true])
    func `provider account dispatch selects exactly one central browser or native action`(
        provider: UsageProvider, enabled: Bool) async throws
    {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        fixture.settings.setOpenCodexHubEnabled(enabled, for: provider)
        fixture.settings.setOpenCodexHubExecutablePath(
            fixture.files.root.appendingPathComponent("missing-ocx").path, for: provider)
        #expect(fixture.settings.setOpenCodexHubManagementOrigin("https://management.example", for: provider))
        var opened: [URL] = []
        var nativeCalls = 0
        let message = await fixture.store.performProviderAccountAction(
            provider,
            openURL: { opened.append($0); return true },
            nativeAction: { nativeCalls += 1 })
        let fragment = switch provider {
        case .codex: "codex-set"
        case .claude: "providers?provider=anthropic&tab=accounts"
        default: "providers?provider=xai&tab=accounts"
        }
        #expect(message == nil)
        #expect(opened.map(\.absoluteString) == (enabled ? ["https://management.example/#\(fragment)"] : []))
        #expect(nativeCalls == (enabled ? 0 : 1))
        #expect(fixture.store.openCodexHubManagementState(for: provider)?.phase == (enabled ? .awaitingReturn : nil))
    }

    @Test(arguments: [false, true])
    func `Codex settings add and re login hand off without invoking native runners`(reauthenticate: Bool) async throws {
        let fixture = try self.fixture()
        defer { fixture.cleanup() }
        #expect(fixture.settings.setOpenCodexHubManagementOrigin("https://management.example", for: .codex))
        let runner = ManagementFlowNativeRunner()
        let coordinator = ManagedCodexAccountCoordinator(service: ManagedCodexAccountService(
            store: FileManagedCodexAccountStore(fileURL: fixture.files.root.appendingPathComponent("accounts.json")),
            homeFactory: ManagedCodexHomeFactory(root: fixture.files.root.appendingPathComponent("managed")),
            loginRunner: runner,
            identityReader: ManagementFlowIdentityReader()))
        var opened: [URL] = []
        var nativeCalls = 0
        let pane = ProvidersPane(
            settings: fixture.settings,
            store: fixture.store,
            managedCodexAccountCoordinator: coordinator,
            codexAmbientLoginRunner: runner,
            runProviderLoginFlow: { provider in
                await fixture.store.performProviderAccountAction(
                    provider,
                    openURL: { opened.append($0); return true },
                    nativeAction: { nativeCalls += 1 })
            })
        if reauthenticate {
            await pane.reauthenticateCodexAccount(CodexVisibleAccount(
                id: "synthetic",
                email: "account@example.invalid",
                storedAccountID: nil,
                selectionSource: .liveSystem,
                isActive: true,
                isLive: true,
                canReauthenticate: true,
                canRemove: false))
        } else {
            await pane.addManagedCodexAccount()
        }
        #expect(opened.map(\.absoluteString) == ["https://management.example/#codex-set"])
        #expect(nativeCalls == 0)
        #expect(await runner.calls == 0)
        #expect(fixture.store.openCodexHubManagementState(for: .codex)?.phase == .awaitingReturn)
    }

    private func fixture() throws -> CodexWorkspacesNavigationFixture {
        let fixture = try CodexWorkspacesNavigationFixture(userDefaults: InMemoryUserDefaults())
        fixture.settings.codexOpenCodexHubEnabled = true
        return fixture
    }

    private func pool(stale: Bool) -> OpenCodexHubPool {
        OpenCodexHubPool(
            provider: .openai,
            accounts: [],
            switchable: false,
            origin: stale ? .snapshot(hubName: "fixture", updatedAt: Date(timeIntervalSince1970: 0)) :
                .hubLocal)
    }
}

private actor ManagementFlowNativeRunner: CodexAmbientLoginRunning, ManagedCodexLoginRunning {
    private(set) var calls = 0

    func run(timeout _: TimeInterval) async -> CLILoginRunner.Result {
        self.calls += 1
        return .init(outcome: .cancelled, output: "")
    }

    func run(homePath _: String, timeout _: TimeInterval) async -> CLILoginRunner.Result {
        self.calls += 1
        return .init(outcome: .cancelled, output: "")
    }
}

private struct ManagementFlowIdentityReader: ManagedCodexIdentityReading {
    func loadAccountIdentity(homePath _: String) throws -> CodexAuthBackedAccount {
        Issue.record("Hub management must not read a native identity")
        throw ManagedCodexAccountServiceError.missingEmail
    }
}
