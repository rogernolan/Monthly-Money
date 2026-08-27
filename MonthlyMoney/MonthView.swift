import SwiftUI

enum MonthItemFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case debits = "Debits"
    case credits = "Credits"
    case pending = "Pending"

    var id: String { rawValue }
}

enum MonthItemFilterRules {
    static func filteredItems(_ items: [PlannedItem], for filter: MonthItemFilter) -> [PlannedItem] {
        switch filter {
        case .all:
            return items
        case .debits:
            return items.filter { $0.type == .fixedDebit || $0.type == .transfer }
        case .credits:
            return items.filter { $0.type == .credit }
        case .pending:
            return items.filter { !$0.isPaid && $0.amount != 0 }
        }
    }
}

enum MonthItemSortRules {
    static func sortedItems(_ items: [PlannedItem], paydayDay: Int, month: YearMonth) -> [PlannedItem] {
        items.sorted { lhs, rhs in
            let leftKey = sortKey(for: lhs, paydayDay: paydayDay, month: month)
            let rightKey = sortKey(for: rhs, paydayDay: paydayDay, month: month)
            if leftKey != rightKey { return leftKey < rightKey }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private static func sortKey(for item: PlannedItem, paydayDay: Int, month: YearMonth) -> Int {
        guard let dueDay = item.dueDay else { return Int.max }
        let normalizedPayday = min(max(paydayDay, 1), daysInMonth(for: month))
        if dueDay >= normalizedPayday {
            return dueDay - normalizedPayday
        }
        return (daysInMonth(for: month) - normalizedPayday + 1) + (dueDay - 1)
    }

    private static func daysInMonth(for month: YearMonth) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: month.year, month: month.month, day: 1)
        let monthStart = calendar.date(from: components)
        return monthStart.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31
    }
}

enum MonthItemRowContent {
    static func amountFootnote(for item: PlannedItem) -> String? {
        guard item.source == .importedUnplanned else { return nil }
        guard item.type == .fixedDebit || item.type == .transfer else { return nil }
        return "unplanned"
    }

    static func metadataLines(for item: PlannedItem) -> [String] {
        var lines = [dueText(for: item)]
        let trimmedNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            lines.append(trimmedNotes)
        }
        return lines
    }

    static func dueText(for item: PlannedItem) -> String {
        if let day = item.dueDay {
            return ordinal(day)
        }
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
        selectedMonth: YearMonth,
        paydayDay: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard item.amount != 0 else { return false }
        guard !item.isPaid, !isSelectedMonthInPast, !isSelectedMonthInFuture else { return false }
        guard let dueDay = item.dueDay else { return false }

        let selectedMonthStart = calendar.date(
            from: DateComponents(year: selectedMonth.year, month: selectedMonth.month, day: 1)
        )
        guard let selectedMonthStart,
              let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: selectedMonthStart),
              let previousMonthDays = calendar.range(of: .day, in: .month, for: previousMonthStart)?.count,
              let selectedMonthDays = calendar.range(of: .day, in: .month, for: selectedMonthStart)?.count else {
            return false
        }

        let cycleStartDay = min(max(paydayDay, 1), previousMonthDays)
        let dueMonthStart = dueDay >= cycleStartDay ? previousMonthStart : selectedMonthStart
        let dueMonthDays = dueDay >= cycleStartDay ? previousMonthDays : selectedMonthDays
        guard let dueDate = calendar.date(
            bySetting: .day,
            value: min(max(dueDay, 1), dueMonthDays),
            of: dueMonthStart
        ) else {
            return false
        }

        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: today)
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedEditableChipID: String?
    @State private var filter: MonthItemFilter = .all
    @State private var activeNewEntry: NewMonthItemSeed?
    @State private var activeEditorItem: PlannedItem?

    private var debits: [PlannedItem] {
        sorted(MonthItemFilterRules.filteredItems(state.monthItems, for: .debits))
    }

    private var credits: [PlannedItem] {
        sorted(MonthItemFilterRules.filteredItems(state.monthItems, for: .credits))
    }

    private var filteredItems: [PlannedItem] {
        sorted(MonthItemFilterRules.filteredItems(state.monthItems, for: filter))
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
                    accessibilityValueID: "month-chip-current-balance-value",
                    footnoteText: BalanceLastUpdatedPresentation.text(
                        for: state.monthlyBalanceLastUpdatedAt,
                        relativeTo: state.currentDate
                    ),
                    footnoteColor: {
                        guard let lastUpdated = state.monthlyBalanceLastUpdatedAt,
                              BalanceLastUpdatedPresentation.isStale(lastUpdated, relativeTo: state.currentDate) else {
                            return nil
                        }
                        return .red
                    }(),
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
                    value: state.projectedBalanceFromCurrentBalance,
                    accessibilityValueID: "month-chip-projected-balance-value"
                )
                amountCard(
                    title: "Outgoings still due",
                    value: state.monthTotals.debitsDue,
                    accessibilityValueID: "month-chip-outgoings-due-value",
                    secondaryText: "Total: " + AppState.currency(state.monthTotals.debitsTotalExLiving),
                    prefixIcon: "arrowtriangle.down.fill",
                    prefixColor: .red
                )
                amountCard(
                    title: "Credits still due",
                    value: state.monthTotals.creditsDue,
                    accessibilityValueID: "month-chip-credits-due-value",
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
        case .all, .debits, .pending:
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
        accessibilityValueID: String? = nil,
        secondaryText: String? = nil,
        footnoteText: String? = nil,
        footnoteColor: Color? = nil,
        editableValue: Binding<Decimal>? = nil,
        editableFocusID: String? = nil,
        prefixIcon: String? = nil,
        prefixColor: Color? = nil
    ) -> some View {
        let style = styleFor(value)
        let palette = ChipPalette.forColorScheme(colorScheme)
        let titleLeadingInset: CGFloat = editableFocusID == nil ? 0 : 28
        let card = VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = prefixIcon {
                    Image(systemName: icon)
                        .font(.caption.bold())
                        .foregroundStyle(prefixColor ?? .secondary)
                }
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(palette.titleColor)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, titleLeadingInset)

            if let editableValue {
                EditableMoneyChipValue(
                    value: editableValue,
                    fontSize: ChipTypography.monthValueFontSize(for: horizontalSizeClass),
                    focus: $focusedEditableChipID,
                    focusID: editableFocusID ?? title,
                    accessibilityIdentifier: accessibilityValueID
                )
            } else {
                Text(AppState.currency(value))
                    .font(.system(size: ChipTypography.monthValueFontSize(for: horizontalSizeClass), weight: .semibold))
                    .accessibilityIdentifier(accessibilityValueID ?? "")
            }

            if let secondaryText {
                Text(secondaryText)
                    .font(.caption2)
                    .foregroundStyle(palette.titleColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let footnoteText {
                Text(footnoteText)
                    .font(.caption2)
                    .foregroundStyle(footnoteColor ?? palette.titleColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .foregroundStyle(palette.valueColor)
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

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AppState.currency(item.amount))
                                    .fontWeight(.semibold)

                                if let footnote = MonthItemRowContent.amountFootnote(for: item) {
                                    Text(footnote)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

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
                            ForEach(Array(metadataLines.enumerated()), id: \.offset) { index, line in
                                if index == 0 && item.copiesToNextMonthAutomatically {
                                    HStack(spacing: 4) {
                                        Text(line)
                                        Image(systemName: "arrow.right")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                } else {
                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
        MonthItemSortRules.sortedItems(items, paydayDay: state.dailyBudgetPaydayDay, month: state.selectedMonth)
    }

    private func isOverdue(_ item: PlannedItem) -> Bool {
        MonthItemRowContent.showsOverdueHighlight(
            for: item,
            isSelectedMonthInPast: state.isSelectedMonthInPast,
            isSelectedMonthInFuture: state.isSelectedMonthInFuture,
            selectedMonth: state.selectedMonth,
            paydayDay: state.dailyBudgetPaydayDay,
            today: Date()
        )
    }

    private func styleFor(_ value: Decimal) -> (top: Color, bottom: Color, border: Color) {
        let palette = ChipPalette.forColorScheme(colorScheme)
        if value < 0 {
            return (
                palette.negativeTop,
                palette.negativeBottom,
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
    @State private var editingItem: PlannedItem?
    @State private var draft: MonthItemEditorDraft
    @State private var activeMatchSourceItem: PlannedItem?
    @State private var pendingSameMonthPopulationItem: PlannedItem?

    init(item: PlannedItem) {
        _editingItem = State(initialValue: item)
        _draft = State(initialValue: MonthItemEditorDraft(item: item))
    }

    init(newType: PlannedItemType, dueDay: Int?) {
        _editingItem = State(initialValue: nil)
        _draft = State(initialValue: MonthItemEditorDraft(newType: newType, dueDay: dueDay))
    }

    var body: some View {
        Form {
            Section("Details") {
                labeledEditor(
                    title: "Display title",
                    text: $draft.label
                )
                .disabled(!isEditable)

                labeledEditor(
                    title: "Search string for import",
                    text: $draft.matchingString
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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

                Picker("Repeat", selection: $draft.repeatMode) {
                    Text("Does not repeat").tag(MonthRepeatMode.oneOff)
                    Text("Calendar repeat").tag(MonthRepeatMode.calendar)
                    Text("Periodic").tag(MonthRepeatMode.periodic)
                }
                .disabled(!isEditable)

                if draft.repeatMode == .calendar {
                    Picker("Day", selection: Binding(
                        get: { draft.repeatAnchorDay ?? 1 },
                        set: { draft.repeatAnchorDay = $0; draft.dueSelection = .day($0) }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text(MonthItemRowContent.ordinal(day)).tag(day)
                        }
                    }
                }

                if draft.repeatMode == .periodic {
                    TextField("Repeat days", text: $draft.repeatDaysText)
                        .keyboardType(.numberPad)
                        .disabled(!isEditable)
                }

                Toggle("Planned", isOn: $draft.isPlanned)
                    .disabled(!isEditable)

                Toggle("Copy to next month automatically", isOn: $draft.copiesToNextMonthAutomatically)
                    .disabled(!isEditable)
            }

            if let editableItem, editableItem.source == .importedUnplanned, isEditable {
                Section("Matching") {
                    Button("Match to planned item") {
                        activeMatchSourceItem = editableItem
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 160)
                    .disabled(!isEditable)

                if let editableItem,
                   let statementText = state.linkedImportedPayee(for: editableItem) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shown on bank statement as")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(statementText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(draft.label.isEmpty ? "Entry" : draft.label)
        .onChange(of: draft.amountText) { _, _ in
            draft.normalizeAmountInput()
        }
        .onChange(of: draft.repeatMode) { _, mode in
            switch mode {
            case .oneOff:
                draft.dueSelection = .floating
            case .calendar:
                let day = draft.repeatAnchorDay ?? 1
                draft.repeatAnchorDay = day
                draft.dueSelection = .day(day)
            case .periodic:
                if draft.repeatAnchorDay == nil { draft.repeatAnchorDay = 1 }
                draft.dueSelection = .everyNDays
            }
        }
        .navigationDestination(item: $activeMatchSourceItem) { sourceItem in
            MonthItemManualMatchPickerView(sourceItem: sourceItem) { matchedItem in
                editingItem = matchedItem
                draft = MonthItemEditorDraft(item: matchedItem)
            }
            .environmentObject(state)
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
        .alert(
            "Add remaining occurrences?",
            isPresented: Binding(
                get: { pendingSameMonthPopulationItem != nil },
                set: { isPresented in
                    if !isPresented { pendingSameMonthPopulationItem = nil }
                }
            )
        ) {
            Button("Add occurrences") {
                if let item = pendingSameMonthPopulationItem {
                    state.populateSameMonth(for: item)
                }
                pendingSameMonthPopulationItem = nil
                dismiss()
            }
            Button("Not now", role: .cancel) {
                pendingSameMonthPopulationItem = nil
                dismiss()
            }
        } message: {
            Text("This repeat falls again later in the selected month. Add all remaining occurrences now?")
        }
    }

    private func labeledEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(title)
        }
    }

    private var isEditable: Bool {
        !state.isSelectedMonthInPast
    }

    private var editableItem: PlannedItem? {
        editingItem
    }

    private var sourceOverride: PlannedItemSource {
        if !draft.isPlanned {
            return .importedUnplanned
        }
        guard let editableItem else {
            return .manual
        }
        return editableItem.source == .copiedFromPreviousMonth ? .copiedFromPreviousMonth : .manual
    }

    private func save() {
        if let item = editableItem {
            let wasNotRepeating = item.repeatMode != .periodic
            let intervalChanged = item.repeatDays != draft.repeatDays
            state.update(
                item: item,
                label: draft.label,
                matchingString: draft.matchingString,
                amount: draft.amount,
                dueDay: draft.dueDay,
                dueText: nil,
                type: draft.resolvedType(existingItemType: item.type),
                sourceOverride: sourceOverride,
                repeatDays: draft.repeatDays,
                recurrenceID: item.recurrenceID,
                repeatMode: draft.repeatMode == .oneOff ? .oneOff : (draft.repeatMode == .calendar ? .calendar : .periodic),
                copiesToNextMonthAutomatically: draft.copiesToNextMonthAutomatically,
                notes: draft.notes
            )
            if (wasNotRepeating || intervalChanged),
               draft.repeatDays != nil,
               !state.sameMonthOccurrences(for: item).isEmpty {
                pendingSameMonthPopulationItem = item
            } else {
                dismiss()
            }
            return
        }
        if state.createEntry(
            type: draft.resolvedType(),
            label: draft.label,
            matchingString: draft.matchingString,
            amount: draft.amount,
            dueDay: draft.dueDay,
            source: sourceOverride,
            repeatDays: draft.repeatDays,
            repeatMode: draft.repeatMode == .oneOff ? .oneOff : (draft.repeatMode == .calendar ? .calendar : .periodic),
            copiesToNextMonthAutomatically: draft.copiesToNextMonthAutomatically,
            notes: draft.notes
        ) != nil {
            dismiss()
        }
    }
}

private struct MonthItemManualMatchPickerView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let sourceItem: PlannedItem
    let onMatched: (PlannedItem) -> Void

    var body: some View {
        List {
            ForEach(state.manualMatchCandidates(for: sourceItem)) { candidate in
                Button {
                    match(sourceItem: sourceItem, to: candidate)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.label)
                            Text(MonthItemRowContent.dueText(for: candidate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(AppState.currency(candidate.amount))
                            .foregroundStyle(candidate.type == .credit ? .green : .primary)
                    }
                }
            }
        }
        .navigationTitle("Match to planned item")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }

    private func match(sourceItem: PlannedItem, to candidate: PlannedItem) {
        do {
            if let matchedItem = try state.matchImportedUnplannedItem(sourceItem, to: candidate) {
                onMatched(matchedItem)
                dismiss()
            }
        } catch {
            print("Manual match failed: \(error)")
        }
    }
}

private struct NewMonthItemSeed: Identifiable, Hashable {
    let id = UUID()
    let type: PlannedItemType
    let dueDay: Int?
}
