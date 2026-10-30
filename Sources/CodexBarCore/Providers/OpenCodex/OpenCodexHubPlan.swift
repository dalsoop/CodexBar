import Foundation

/// The plan name and monthly price shown for a ChatGPT account read from an opencodex hub.
/// The hub reports only the plan label (`go`, `plus`, `pro`, …); prices come from the person's settings.
public enum OpenCodexHubPlan {
    /// List prices that are the same in every country. Go's price varies by country, so it has no default.
    public static let defaultPrices = "plus=20, pro=200"

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
}
