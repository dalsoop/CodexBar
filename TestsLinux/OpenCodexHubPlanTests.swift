import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodexHubPlanTests {
    @Test
    func `plan prices read plan=price pairs and skip malformed ones`() {
        let prices = OpenCodexHubPlan.prices("Go=8.5; plus = $20,\npro=200, team, edu=x, free=-1, =3")
        #expect(prices == ["go": Decimal(85) / 10, "plus": 20, "pro": 200])
        #expect(OpenCodexHubPlan.prices(OpenCodexHubPlan.defaultPrices) == ["plus": 20, "pro": 200])
        #expect(OpenCodexHubPlan.prices("").isEmpty)
    }

    @Test
    func `known plans get their product name and prices are dollars with up to two decimals`() {
        #expect(OpenCodexHubPlan.displayName("go") == "Go")
        #expect(OpenCodexHubPlan.displayName("PRO") == "Pro")
        #expect(OpenCodexHubPlan.displayName("edu_plus") == "edu_plus")
        #expect(OpenCodexHubPlan.priceText(200) == "$200")
        #expect(OpenCodexHubPlan.priceText(Decimal(85) / 10) == "$8.5")
        #expect(OpenCodexHubPlan.priceText(Decimal(1_234_567) / 1000) == "$1234.57")
    }

    @Test
    func `billing days read code=day pairs and skip days outside a month`() {
        let days = OpenCodexHubPlan.billingDays("#0F0F=18; 1a2b = 2,\nffff=0, eeee=32, dddd=x, 31, =5")
        #expect(days == ["0f0f": 18, "1a2b": 2])
        #expect(OpenCodexHubPlan.billingDays("").isEmpty)
    }

    @Test
    func `the next billing date includes today and falls back to a short month's last day`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        func date(_ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
        }
        #expect(try OpenCodexHubPlan.nextBillingDate(day: 30, after: date(10, 30, hour: 12), calendar: calendar)
            == date(10, 30))
        #expect(try OpenCodexHubPlan.nextBillingDate(day: 18, after: date(10, 30, hour: 12), calendar: calendar)
            == date(11, 18))
        #expect(try OpenCodexHubPlan.nextBillingDate(day: 31, after: date(11, 5), calendar: calendar)
            == date(11, 30))
        #expect(try OpenCodexHubPlan.nextBillingDate(day: 31, after: date(1, 31, hour: 23), calendar: calendar)
            == date(1, 31))
        #expect(try OpenCodexHubPlan.nextBillingDate(day: 30, after: date(2, 1), calendar: calendar)
            == date(2, 28))
    }

    @Test
    func `plan prices are stored in the Codex provider config`() throws {
        var config = ProviderConfig(id: .codex)
        #expect(config.codexPlanPrices == nil)
        config.codexPlanPrices = "go=8"
        config.codexBillingDays = "0f0f=18"
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.codexPlanPrices == "go=8")
        #expect(decoded.codexBillingDays == "0f0f=18")
    }
}
