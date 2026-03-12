import SwiftUI

struct DailyView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section("Variable Budget") {
                metricRow("Budget", state.monthTotals.suggestedLiving)
                metricRow("Funds total", state.fundsTotal)
                metricRow("Current daily avg", state.currentDailyAverage)
                metricRow("Ahead / behind", state.aheadBehind)
            }

            Section("Cash + FX") {
                Toggle("Include cash", isOn: $state.includeCash)
                Toggle("Include FX", isOn: $state.includeFX)
                LabeledContent("Cash") { decimalField($state.cashBalance) }
                LabeledContent("FX") { decimalField($state.fxBalance) }
            }

            Section("Payday") {
                Stepper("Payday day: \(state.paydayDay)", value: $state.paydayDay, in: 1...31)
                Text("Remaining days: \(state.daysRemainingInMonth)")
            }

            Section("Weekly Reckoner") {
                metricRow("Weekly reckoner", state.weeksReckoner)
            }

            Section {
                Button("Set Living Expenses to Suggested") {
                    state.setLivingExpensesToSuggested()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Daily")
    }

    private func metricRow(_ title: String, _ value: Decimal) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(AppState.currency(value))
                .bold()
        }
    }

    private func decimalField(_ value: Binding<Decimal>) -> some View {
        TextField("0", text: Binding(
            get: { NSDecimalNumber(decimal: value.wrappedValue).stringValue },
            set: { value.wrappedValue = Decimal(string: $0, locale: Locale.current) ?? 0 }
        ))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(width: 120)
    }
}

