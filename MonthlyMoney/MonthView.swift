import SwiftUI

private enum MonthItemFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case debits = "Debits"
    case credits = "Credits"

    var id: String { rawValue }
}

struct MonthView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: MonthItemFilter = .all
    @State private var activeNewEntry: NewMonthItemSeed?

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
    }

    private var fixedHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            monthTimeline

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                amountCard(
                    title: state.isSelectedMonthInFuture ? "Opening balance" : "Current balance",
                    value: state.isSelectedMonthInFuture ? state.openingBalance : state.primaryBankBalance,
                    editableValue: state.isSelectedMonthInFuture
                        ? nil
                        : Binding(
                            get: { state.primaryBankBalance },
                            set: { state.primaryBankBalance = $0 }
                        )
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

    private func amountCard(
        title: String,
        value: Decimal,
        secondaryText: String? = nil,
        editableValue: Binding<Decimal>? = nil,
        prefixIcon: String? = nil,
        prefixColor: Color? = nil
    ) -> some View {
        let style = styleFor(value)
        return VStack(alignment: .trailing, spacing: 4) {
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
                EditableCurrencyField(value: editableValue)
                    .font(.system(size: 25.5, weight: .semibold))
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
    }

    private func itemSection(title: String, items: [PlannedItem]) -> some View {
        Section(title) {
            if items.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
            }

            ForEach(items) { item in
                NavigationLink {
                    MonthItemEditorView(item: item)
                        .environmentObject(state)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.type == .credit ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.caption.bold())
                            .foregroundStyle(item.type == .credit ? Color.green : Color.red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label.isEmpty ? " " : item.label)
                            Text(dueText(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

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
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isOverdue(item) ? Color.red.opacity(0.12) : Color.clear)
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        state.delete(item: item)
                    } label: {
                        Label("Delete", systemImage: "trash")
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

    private func dueText(_ item: PlannedItem) -> String {
        if let day = item.dueDay { return ordinal(day) }
        if let dueText = item.dueText, !dueText.isEmpty { return dueText }
        return "Floating"
    }

    private func ordinal(_ day: Int) -> String {
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

    private func isOverdue(_ item: PlannedItem) -> Bool {
        guard !item.isPaid, !state.isSelectedMonthInPast, !state.isSelectedMonthInFuture else { return false }
        guard let dueDay = item.dueDay else { return false }
        let today = Calendar.current.component(.day, from: Date())
        return dueDay < today
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
                        Text(ordinal(day)).tag(MonthDueSelection.day(day))
                    }
                }
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
            notes: draft.notes
        ) != nil {
            dismiss()
        }
    }

    private func ordinal(_ day: Int) -> String {
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
}

private struct NewMonthItemSeed: Identifiable, Hashable {
    let id = UUID()
    let type: PlannedItemType
    let dueDay: Int?
}

private struct EditableCurrencyField: View {
    @Binding var value: Decimal
    @State private var isEditing = false
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("0", text: Binding(
                    get: { draft },
                    set: {
                        draft = $0
                        value = Decimal(string: $0, locale: Locale.current) ?? 0
                    }
                ))
                .focused($isFocused)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isFocused = false
                            isEditing = false
                        }
                    }
                }
            } else {
                Text(AppState.currency(value))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = NSDecimalNumber(decimal: value).stringValue
                        isEditing = true
                        DispatchQueue.main.async {
                            isFocused = true
                        }
                    }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                isEditing = false
            }
        }
    }
}
