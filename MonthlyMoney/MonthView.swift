import SwiftUI

private enum MonthItemFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case debits = "Debits"
    case credits = "Credits"

    var id: String { rawValue }
}

enum MonthItemRowContent {
    static func metadataLines(for item: PlannedItem) -> [String] {
        var lines = [dueText(for: item)]
        let trimmedNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            lines.append(trimmedNotes)
        }
        return lines
    }

    static func dueText(for item: PlannedItem) -> String {
        if let day = item.dueDay { return ordinal(day) }
        if let dueText = item.dueText, !dueText.isEmpty { return dueText }
        return "Floating"
    }

    static func ordinal(_ day: Int) -> String {
        let remainder100 = day % 100
        let suffix: String
        if remainder100 >= 11 && remainder100 <= 13 {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    static func showsOverdueHighlight(
        for item: PlannedItem,
        isSelectedMonthInPast: Bool,
        isSelectedMonthInFuture: Bool,
        todayDay: Int
    ) -> Bool {
        guard item.amount != 0 else { return false }
        guard !item.isPaid, !isSelectedMonthInPast, !isSelectedMonthInFuture else { return false }
        guard let dueDay = item.dueDay else { return false }
        return dueDay < todayDay
    }
}

enum MonthEditableCardRules {
    static func allowsCurrentBalanceEditing(
        isSelectedMonthInPast: Bool,
        isSelectedMonthInFuture: Bool
    ) -> Bool {
        !isSelectedMonthInPast && !isSelectedMonthInFuture
    }
}

enum MonthChipFocusID {
    static func currentBalance(for month: YearMonth) -> String {
        "month-current-balance-\(month.rawValue)"
    }
}

private extension VerticalAlignment {
    private enum MonthRowTitleAlignment: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let monthRowTitle = VerticalAlignment(MonthRowTitleAlignment.self)
}

struct MonthView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var focusedEditableChipID: String?
    @State private var filter: MonthItemFilter = .all
    @State private var activeNewEntry: NewMonthItemSeed?
    @State private var activeEditorItem: PlannedItem?

    private var debits: [PlannedItem] {
        sorted(state.monthItems.filter { $0.type == .fixedDebit || $0.type == .transfer })
    }

    private var credits: [PlannedItem] {
        sorted(state.monthItems.filter { $0.type == .credit })
    }

    private var filteredItems: [PlannedItem] {
        switch filter {
        case .all:
            return sorted(debits + credits)
        case .debits:
            return debits
        case .credits:
            return credits
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                fixedHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                Divider()

                List {
                    itemSection(title: filter.rawValue, items: filteredItems)
                }
                .listStyle(.insetGrouped)
            }

            floatingAddButton
                .padding(.trailing, 18)
                .padding(.bottom, 10)
                .zIndex(1)
        }
        .navigationDestination(item: $activeNewEntry) { seed in
            MonthItemEditorView(newType: seed.type, dueDay: seed.dueDay)
                .environmentObject(state)
        }
        .navigationDestination(item: $activeEditorItem) { item in
            MonthItemEditorView(item: item)
                .environmentObject(state)
        }
        .onChange(of: state.selectedMonth) { _, _ in
            focusedEditableChipID = nil
        }
    }

    private var fixedHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            monthTimeline

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                amountCard(
                    title: state.isSelectedMonthInFuture ? "Opening balance" : "Current balance",
                    value: state.isSelectedMonthInFuture ? state.openingBalance : state.primaryBankBalance,
                    editableValue: MonthEditableCardRules.allowsCurrentBalanceEditing(
                        isSelectedMonthInPast: state.isSelectedMonthInPast,
                        isSelectedMonthInFuture: state.isSelectedMonthInFuture
                    ) ? Binding(
                            get: { state.primaryBankBalance },
                            set: { state.primaryBankBalance = $0 }
                        ) : nil,
                    editableFocusID: MonthEditableCardRules.allowsCurrentBalanceEditing(
                        isSelectedMonthInPast: state.isSelectedMonthInPast,
                        isSelectedMonthInFuture: state.isSelectedMonthInFuture
                    ) ? MonthChipFocusID.currentBalance(for: state.selectedMonth) : nil
                )
                amountCard(
                    title: "Projected balance",
                    value: state.projectedBalanceFromCurrentBalance
                )
                amountCard(
                    title: "Outgoings still due",
                    value: state.monthTotals.debitsDue,
                    secondaryText: "Total: " + AppState.currency(state.monthTotals.debitsTotalExLiving),
                    prefixIcon: "arrowtriangle.down.fill",
                    prefixColor: .red
                )
                amountCard(
                    title: "Credits still due",
                    value: state.monthTotals.creditsDue,
                    secondaryText: "Total: " + AppState.currency(state.monthTotals.creditsTotal),
                    prefixIcon: "arrowtriangle.up.fill",
                    prefixColor: .green
                )
            }

            Picker("Filter", selection: $filter) {
                ForEach(MonthItemFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if state.canPopulateSelectedMonthFromPrevious {
                Button {
                    state.populateSelectedMonthFromPrevious()
                } label: {
                    Text("Populate \(selectedMonthName) from \(previousMonthName)?")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    private var monthTimeline: some View {
        HStack(spacing: 8) {
            Button { state.shiftMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Button {
                state.selectedMonth = currentYearMonth
                try? state.refresh()
            } label: {
                Text(selectedMonthName)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { state.shiftMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!state.canNavigateToNextMonth)
            .opacity(state.canNavigateToNextMonth ? 1 : 0.35)
            .accessibilityLabel("Next month")
        }
    }

    private var selectedMonthName: String {
        var components = DateComponents()
        components.year = state.selectedMonth.year
        components.month = state.selectedMonth.month
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    private var currentYearMonth: YearMonth {
        let now = Date()
        let calendar = Calendar.current
        return YearMonth(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
    }

    private var previousMonthName: String {
        monthName(for: previousMonth(of: state.selectedMonth))
    }

    private func previousMonth(of month: YearMonth) -> YearMonth {
        var year = month.year
        var value = month.month - 1
        if value < 1 {
            value = 12
            year -= 1
        }
        return YearMonth(year: year, month: value)
    }

    private func monthName(for month: YearMonth) -> String {
        var components = DateComponents()
        components.year = month.year
        components.month = month.month
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    private var todayDay: Int {
        Calendar.current.component(.day, from: Date())
    }

    private var defaultTypeForNewEntry: PlannedItemType {
        switch filter {
        case .credits:
            return .credit
        case .all, .debits:
            return .fixedDebit
        }
    }

    private var floatingAddButton: some View {
        Button {
            activeNewEntry = NewMonthItemSeed(type: defaultTypeForNewEntry, dueDay: todayDay)
        } label: {
            Image(systemName: "plus")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.16, green: 0.58, blue: 0.34), Color(red: 0.09, green: 0.41, blue: 0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .disabled(state.isSelectedMonthInPast)
        .opacity(state.isSelectedMonthInPast ? 0.45 : 1.0)
        .accessibilityLabel("New entry")
    }

    @ViewBuilder
    private func amountCard(
        title: String,
        value: Decimal,
        secondaryText: String? = nil,
        editableValue: Binding<Decimal>? = nil,
        editableFocusID: String? = nil,
        prefixIcon: String? = nil,
        prefixColor: Color? = nil
    ) -> some View {
        let style = styleFor(value)
        let card = VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = prefixIcon {
                    Image(systemName: icon)
                        .font(.caption.bold())
                        .foregroundStyle(prefixColor ?? .secondary)
                }
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if let editableValue {
                EditableMoneyChipValue(
                    value: editableValue,
                    fontSize: 25.5,
                    focus: $focusedEditableChipID,
                    focusID: editableFocusID ?? title
                )
            } else {
                Text(AppState.currency(value))
                    .font(.system(size: 25.5, weight: .semibold))
            }

            if let secondaryText {
                Text(secondaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .frame(minHeight: 54, alignment: .topTrailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [style.top, style.bottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.border.opacity(0.35), lineWidth: 1)
        )

        if let editableFocusID {
            card
                .overlay(alignment: .topLeading) {
                    EditableMoneyChipBadge()
                        .padding(.top, 6)
                        .padding(.leading, 6)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedEditableChipID = editableFocusID
                }
        } else {
            card
        }
    }

    private func itemSection(title: String, items: [PlannedItem]) -> some View {
        Section(title) {
            if items.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
            }

            ForEach(items) { item in
                HStack(alignment: .monthRowTitle, spacing: 8) {
                    Image(systemName: item.type == .credit ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption.bold())
                        .foregroundStyle(item.type == .credit ? Color.green : Color.red)
                        .alignmentGuide(.monthRowTitle) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(item.label.isEmpty ? " " : item.label)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(AppState.currency(item.amount))
                                .fontWeight(.semibold)

                            Button {
                                state.setPaid(item: item, paid: !item.isPaid)
                            } label: {
                                Image(systemName: item.isPaid ? "checkmark.square.fill" : "square")
                                    .font(.title3)
                                    .foregroundStyle(item.isPaid ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(state.isSelectedMonthInPast)
                            .opacity(state.isSelectedMonthInPast ? 0.6 : 1.0)
                            .frame(width: 44)

                            Image(systemName: "chevron.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .alignmentGuide(.monthRowTitle) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            let metadataLines = MonthItemRowContent.metadataLines(for: item)
                            ForEach(Array(metadataLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeEditorItem = item
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isOverdue(item) ? Color.red.opacity(0.12) : Color.clear)
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !state.isSelectedMonthInPast {
                        Button(role: .destructive) {
                            state.delete(item: item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func sorted(_ items: [PlannedItem]) -> [PlannedItem] {
        items.sorted { lhs, rhs in
            let leftDay = lhs.dueDay ?? 0
            let rightDay = rhs.dueDay ?? 0
            if leftDay != rightDay { return leftDay < rightDay }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private func isOverdue(_ item: PlannedItem) -> Bool {
        MonthItemRowContent.showsOverdueHighlight(
            for: item,
            isSelectedMonthInPast: state.isSelectedMonthInPast,
            isSelectedMonthInFuture: state.isSelectedMonthInFuture,
            todayDay: Calendar.current.component(.day, from: Date())
        )
    }

    private func styleFor(_ value: Decimal) -> (top: Color, bottom: Color, border: Color) {
        if value < 0 {
            return (
                Color(red: 0.98, green: 0.86, blue: 0.86),
                Color(red: 0.93, green: 0.70, blue: 0.70),
                .red
            )
        }
        if value < 100 {
            return (
                Color(red: 0.99, green: 0.95, blue: 0.82),
                Color(red: 0.96, green: 0.88, blue: 0.63),
                .orange
            )
        }
        return (
            Color(red: 0.87, green: 0.95, blue: 0.89),
            Color(red: 0.72, green: 0.88, blue: 0.76),
            .green
        )
    }
}

private struct MonthItemEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    private let item: PlannedItem?
    @State private var draft: MonthItemEditorDraft

    init(item: PlannedItem) {
        self.item = item
        _draft = State(initialValue: MonthItemEditorDraft(item: item))
    }

    init(newType: PlannedItemType, dueDay: Int?) {
        item = nil
        _draft = State(initialValue: MonthItemEditorDraft(newType: newType, dueDay: dueDay))
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $draft.label)
                    .disabled(!isEditable)

                Picker("Type", selection: $draft.entryKind) {
                    ForEach(MonthEntryKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!isEditable)

                TextField("Amount", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                    .disabled(!isEditable)

                Picker("Day", selection: $draft.dueSelection) {
                    Text("Floating").tag(MonthDueSelection.floating)
                    ForEach(1...31, id: \.self) { day in
                        Text(MonthItemRowContent.ordinal(day)).tag(MonthDueSelection.day(day))
                    }
                }
                .disabled(!isEditable)

                Toggle("Copy to next month automatically", isOn: $draft.copiesToNextMonthAutomatically)
                    .disabled(!isEditable)
            }

            Section("Notes") {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 160)
                    .disabled(!isEditable)
            }
        }
        .navigationTitle(draft.label.isEmpty ? "Entry" : draft.label)
        .onChange(of: draft.amountText) { _, _ in
            draft.normalizeAmountInput()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isEditable {
                    Button("Save") {
                        save()
                    }
                    .disabled(!draft.canSave)
                }
            }
        }
    }

    private var isEditable: Bool {
        !state.isSelectedMonthInPast
    }

    private func save() {
        if let item {
            state.update(
                item: item,
                label: draft.label,
                amount: draft.amount,
                dueDay: draft.dueSelection.value,
                dueText: nil,
                type: draft.resolvedType(existingItemType: item.type),
                copiesToNextMonthAutomatically: draft.copiesToNextMonthAutomatically,
                notes: draft.notes
            )
            dismiss()
            return
        }
        if state.createEntry(
            type: draft.resolvedType(),
            label: draft.label,
            amount: draft.amount,
            dueDay: draft.dueSelection.value,
            copiesToNextMonthAutomatically: draft.copiesToNextMonthAutomatically,
            notes: draft.notes
        ) != nil {
            dismiss()
        }
    }
}

private struct NewMonthItemSeed: Identifiable, Hashable {
    let id = UUID()
    let type: PlannedItemType
    let dueDay: Int?
}
