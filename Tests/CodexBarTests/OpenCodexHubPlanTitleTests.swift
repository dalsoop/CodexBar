import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OpenCodexHubPlanTitleTests {
    private static let now = Date(timeIntervalSince1970: 1_793_300_000) // 2026-10-29

    private static func account(label: String?, activeUntil: Date?) -> OpenCodexHubAccount {
        OpenCodexHubAccount(
            idSuffix: "0f0f",
            label: label,
            email: "b***b@example.com",
            isActive: false,
            subscriptionActiveUntil: activeUntil)
    }

    @Test
    func `the title shows the plan, its price and the next billing date`() {
        let renewal = Self.now.addingTimeInterval(20 * 86400)
        let title = OpenCodexHubPlanTitle.title(
            for: Self.account(label: "go", activeUntil: renewal),
            prices: ["go": 8, "pro": 200],
            now: Self.now)
        let date = renewal.formatted(.dateTime.month(.abbreviated).day().locale(codexBarLocalizedLocale()))
        #expect(title == "Go ($8) · " + L("hub_plan_next_billing", date))
    }

    @Test
    func `a stale sign-in date asks to check billing and unknown dates or prices are left out`() {
        let stale = OpenCodexHubPlanTitle.title(
            for: Self.account(label: "pro", activeUntil: Self.now.addingTimeInterval(-86400)),
            prices: ["pro": 200],
            now: Self.now)
        #expect(stale == "Pro ($200) · " + L("hub_plan_billing_unknown"))
        let unpriced = OpenCodexHubPlanTitle.title(
            for: Self.account(label: "go", activeUntil: nil),
            prices: ["pro": 200],
            now: Self.now)
        #expect(unpriced == "Go")
    }

    @Test
    func `accounts without a plan label keep the provider title`() {
        #expect(OpenCodexHubPlanTitle.title(
            for: Self.account(label: nil, activeUntil: Self.now),
            prices: [:],
            now: Self.now) == nil)
        #expect(OpenCodexHubPlanTitle.title(
            for: Self.account(label: "b***b@example.com", activeUntil: Self.now),
            prices: [:],
            now: Self.now) == nil)
    }
}
