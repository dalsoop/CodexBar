import CodexBarCore
import SwiftUI

struct CodexResetAnnouncementsPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String?
        let sourceURL: URL?
    }

    /// The newest reported reset, shown in the section header.
    struct Latest: Equatable {
        let title: String
        let dateText: String?
        let elapsedText: String?
        let quote: String?
        let sourceURL: URL?
    }

    /// Time since the newest reset against the provider's average interval.
    struct Cycle: Equatable {
        let percent: Double
        let label: String
        let isOverdue: Bool
    }

    let latest: Latest?
    let cycle: Cycle?
    let rows: [Row]
    let statusText: String
    let sourceURL: URL
    let isStale: Bool

    @MainActor
    static func make(
        store: CodexResetAnnouncementsStore,
        now: Date) -> Self?
    {
        guard store.isEnabled, let url = store.providerURL else { return nil }
        let snapshot = store.snapshot
        let latest = snapshot?.latest.map { event in
            Latest(
                title: Self.title(for: event),
                dateText: event.date?.formatted(
                    date: .abbreviated,
                    time: .shortened),
                elapsedText: event.date.map { Self.elapsedText(since: $0, now: now) },
                quote: Self.quote(event.text),
                sourceURL: event.sourceURL)
        }
        let cycle: Cycle? = if let date = snapshot?.latest?.date,
                               let averageDays = snapshot?.averageIntervalDays
        {
            Self.cycle(since: date, averageDays: averageDays, now: now)
        } else {
            nil
        }
        var rows: [Row] = []
        if let event = snapshot?.scheduled {
            // The title already says the reset awaits confirmation, so only a future ETA adds detail.
            rows.append(Row(
                id: "scheduled",
                title: L("reset_news_scheduled"),
                detail: event.date.flatMap { date in
                    date < now ? nil : date.formatted(
                        date: .abbreviated,
                        time: .shortened)
                },
                sourceURL: event.sourceURL))
        }
        if let watch = snapshot?.watch, watch.expiresAt > now {
            rows.append(Row(
                id: "watch",
                title: L("reset_news_outlook"),
                detail: watch.text,
                sourceURL: watch.sourceURL))
        }
        let isStale = store.error != nil || snapshot?.generatedAt.map { now.timeIntervalSince($0) > 1800 } == true
        let status = if let generatedAt = snapshot?.generatedAt, store.error == nil {
            L("reset_news_data_time", generatedAt.formatted(
                date: .abbreviated,
                time: .shortened))
        } else {
            store.statusText
        }
        return Self(
            latest: latest,
            cycle: cycle,
            rows: rows,
            statusText: status,
            sourceURL: url,
            isStale: isStale)
    }

    /// Details that do not need a line of their own: the reset date, freshness, attribution and disclaimer.
    var helpText: String {
        var lines: [String] = []
        if let latest = self.latest {
            lines.append([latest.title, latest.dateText].compactMap(\.self).joined(separator: " · "))
        }
        if self.isStale { lines.append(L("reset_news_stale")) }
        lines.append(self.statusText)
        lines.append(L("reset_news_attribution", self.sourceURL.host ?? ""))
        lines.append(L("reset_news_disclaimer"))
        return lines.joined(separator: "\n")
    }

    var heightFingerprint: String {
        let latest = self.latest.map { "\($0.elapsedText ?? ""):\($0.quote ?? "")" } ?? ""
        let cycle = self.cycle.map { "\($0.label):\($0.isOverdue)" } ?? ""
        let rows = self.rows.map {
            "\($0.id):\($0.title):\($0.detail ?? ""):\($0.sourceURL?.absoluteString ?? "")"
        }.joined(separator: "|")
        return "\(latest)|\(cycle)|\(rows)|\(self.statusText)|\(self.isStale)|\(self.sourceURL.absoluteString)"
    }

    private static func title(for event: CodexResetAnnouncements.Event) -> String {
        switch event.kind {
        case .banked: L("reset_news_banked")
        case .announcement: L("reset_news_announced")
        case .reset: L(event.isObserved ? "reset_news_observed" : "reset_news_latest")
        case .scheduled: L("reset_news_scheduled")
        }
    }

    static func elapsedText(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 3600 {
            return String(format: L("%dm ago"), max(1, seconds / 60))
        }
        if seconds < 86400 {
            return String(format: L("%dh ago"), seconds / 3600)
        }
        return String(format: L("%dd ago"), seconds / 86400)
    }

    static func cycle(since date: Date, averageDays: Double, now: Date) -> Cycle {
        let ratio = max(0, now.timeIntervalSince(date)) / 86400 / averageDays
        let average = averageDays.formatted(
            .number.precision(.fractionLength(0...1)).locale(codexBarLocalizedLocale()))
        return Cycle(
            percent: min(100, ratio * 100),
            label: L("reset_news_average_cycle", average),
            isOverdue: ratio >= 1)
    }

    /// One line of the source post without links, which the header already opens.
    static func quote(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).filter {
            !$0.hasPrefix("http://") && !$0.hasPrefix("https://")
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}

struct CodexResetAnnouncementsContent: View {
    let presentation: CodexResetAnnouncementsPresentation
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 6)
        {
            self.header
            if let cycle = self.presentation.cycle {
                HStack(spacing: 8) {
                    UsageProgressBar(
                        percent: cycle.percent,
                        tint: cycle.isOverdue ? .orange : .secondary,
                        accessibilityLabel: cycle.label)
                    self.secondaryText(cycle.label)
                        .fixedSize()
                }
            } else if let latest = self.presentation.latest {
                self.secondaryText([latest.title, latest.dateText].compactMap(\.self).joined(separator: " · "))
                    .lineLimit(1)
            } else {
                self.secondaryText(self.presentation.statusText)
                    .lineLimit(2)
            }
            if let quote = self.presentation.latest?.quote {
                self.secondaryText("“\(quote)”")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            ForEach(self.presentation.rows) { row in
                self.rowView(row)
            }
            HStack(spacing: 4) {
                Link(
                    self.presentation.sourceURL.host ?? "",
                    destination: self.presentation.sourceURL)
                Text(verbatim: "·")
                Text(L("reset_news_community"))
            }
            .font(.caption2)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
        .help(self.presentation.helpText)
        .fixedSize(
            horizontal: false,
            vertical: true)
    }

    private var header: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: 6)
        {
            Text(L("reset_news_title"))
                .font(.body)
                .fontWeight(.medium)
                .fixedSize()
            if self.presentation.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(L("reset_news_stale"))
            }
            Spacer(minLength: 8)
            if let latest = self.presentation.latest, let elapsed = latest.elapsedText {
                let label = HStack(spacing: 2) {
                    Text(elapsed)
                    if latest.sourceURL != nil {
                        Image(systemName: "arrow.up.right")
                            .imageScale(.small)
                    }
                }
                .font(.footnote)
                if let url = latest.sourceURL {
                    Link(destination: url) { label }
                } else {
                    label.foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: CodexResetAnnouncementsPresentation.Row) -> some View {
        let text = [row.title, row.detail].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
        if let url = row.sourceURL {
            Link(text, destination: url)
                .font(.footnote)
                .lineLimit(2)
        } else {
            self.secondaryText(text)
                .lineLimit(2)
        }
    }

    private func secondaryText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
    }
}
