import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Daily") {
                Toggle(
                    "Use separate account for daily budget",
                    isOn: Binding(
                        get: { state.usesSeparateAccountForDailyBudget },
                        set: { state.usesSeparateAccountForDailyBudget = $0 }
                    )
                )
                .disabled(!state.canEditBudgetSettings)

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
                .disabled(!state.canEditBudgetSettings)

                if !state.canEditBudgetSettings {
                    Text("Only the budget owner can change these settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sharing") {
                Button("Share Budget") {
                    Task {
                        await state.shareBudget()
                    }
                }
                .disabled(!state.sharingPresentation.isShareButtonEnabled || state.isSharingBudget)

                LabeledContent("Status", value: state.sharingPresentation.statusText)

                if let note = state.sharingPresentation.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = state.sharingErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
