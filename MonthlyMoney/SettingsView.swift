import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Toggle(
                "Use separate account for daily budget",
                isOn: Binding(
                    get: { state.usesSeparateAccountForDailyBudget },
                    set: { state.usesSeparateAccountForDailyBudget = $0 }
                )
            )

            Picker(
                "Payday",
                selection: Binding(
                    get: { state.dailyBudgetPaydayDay },
                    set: { state.dailyBudgetPaydayDay = $0 }
                )
            ) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)")
                        .tag(day)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
