import CodexBarCore
import Foundation

/// The card title of a Codex hub account: plan, monthly price and next billing date
/// (`Go ($8) · Next billing Nov 18`). The email moves to its own line under it.
enum OpenCodexHubPlanTitle {
    static func title(for account: OpenCodexHubAccount, prices: [String: Decimal], now: Date) -> String? {
        guard let label = account.displayAlias?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty
        else { return nil }
        var plan = OpenCodexHubPlan.displayName(label)
        if let price = prices[label.lowercased()] {
            plan += " (\(OpenCodexHubPlan.priceText(price)))"
        }
        guard let activeUntil = account.subscriptionActiveUntil else { return plan }
        // A past date means the hub's stored sign-in predates the last renewal, not that billing stopped.
        let billing = activeUntil > now
            ? L("hub_plan_next_billing", activeUntil.formatted(
                .dateTime.month(.abbreviated).day().locale(codexBarLocalizedLocale())))
            : L("hub_plan_billing_unknown")
        return "\(plan) · \(billing)"
    }
}
