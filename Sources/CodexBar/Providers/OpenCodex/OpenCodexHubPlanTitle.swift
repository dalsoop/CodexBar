import CodexBarCore
import Foundation

/// The card title of a Codex hub account: plan, monthly price and next billing date
/// (`Go ($8) · Next billing Nov 18`). The email and the account's hub code move to the line below.
enum OpenCodexHubPlanTitle {
    static func title(
        for account: OpenCodexHubAccount,
        prices: [String: Decimal],
        billingDays: [String: Int],
        now: Date,
        calendar: Calendar = .current) -> String?
    {
        guard let label = account.displayAlias?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty
        else { return nil }
        var plan = OpenCodexHubPlan.displayName(label)
        if let price = prices[label.lowercased()] {
            plan += " (\(OpenCodexHubPlan.priceText(price)))"
        }
        // The billing day is the person's own entry: neither the sign-in nor the hub has a reliable renewal date.
        guard let code = account.idSuffix?.lowercased(), let day = billingDays[code],
              let next = OpenCodexHubPlan.nextBillingDate(day: day, after: now, calendar: calendar)
        else { return plan }
        let date = next.formatted(.dateTime.month(.abbreviated).day().locale(codexBarLocalizedLocale()))
        return "\(plan) · \(L("hub_plan_next_billing", date))"
    }

    /// The masked email followed by the account's hub code, which the billing-day setting uses as its key.
    static func emailLine(for account: OpenCodexHubAccount, email: String) -> String {
        guard let code = account.idSuffix, !code.isEmpty else { return email }
        return email.isEmpty ? "#\(code)" : "\(email) · #\(code)"
    }
}
