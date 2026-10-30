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
    func `plan prices are stored in the Codex provider config`() throws {
        var config = ProviderConfig(id: .codex)
        #expect(config.codexPlanPrices == nil)
        config.codexPlanPrices = "go=8"
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.codexPlanPrices == "go=8")
    }
}
