import SwiftUI
import WidgetKit

struct DailyBudgetSummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: DailyBudgetWidgetSnapshot?
}

struct DailyBudgetSummaryProvider: TimelineProvider {
    private let store = DailyBudgetWidgetSnapshotStore()

    func placeholder(in context: Context) -> DailyBudgetSummaryEntry {
        DailyBudgetSummaryEntry(date: Date(), snapshot: placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyBudgetSummaryEntry) -> Void) {
        let snapshot = store.load() ?? placeholderSnapshot
        completion(DailyBudgetSummaryEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyBudgetSummaryEntry>) -> Void) {
        let entry = DailyBudgetSummaryEntry(date: Date(), snapshot: store.load())
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 30)))
        completion(timeline)
    }

    private var placeholderSnapshot: DailyBudgetWidgetSnapshot {
        DailyBudgetWidgetSnapshot(
            updatedAt: Date(),
            chips: [
                DailyBudgetWidgetChipSnapshot(title: "Ahead", value: "--", tone: .neutral),
                DailyBudgetWidgetChipSnapshot(title: "Current Day", value: "--", tone: .neutral)
            ]
        )
    }
}

struct DailyBudgetSummaryWidget: Widget {
    let kind: String = "DailyBudgetSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyBudgetSummaryProvider()) { entry in
            DailyBudgetSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Budget")
        .description("Shows ahead or behind budget and your current daily budget.")
        .supportedFamilies(supportedFamilies)
        #if !os(watchOS)
        .contentMarginsDisabled()
        #endif
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryRectangular]
        #else
        return [.systemSmall]
        #endif
    }
}

private struct DailyBudgetSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: DailyBudgetSummaryEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessoryRectangularView
                .containerBackground(Color.clear, for: .widget)
        default:
            systemSmallView
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private var systemSmallView: some View {
        VStack(spacing: 10) {
            ForEach(displayChips.indices, id: \.self) { index in
                chipView(displayChips[index], compact: false)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }

    private var accessoryRectangularView: some View {
        HStack(spacing: 8) {
            ForEach(displayChips.indices, id: \.self) { index in
                chipView(displayChips[index], compact: true)
            }
        }
        .padding(.vertical, 6)
    }

    private var displayChips: [DailyBudgetWidgetChipSnapshot] {
        entry.snapshot?.chips ?? [
            DailyBudgetWidgetChipSnapshot(title: "Ahead", value: "--", tone: .neutral),
            DailyBudgetWidgetChipSnapshot(title: "Current Day", value: "--", tone: .neutral)
        ]
    }

    private func chipView(_ chip: DailyBudgetWidgetChipSnapshot, compact: Bool) -> some View {
        VStack(alignment: .trailing, spacing: compact ? 2 : 4) {
            Text(chip.title)
                .font(compact ? .system(size: 10, weight: .medium) : .system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(chip.value)
                .font(compact ? .system(size: 15, weight: .semibold) : .system(size: 24, weight: .bold))
                .foregroundStyle(valueColor(for: chip.tone))
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 4 : 12)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .fill(Color.white.opacity(compact ? 0.12 : 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .stroke(compact ? Color.clear : Color.secondary.opacity(0.35), lineWidth: compact ? 0 : 1)
        )
    }

    private func valueColor(for tone: DailyBudgetWidgetChipTone) -> Color {
        switch tone {
        case .negative:
            return .red
        case .neutral:
            return .primary
        case .positive:
            return .green
        }
    }
}
