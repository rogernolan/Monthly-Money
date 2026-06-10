import SwiftUI

enum WheelOfMoneyRowContent {
    static func notesLine(for item: WheelOfMoneyItem) -> String? {
        let trimmed = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct WheelOfMoneyView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @State private var activeEditorItem: WheelOfMoneyItem?
    @State private var isPresentingNewItem = false
    @State private var pendingDeleteItem: WheelOfMoneyItem?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 4)

                Divider()

                List {
                    if state.filteredWheelOfMoneyItems.isEmpty {
                        Text("No items")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(state.filteredWheelOfMoneyItems, id: \.id) { item in
                        row(for: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeleteItem = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }

            Button {
                isPresentingNewItem = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.green))
            }
            .padding(.trailing, 18)
            .padding(.bottom, 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeEditorItem) { item in
            WheelOfMoneyItemEditorView(item: item)
                .environmentObject(state)
        }
        .navigationDestination(isPresented: $isPresentingNewItem) {
            WheelOfMoneyItemEditorView()
                .environmentObject(state)
        }
        .alert(
            "Delete item?",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if !$0 { pendingDeleteItem = nil } }
            ),
            presenting: pendingDeleteItem
        ) { item in
            Button("Cancel", role: .cancel) {
                pendingDeleteItem = nil
            }
            Button("Delete", role: .destructive) {
                state.delete(wheelOfMoneyItem: item)
                pendingDeleteItem = nil
            }
        } message: { item in
            Text("Delete \"\(item.title)\"? This cannot be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WoM")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                chip(
                    title: "Annual total",
                    value: state.wheelOfMoneyMetrics.annualTotal,
                    accessibilityValueID: "wom-chip-annual-total-value"
                )
                chip(
                    title: "Monthly average",
                    value: state.wheelOfMoneyMetrics.monthlyAverage,
                    accessibilityValueID: "wom-chip-monthly-average-value"
                )
                chip(
                    title: "Pending total",
                    value: state.wheelOfMoneyMetrics.pendingTotal,
                    accessibilityValueID: "wom-chip-pending-total-value"
                )
                chip(
                    title: "Remaining average",
                    value: state.wheelOfMoneyMetrics.remainingAverage,
                    accessibilityValueID: "wom-chip-remaining-average-value",
                    tint: state.wheelOfMoneyMetrics.remainingAverageExceedsMonthlyAverage ? ChipPalette.forColorScheme(colorScheme).negativeTop : .white
                )
            }

            Picker("Filter", selection: $state.wheelOfMoneyFilter) {
                ForEach(WheelOfMoneyFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue.capitalized).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func chip(
        title: String,
        value: Decimal,
        accessibilityValueID: String,
        tint: Color = .white
    ) -> some View {
        let palette = ChipPalette.forColorScheme(colorScheme)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(AppState.currency(value))
                .font(.system(
                    size: ChipTypography.monthValueFontSize(for: horizontalSizeClass),
                    weight: .bold,
                    design: .rounded
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier(accessibilityValueID)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.valueColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: resolvedTintColors(from: tint, palette: palette),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.plainBorder.opacity(0.53), lineWidth: 1)
        )
    }

    private func resolvedTintColors(from tint: Color, palette: ChipPalette) -> [Color] {
        if tint == .white {
            return [palette.plainTop, palette.plainBottom]
        }
        if tint == palette.negativeTop {
            return [palette.negativeTop, palette.negativeBottom]
        }
        return [tint, tint]
    }

    private func row(for item: WheelOfMoneyItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(item.title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(AppState.currency(item.amount))
                    .fontWeight(.semibold)

                Button {
                    state.setWheelOfMoneyPaid(item: item, paid: !item.isPaid)
                } label: {
                    Image(systemName: item.isPaid ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(item.isPaid ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 44)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                activeEditorItem = item
            }

            if let notes = WheelOfMoneyRowContent.notesLine(for: item) {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}
