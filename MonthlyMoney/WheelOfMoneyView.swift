import SwiftUI

enum WheelOfMoneyRowContent {
    static let annualisedCostTitle = "Annualised cost"
    static let singleOccurrenceRepeatPeriodHelp = "Cannot edit repeat period of a single entry. Select 'This and future' if you wish to change the repeat period."

    static func notesLine(for item: WheelOfMoneyItem) -> String? {
        let trimmed = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func dayText(for date: CivilDate) -> String {
        MonthItemRowContent.ordinal(date.day)
    }

    static func directionSymbol(for type: PlannedItemType) -> String {
        type == .credit ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
    }
}

struct WheelOfMoneyView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var activeOccurrence: PeriodicWomOccurrence?

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                savingsChip(
                    title: WheelOfMoneyRowContent.annualisedCostTitle,
                    amount: state.annualizedPeriodicRepeatCost,
                    accessibilityIdentifier: "wom-chip-annualised-cost-value"
                )
                savingsChip(
                    title: "Monthly savings target",
                    amount: state.monthlyPeriodicRepeatSavingsTarget,
                    accessibilityIdentifier: "wom-chip-monthly-savings-target-value"
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("wom-fixed-summary")

            Divider()

            List {
                if state.womOccurrenceGroups.allSatisfy({ $0.occurrences.isEmpty }) {
                    ContentUnavailableView("No periodic repeats", systemImage: "repeat", description: Text("Every-N-days items will appear here."))
                }

                ForEach(visibleGroups) { group in
                    Section(monthTitle(group.month)) {
                        ForEach(group.occurrences) { occurrence in
                            Button {
                                activeOccurrence = occurrence
                            } label: {
                                occurrenceRow(occurrence)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wom-occurrence-\(occurrence.id)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    _ = state.deletePeriodicOccurrence(occurrence, scope: .thisOccurrence)
                                }
                                .accessibilityIdentifier("wom-occurrence-delete-\(occurrence.id)")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("WoM")
        .navigationDestination(item: $activeOccurrence) { occurrence in
            PeriodicWomOccurrenceEditorView(occurrence: occurrence)
                .environmentObject(state)
        }
    }

    private var visibleGroups: [PeriodicWomMonthGroup] {
        guard let current = state.womOccurrenceGroups.first?.month else { return [] }
        return state.womOccurrenceGroups.filter { $0.month == current || !$0.occurrences.isEmpty }
    }

    private func savingsChip(title: String, amount: Decimal, accessibilityIdentifier: String) -> some View {
        let style = chipStyle(for: amount)
        let palette = ChipPalette.forColorScheme(colorScheme)
        return VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.titleColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(AppState.currency(amount))
                .font(.system(size: ChipTypography.monthValueFontSize(for: horizontalSizeClass), weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .foregroundStyle(palette.valueColor)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topTrailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [style.top, style.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.border.opacity(0.35), lineWidth: 1)
        )
    }

    private func chipStyle(for value: Decimal) -> (top: Color, bottom: Color, border: Color) {
        let palette = ChipPalette.forColorScheme(colorScheme)
        if value < 0 { return (palette.negativeTop, palette.negativeBottom, .red) }
        if value < 100 {
            return (Color(red: 0.99, green: 0.95, blue: 0.82), Color(red: 0.96, green: 0.88, blue: 0.63), .orange)
        }
        return (Color(red: 0.87, green: 0.95, blue: 0.89), Color(red: 0.72, green: 0.88, blue: 0.76), .green)
    }

    private func monthTitle(_ month: YearMonth) -> String {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? .now
        return date.formatted(Date.FormatStyle().month(.wide).year().locale(Locale(identifier: "en_GB")))
    }

    private func occurrenceRow(_ occurrence: PeriodicWomOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: WheelOfMoneyRowContent.directionSymbol(for: occurrence.type))
                    .font(.caption.bold())
                    .foregroundStyle(occurrence.type == .credit ? Color.green : Color.red)
                    .accessibilityHidden(true)

                Text(occurrence.label)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(AppState.currency(occurrence.amount))
                    .fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text("\(WheelOfMoneyRowContent.dayText(for: occurrence.dueDate)) · Every \(occurrence.repeatDays) days")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("wom-occurrence-date-\(occurrence.id)")
            if !occurrence.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(occurrence.notes).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}

private struct PeriodicWomOccurrenceEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let occurrence: PeriodicWomOccurrence
    @State private var label: String
    @State private var matchingString: String
    @State private var amountText: String
    @State private var startDate: Date
    @State private var repeatDaysText: String
    @State private var notes: String
    @State private var type: PlannedItemType
    @State private var scope: PeriodicOccurrenceEditScope = .thisOccurrence
    @State private var isShowingDeleteConfirmation = false

    init(occurrence: PeriodicWomOccurrence) {
        self.occurrence = occurrence
        _label = State(initialValue: occurrence.label)
        _matchingString = State(initialValue: occurrence.matchingString ?? "")
        _amountText = State(initialValue: NSDecimalNumber(decimal: occurrence.amount).stringValue)
        _startDate = State(initialValue: Self.date(from: occurrence.dueDate))
        _repeatDaysText = State(initialValue: String(occurrence.repeatDays))
        _notes = State(initialValue: occurrence.notes)
        _type = State(initialValue: occurrence.type)
    }

    var body: some View {
        Form {
            Section("Change scope") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apply to")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Apply to", selection: $scope) {
                        ForEach(PeriodicOccurrenceEditScope.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("wom-occurrence-apply-to")

                    Text(scope == .thisOccurrence
                         ? "Only this occurrence will change."
                         : "This date and later dates will use a new schedule revision.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                labeledTextField(title: "Display title", text: $label, identifier: "wom-occurrence-title")
                labeledTextField(title: "Search string for import", text: $matchingString, identifier: "wom-occurrence-matching-text")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                VStack(alignment: .leading, spacing: 6) {
                    fieldTitle("Type")
                    Picker("Type", selection: Binding(
                        get: { type == .credit ? MonthEntryKind.credit : .debit },
                        set: { type = $0 == .credit ? .credit : .fixedDebit }
                    )) {
                        ForEach(MonthEntryKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("wom-occurrence-type")
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldTitle("Amount")
                    HStack(spacing: 2) {
                        Text("£")
                            .foregroundStyle(.secondary)
                        TextField("", text: $amountText)
                            .keyboardType(.decimalPad)
                            .frame(width: 96)
                            .multilineTextAlignment(.leading)
                            .accessibilityLabel("Amount")
                            .accessibilityIdentifier("wom-occurrence-amount")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldTitle("Start date")
                    Group {
                        if scope == .thisAndFuture {
                            DatePicker(
                                "Start date",
                                selection: $startDate,
                                in: Self.date(from: occurrence.scheduledDate)...,
                                displayedComponents: .date
                            )
                        } else {
                            DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                        }
                    }
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("wom-occurrence-start-date")
                }

                VStack(alignment: .leading, spacing: 6) {
                    labeledTextField(title: "Repeat period (days)", text: $repeatDaysText, identifier: "wom-occurrence-repeat-days")
                        .keyboardType(.numberPad)
                        .disabled(scope != .thisAndFuture)
                    Text(scope == .thisOccurrence
                         ? WheelOfMoneyRowContent.singleOccurrenceRepeatPeriodHelp
                         : "The start date must be on or after \(occurrence.scheduledDate.rawValue).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }

            Section {
                Button("Delete repeat", systemImage: "trash", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .accessibilityIdentifier("wom-occurrence-delete")
                .confirmationDialog(
                    scope == .thisOccurrence ? "Delete this occurrence?" : "Delete this and future repeats?",
                    isPresented: $isShowingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if state.deletePeriodicOccurrence(occurrence, scope: scope) {
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(scope == .thisOccurrence
                         ? "Only this occurrence will be deleted."
                         : "This repeat and its future occurrences will be deleted. Earlier occurrences will remain.")
                }
            }
        }
        .navigationTitle(label.isEmpty ? "Repeat occurrence" : label)
        .onChange(of: scope) { _, newScope in
            if newScope == .thisAndFuture,
               Self.civilDate(from: startDate).map({ $0 < occurrence.scheduledDate }) == true {
                startDate = Self.date(from: occurrence.scheduledDate)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .accessibilityIdentifier("wom-occurrence-editor-save")
            }
        }
    }

    private func save() {
        guard let amount = Self.decimal(from: amountText),
              let dueDate = Self.civilDate(from: startDate) else { return }
        let interval = scope == .thisOccurrence ? occurrence.repeatDays : (Int(repeatDaysText) ?? 0)
        guard state.savePeriodicOccurrence(
            occurrence,
            label: label,
            matchingString: matchingString,
            amount: amount,
            dueDate: dueDate,
            type: type,
            notes: notes,
            repeatDays: interval,
            scope: scope
        ) else { return }
        dismiss()
    }

    private func labeledTextField(title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldTitle(title)
            TextField("", text: text)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func decimal(from text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: cleaned, locale: Locale(identifier: "en_GB"))
    }

    private static func date(from civilDate: CivilDate) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            year: civilDate.year,
            month: civilDate.month,
            day: civilDate.day,
            hour: 12
        ))!
    }

    private static func civilDate(from date: Date) -> CivilDate? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return CivilDate(year: year, month: month, day: day)
    }
}
