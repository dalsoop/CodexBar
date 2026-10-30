import Foundation

/// The plan name and monthly price shown for a ChatGPT account read from an opencodex hub.
/// The hub reports only the plan label (`go`, `plus`, `pro`, …); prices come from the person's settings.
public enum OpenCodexHubPlan {
    /// List prices that are the same in every country. Go's price varies by country, so it has no default.
    public static let defaultPrices = "plus=20, pro=200"
    /// Placeholder of the billing-day setting.
    public static let billingDaysExample = "0f0f=18, 1a2b=2"

    private static let names = [
        "free": "Free",
        "go": "Go",
        "plus": "Plus",
        "pro": "Pro",
        "team": "Team",
        "business": "Business",
        "enterprise": "Enterprise",
        "edu": "Edu",
    ]

    /// A known plan's product name; any other label is shown as the hub reports it.
    public static func displayName(_ label: String) -> String {
        self.names[label.lowercased()] ?? label
    }

    /// Reads `plan=price` pairs separated by commas, semicolons or new lines (`go=8, plus=20`). A leading `$`
    /// is allowed. Malformed pairs are skipped so one typo does not hide every price.
    public static func prices(_ text: String) -> [String: Decimal] {
        var prices: [String: Decimal] = [:]
        for pair in text.split(whereSeparator: { ",;\n".contains($0) }) {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            let amount = parts[1].hasPrefix("$") ? String(parts[1].dropFirst()) : parts[1]
            guard let price = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")),
                  price >= 0
            else { continue }
            prices[parts[0].lowercased()] = price
        }
        return prices
    }

    /// Reads `code=day` pairs (`0f0f=18, 1a2b=2`): an account's hub code and its billing day of the month (1–31).
    /// Codes are matched case-insensitively; malformed pairs are skipped.
    public static func billingDays(_ text: String) -> [String: Int] {
        var days: [String: Int] = [:]
        for pair in text.split(whereSeparator: { ",;\n".contains($0) }) {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let code = parts.first.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 } ?? ""
            guard parts.count == 2, !code.isEmpty, let day = Int(parts[1]), (1...31).contains(day) else { continue }
            days[code.lowercased()] = day
        }
        return days
    }

    /// The next date, today included, that falls on `day` of a month; in shorter months the last day stands in.
    public static func nextBillingDate(day: Int, after now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: today),
                  let range = calendar.range(of: .day, in: .month, for: month)
            else { return nil }
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = min(day, range.count)
            if let date = calendar.date(from: components), date >= today { return date }
        }
        return nil
    }

    /// `$20`, `$8.5`: US dollars with up to two decimals, independent of the app language.
    public static func priceText(_ price: Decimal) -> String {
        "$" + price.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }
}

extension ProviderConfig {
    /// Codex: monthly plan prices in US dollars as `plan=price` pairs, shown next to hub account plans.
    public var codexPlanPrices: String? {
        get { self.extensionValue(forKey: "codexPlanPrices") }
        set { self.setExtensionValue(newValue, forKey: "codexPlanPrices") }
    }

    /// Codex: each hub account's billing day of the month as `code=day` pairs, keyed by the account's hub code.
    public var codexBillingDays: String? {
        get { self.extensionValue(forKey: "codexBillingDays") }
        set { self.setExtensionValue(newValue, forKey: "codexBillingDays") }
    }
}
