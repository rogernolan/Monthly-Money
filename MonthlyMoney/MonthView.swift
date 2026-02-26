import SwiftUI

struct MonthView: View {
    @EnvironmentObject private var state: AppState
    @State private var editingItem: PlannedItem?

    private var fixedDebits: [PlannedItem] { sorted(state.monthItems.filter { $0.type == .fixedDebit }) }
    private var credits: [PlannedItem] { sorted(state.monthItems.filter { $0.type == .credit }) }
    private var transfers: [PlannedItem] { sorted(state.monthItems.filter { $0.type == .transfer }) }

    var body: some View {
        List {
            monthHeader

            itemSection(title: "Fixed Debits", items: fixedDebits)
            itemSection(title: "Credits", items: credits)
            itemSection(title: "Transfers", items: transfers)
        }
        .navigationTitle("Month")
        .sheet(item: $editingItem) { item in
            PlannedItemEditor(item: item)
                .environmentObject(state)
        }
    }

    private var monthHeader: some View {
        Section {
            HStack {
                Button { state.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(state.selectedMonth.rawValue)
                    .font(.headline)
                Spacer()
                Button { state.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }

            Picker("View", selection: $state.viewScope) {
                Text("My View").tag(ViewScope.myView)
                Text("Shared View").tag(ViewScope.sharedView)
            }
            .pickerStyle(.segmented)
            .onChange(of: state.viewScope) { _, _ in
                try? state.refresh()
            }

            LabeledContent("Opening balance") {
                DecimalField(value: Binding(get: { state.openingBalance }, set: { state.openingBalance = $0 }))
            }
            LabeledContent("Primary bank balance") {
                DecimalField(value: Binding(get: { state.primaryBankBalance }, set: { state.primaryBankBalance = $0 }))
            }

            metricTile(title: "Outgoings still due", value: state.monthTotals.debitsDue)
            metricTile(title: "Credits still due", value: state.monthTotals.creditsDue)
            metricTile(title: "Net outgoings due", value: state.monthTotals.netOutgoingsDue)
            metricTile(title: "Projected balance", value: state.monthTotals.projectedBalance)
            metricTile(title: "Suggested living expenses", value: state.monthTotals.suggestedLiving)
        }
    }

    private func metricTile(title: String, value: Decimal) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(AppState.currency(value))
                .bold()
        }
    }

    private func itemSection(title: String, items: [PlannedItem]) -> some View {
        Section(title) {
            if items.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label)
                        Text(dueText(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !item.notes.isEmpty {
                            Text(item.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(AppState.currency(item.amount))
                    Toggle("", isOn: Binding(get: { item.isPaid }, set: { state.setPaid(item: item, paid: $0) }))
                        .labelsHidden()
                }
                .swipeActions(edge: .leading) {
                    Button("Edit") { editingItem = item }
                    Button("Duplicate") { state.duplicate(item: item) }
                        .tint(.blue)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) { state.delete(item: item) }
                }
                .contextMenu {
                    Button("Copy to previous month") { state.copy(item: item, to: shiftedMonth(-1)) }
                    Button("Copy to next month") { state.copy(item: item, to: shiftedMonth(1)) }
                }
            }
        }
    }

    private func dueText(_ item: PlannedItem) -> String {
        if let day = item.dueDay { return "Due day \(day)" }
        if let dueText = item.dueText, !dueText.isEmpty { return dueText }
        return "Floating"
    }

    private func sorted(_ items: [PlannedItem]) -> [PlannedItem] {
        items.sorted { lhs, rhs in
            switch (lhs.dueDay, rhs.dueDay) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
        }
    }

    private func shiftedMonth(_ delta: Int) -> YearMonth {
        var year = state.selectedMonth.year
        var month = state.selectedMonth.month + delta
        while month < 1 { month += 12; year -= 1 }
        while month > 12 { month -= 12; year += 1 }
        return YearMonth(year: year, month: month)
    }
}

private struct PlannedItemEditor: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let item: PlannedItem

    @State private var label: String
    @State private var amountText: String
    @State private var dueDayText: String
    @State private var dueText: String
    @State private var notes: String

    init(item: PlannedItem) {
        self.item = item
        _label = State(initialValue: item.label)
        _amountText = State(initialValue: NSDecimalNumber(decimal: item.amount).stringValue)
        _dueDayText = State(initialValue: item.dueDay.map(String.init) ?? "")
        _dueText = State(initialValue: item.dueText ?? "")
        _notes = State(initialValue: item.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $label)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                TextField("Due day", text: $dueDayText)
                    .keyboardType(.numberPad)
                TextField("Due text", text: $dueText)
                TextField("Notes", text: $notes)
            }
            .navigationTitle("Edit Item")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let amount = Decimal(string: amountText) ?? item.amount
                        let dueDay = Int(dueDayText)
                        state.update(item: item, label: label, amount: amount, dueDay: dueDay, dueText: dueText.isEmpty ? nil : dueText, notes: notes)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct DecimalField: View {
    @Binding var value: Decimal

    var body: some View {
        TextField("0", text: Binding(
            get: { NSDecimalNumber(decimal: value).stringValue },
            set: { value = Decimal(string: $0) ?? 0 }
        ))
        .multilineTextAlignment(.trailing)
        .keyboardType(.decimalPad)
        .frame(width: 120)
    }
}
