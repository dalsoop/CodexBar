import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OpenCodexHubPlanTitleTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return calendar
    }()

    /// 2026-10-30 12:00 in Seoul.
    private static let now = Date(timeIntervalSince1970: 1_793_329_200)

    private static func account(label: String?, code: String? = "0F0F") -> OpenCodexHubAccount {
        OpenCodexHubAccount(
            idSuffix: code,
            label: label,
            email: "b***b@example.com",
            isActive: false,
            subscriptionActiveUntil: self.now.addingTimeInterval(-86400))
    }

    private static func dateText(month: Int, day: Int) throws -> String {
        let date = try #require(Self.calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        return date.formatted(.dateTime.month(.abbreviated).day().locale(codexBarLocalizedLocale()))
    }

    @Test
    func `the title shows the plan, its price and the next billing day the person entered`() throws {
        let title = OpenCodexHubPlanTitle.title(
            for: Self.account(label: "go"),
            prices: ["go": 8, "pro": 200],
            billingDays: ["0f0f": 18],
            now: Self.now,
            calendar: Self.calendar)
        #expect(try title == "Go ($8) · " + L("hub_plan_next_billing", Self.dateText(month: 11, day: 18)))
        let laterThisMonth = OpenCodexHubPlanTitle.title(
            for: Self.account(label: "pro"),
            prices: ["pro": 200],
            billingDays: ["0f0f": 31],
            now: Self.now,
            calendar: Self.calendar)
        #expect(try laterThisMonth == "Pro ($200) · " + L("hub_plan_next_billing", Self.dateText(month: 10, day: 31)))
    }

    @Test
    func `without an entered day only the plan and price show, whatever the sign-in claims`() {
        #expect(OpenCodexHubPlanTitle.title(
            for: Self.account(label: "go"),
            prices: ["pro": 200],
            billingDays: ["1a2b": 2],
            now: Self.now,
            calendar: Self.calendar) == "Go")
    }

    @Test
    func `accounts without a plan label keep the provider title`() {
        #expect(OpenCodexHubPlanTitle.title(
            for: Self.account(label: nil),
            prices: [:],
            billingDays: [:],
            now: Self.now) == nil)
        #expect(OpenCodexHubPlanTitle.title(
            for: Self.account(label: "b***b@example.com"),
            prices: [:],
            billingDays: [:],
            now: Self.now) == nil)
    }

    @Test
    func `the email line carries the account's hub code`() {
        #expect(OpenCodexHubPlanTitle.emailLine(for: Self.account(label: "go"), email: "b***b@example.com")
            == "b***b@example.com · #0F0F")
        #expect(OpenCodexHubPlanTitle.emailLine(for: Self.account(label: "go"), email: "") == "#0F0F")
        #expect(OpenCodexHubPlanTitle.emailLine(for: Self.account(label: "go", code: nil), email: "x") == "x")
    }
}
