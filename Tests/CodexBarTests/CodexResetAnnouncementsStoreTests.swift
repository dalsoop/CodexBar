import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct CodexResetAnnouncementsStoreTests {
    private static let now = Date(timeIntervalSince1970: 1_792_774_800)

    @Test
    func `settings default on and invalid addresses never replace the saved URL`() {
        let settings = testSettingsStore(
            suiteName: "CodexResetAnnouncementsStoreTests-settings",
            userDefaults: InMemoryUserDefaults())
        #expect(settings.codexResetAnnouncementsEnabled)
        #expect(settings.setCodexResetAnnouncementsProviderURL("https://tokenusage.dev/api/resets"))
        #expect(!settings.setCodexResetAnnouncementsProviderURL("https://name:secret@example.com/feed"))
        #expect(settings.codexResetAnnouncementsProviderURL == "https://tokenusage.dev/api/resets")
        #expect(settings.setCodexResetAnnouncementsProviderURL("  "))
        #expect(settings.codexResetAnnouncementsProviderURL == CodexResetAnnouncements.defaultProviderURL)
    }

    @Test
    func `provider throttling applies to manual refreshes too`() async throws {
        let client = try ResetNewsQueueClient(results: [.failure(.retryLater(3600)), .success(Self.snapshot())])
        let store = CodexResetAnnouncementsStore(client: client)
        store.configure(
            enabled: true,
            address: CodexResetAnnouncements.defaultProviderURL,
            automaticallyPoll: false)
        await store.refresh(now: Self.now)
        await store.refresh(now: Self.now.addingTimeInterval(300))
        #expect(await client.calls == 1)
        #expect(store.error == .retryLater(3600))
        await store.refresh(now: Self.now.addingTimeInterval(3600))
        #expect(await client.calls == 2)
        #expect(store.error == nil)
    }

    @Test
    func `a late response from the previous provider cannot replace the new provider`() async throws {
        let client = ResetNewsSuspendedClient()
        let store = CodexResetAnnouncementsStore(client: client)
        let first = "https://first.invalid/feed"
        let second = "https://second.invalid/feed"
        store.configure(
            enabled: true,
            address: first,
            automaticallyPoll: false)
        let oldRequest = Task { await store.refresh(now: Self.now) }
        await client.waitForRequest(first)
        store.configure(
            enabled: true,
            address: second,
            automaticallyPoll: false)
        let newRequest = Task { await store.refresh(now: Self.now) }
        await client.waitForRequest(second)
        try await client.complete(
            second,
            value: Self.snapshot(id: "new-provider"))
        await newRequest.value
        try await client.complete(
            first,
            value: Self.snapshot(id: "old-provider"))
        await oldRequest.value
        #expect(store.snapshot?.latest?.id == "new-provider")
        #expect(store.providerURL?.host == "second.invalid")
        #expect(!store.isRefreshing)
    }

    @Test
    func `turning off clears reports and ignores a pending request`() async throws {
        let client = ResetNewsSuspendedClient()
        let store = CodexResetAnnouncementsStore(client: client)
        let address = CodexResetAnnouncements.defaultProviderURL
        store.configure(
            enabled: true,
            address: address,
            automaticallyPoll: false)
        let request = Task { await store.refresh(now: Self.now) }
        await client.waitForRequest(address)
        store.configure(
            enabled: false,
            address: address)
        try await client.complete(
            address,
            value: Self.snapshot())
        await request.value
        #expect(store.snapshot == nil)
        #expect(CodexResetAnnouncementsPresentation.make(
            store: store,
            now: Self.now) == nil)
    }

    @Test
    func `failed refresh retains the last report and marks it stale`() async throws {
        let client = try ResetNewsQueueClient(results: [.success(Self.snapshot()), .failure(.unavailable)])
        let store = CodexResetAnnouncementsStore(client: client)
        store.configure(
            enabled: true,
            address: CodexResetAnnouncements.defaultProviderURL,
            automaticallyPoll: false)
        await store.refresh(now: Self.now)
        await store.refresh(now: Self.now.addingTimeInterval(300))
        let presentation = try #require(CodexResetAnnouncementsPresentation.make(
            store: store,
            now: Self.now))
        #expect(presentation.latest != nil)
        #expect(presentation.isStale)
        #expect(store.snapshot != nil)
    }

    @Test
    func `expired outlooks disappear and passed schedules still await execution`() async throws {
        let client = try ResetNewsQueueClient(results: [.success(Self.snapshot())])
        let store = CodexResetAnnouncementsStore(client: client)
        store.configure(
            enabled: true,
            address: CodexResetAnnouncements.defaultProviderURL,
            automaticallyPoll: false)
        await store.refresh(now: Self.now)
        let view = try #require(CodexResetAnnouncementsPresentation.make(
            store: store,
            now: Self.now))
        #expect(!view.rows.contains { $0.id == "watch" })
        let scheduled = try #require(view.rows.first { $0.id == "scheduled" })
        #expect(scheduled.detail == nil)
        #expect(view.rows.first { $0.id == "scheduled" }?.title == L("reset_news_scheduled"))
    }

    @Test
    func `the newest reset shows elapsed time, its cycle, and one line of the post`() async throws {
        let store = try CodexResetAnnouncementsStore(
            client: ResetNewsQueueClient(results: [.success(Self.snapshot())]))
        store.configure(
            enabled: true,
            address: CodexResetAnnouncements.defaultProviderURL,
            automaticallyPoll: false)
        await store.refresh(now: Self.now)
        let presentation = try #require(CodexResetAnnouncementsPresentation.make(
            store: store,
            now: Self.now))
        let latest = try #require(presentation.latest)
        #expect(latest.elapsedText == String(format: L("%dd ago"), 1))
        #expect(latest.quote == "And it's done. See you tomorrow")
        #expect(latest.sourceURL?.absoluteString == "https://x.com/example/status/1")
        let cycle = try #require(presentation.cycle)
        #expect(abs(cycle.percent - 100.0 / 6) < 0.001)
        #expect(cycle.label == L("reset_news_average_cycle", "6"))
        #expect(!cycle.isOverdue)
        #expect(presentation.helpText.contains(L("reset_news_disclaimer")))
    }

    @Test
    func `the cycle fills and turns overdue after the average interval`() {
        let start = Self.now
        let early = CodexResetAnnouncementsPresentation.cycle(
            since: start,
            averageDays: 4,
            now: start.addingTimeInterval(86400))
        #expect(early.percent == 25)
        #expect(!early.isOverdue)
        let late = CodexResetAnnouncementsPresentation.cycle(
            since: start,
            averageDays: 4,
            now: start.addingTimeInterval(86400 * 9))
        #expect(late.percent == 100)
        #expect(late.isOverdue)
        #expect(CodexResetAnnouncementsPresentation.elapsedText(
            since: start,
            now: start.addingTimeInterval(20)) == String(format: L("%dm ago"), 1))
        #expect(CodexResetAnnouncementsPresentation.elapsedText(
            since: start,
            now: start.addingTimeInterval(3 * 3600)) == String(format: L("%dh ago"), 3))
        #expect(CodexResetAnnouncementsPresentation.quote("https://t.co/only \n ") == nil)
    }

    @Test
    func `the Codex setting exposes a saved provider URL and Korean labels`() async throws {
        let fixture = Self.fixture()
        fixture.settings.codexResetAnnouncementsEnabled = false
        let context = fixture.context
        let toggle = CodexResetAnnouncementsSettings.toggle(context: context)
        #expect(toggle.id == "codex-reset-news")
        #expect(L(
            toggle.title,
            language: "ko") == "Codex 리셋 소식")
        let field = try #require(toggle.inlineFields.first)
        field.binding.wrappedValue = "https://tokenusage.dev/api/resets"
        let action = try #require(field.actions.first)
        await action.perform()
        #expect(fixture.settings.codexResetAnnouncementsProviderURL == "https://tokenusage.dev/api/resets")
        #expect(!fixture.settings.codexResetAnnouncementsEnabled)
    }

    @Test
    func `render reset news with synthetic data when a screenshot directory is provided`() async throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_RESET_NEWS_SCREENSHOT_DIR"] else { return }
        let store = try CodexResetAnnouncementsStore(
            client: ResetNewsQueueClient(results: [.success(Self.snapshot())]))
        store.configure(
            enabled: true,
            address: CodexResetAnnouncements.defaultProviderURL,
            automaticallyPoll: false)
        await store.refresh(now: Self.now)
        let path = URL(
            fileURLWithPath: directory,
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: path,
            withIntermediateDirectories: true)
        for language in ["en", "ko"] {
            try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                let presentation = try #require(CodexResetAnnouncementsPresentation.make(
                    store: store,
                    now: Self.now))
                let view = CodexResetAnnouncementsContent(presentation: presentation)
                    .padding(16).frame(width: 340)
                    .background(Color(nsColor: .windowBackgroundColor))
                try Self.writePNG(
                    view,
                    to: path.appendingPathComponent("reset-news-\(language).png"))
                let fixture = Self.fixture()
                fixture.settings.codexResetAnnouncementsEnabled = true
                let settingsView = ProviderSettingsToggleRowView(
                    toggle: CodexResetAnnouncementsSettings.toggle(context: fixture.context))
                    .padding(20).frame(width: 560)
                    .background(Color(nsColor: .windowBackgroundColor))
                try Self.writePNG(
                    settingsView,
                    to: path.appendingPathComponent("reset-news-settings-\(language).png"))
            }
        }
    }

    private static func writePNG(_ view: some View, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        let size = hosting.fittingSize
        #expect(size.width > 0 && size.height > 0)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        bitmap.size = size
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        hosting.displayIgnoringOpacity(hosting.bounds, in: context)
        let png = try #require(bitmap.representation(
            using: .png,
            properties: [:]))
        try png.write(to: url)
    }

    private static func snapshot(id: String = "one") throws -> CodexResetAnnouncements {
        try CodexResetAnnouncements.decode(Data("""
        {"data":{"latest_reset":{"id":"\(id)","reset_type":"regular",
          "announced_at":"2026-10-22T17:00:00Z","text":"And it's done.\\nSee you tomorrow https://t.co/example",
          "source":{"url":"https://x.com/example/status/1"}},
          "scheduled_reset":{"id":"next","scheduled_for":"2026-10-23T16:00:00Z"},
          "active_watch":{"text":"Expired outlook","expires_at":"2026-10-22T17:00:00Z"},
          "stats":{"avg_interval_days":6}},
          "meta":{"generated_at":"2026-10-23T17:00:00Z"}}
        """.utf8))
    }

    private static func fixture() -> (
        settings: SettingsStore,
        context: ProviderSettingsContext)
    {
        let settings = testSettingsStore(
            suiteName: "CodexResetAnnouncementsStoreTests-descriptor",
            userDefaults: InMemoryUserDefaults())
        let root = URL(fileURLWithPath: "/tmp/reset-news-fixture-\(UUID().uuidString)")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: ["HOME": root.path]),
            browserDetection: BrowserDetection(
                homeDirectory: root.path,
                cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: ["HOME": root.path])
        let draft = ResetNewsDraft()
        let context = ProviderSettingsContext(
            provider: .codex,
            settings: settings,
            store: store,
            statusText: { draft.values[$0] },
            setStatusText: { draft.values[$0] = $1 },
            lastAppActiveRunAt: { _ in nil },
            setLastAppActiveRunAt: { _, _ in },
            requestConfirmation: { _ in })
        return (settings, context)
    }
}

@MainActor
private final class ResetNewsDraft {
    var values: [String: String] = [:]
}

private actor ResetNewsQueueClient: CodexResetAnnouncementsFetching {
    var calls = 0
    var results: [Result<CodexResetAnnouncements, CodexResetAnnouncementsError>]

    init(results: [Result<CodexResetAnnouncements, CodexResetAnnouncementsError>]) { self.results = results }

    func fetch(from _: URL) async throws -> CodexResetAnnouncements {
        self.calls += 1
        guard !self.results.isEmpty else { throw CodexResetAnnouncementsError.unavailable }
        return try self.results.removeFirst().get()
    }
}

private actor ResetNewsSuspendedClient: CodexResetAnnouncementsFetching {
    var pending: [String: CheckedContinuation<CodexResetAnnouncements, any Error>] = [:]
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    func fetch(from url: URL) async throws -> CodexResetAnnouncements {
        try await withCheckedThrowingContinuation { continuation in
            self.pending[url.absoluteString] = continuation
            self.waiters.removeValue(forKey: url.absoluteString)?.resume()
        }
    }

    func waitForRequest(_ address: String) async {
        if self.pending[address] != nil { return }
        await withCheckedContinuation { self.waiters[address] = $0 }
    }

    func complete(
        _ address: String,
        value: CodexResetAnnouncements)
    {
        self.pending.removeValue(forKey: address)?.resume(returning: value)
    }
}
