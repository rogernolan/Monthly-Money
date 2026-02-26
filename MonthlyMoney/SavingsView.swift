import SwiftUI

private enum SavingsOwner: String, CaseIterable, Identifiable {
    case all = "All"
    case rog = "Rog"
    case jane = "Jane"
    case joint = "Joint"

    var id: String { rawValue }
}

struct SavingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var owner: SavingsOwner = .all

    private var savingsItems: [PlannedItem] {
        state.monthItems.filter { $0.label.localizedCaseInsensitiveContains("saving") }
    }

    private var total: Decimal {
        savingsItems.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            Section {
                Picker("Who", selection: $owner) {
                    ForEach(SavingsOwner.allCases) { person in
                        Text(person.rawValue).tag(person)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Total") {
                HStack {
                    Text("Savings total")
                    Spacer()
                    Text(AppState.currency(total)).bold()
                }
            }

            Section("Savings") {
                if savingsItems.isEmpty {
                    Text("No savings lines in this month")
                        .foregroundStyle(.secondary)
                }
                ForEach(savingsItems) { item in
                    HStack {
                        Text(item.label)
                        Spacer()
                        Text(AppState.currency(item.amount))
                    }
                }
            }
        }
        .navigationTitle("Savings")
    }
}
