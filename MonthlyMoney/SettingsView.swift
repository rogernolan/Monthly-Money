import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var templatesText: String = "Rent\nSalary\nLiving expenses\nSavings"

    var body: some View {
        Form {
            Section("Category templates") {
                TextEditor(text: $templatesText)
                    .frame(minHeight: 120)
            }

            Section("Defaults") {
                LabeledContent("Min suggested living") {
                    decimalField($state.minSuggestedLiving)
                }
                LabeledContent("Buffer") {
                    decimalField($state.livingBuffer)
                }
            }

            Section("Export / Import") {
                Button("Export CSV") {}
                Button("Export XLSX") {}
                Button("Import CSV") {}
                Button("Import XLSX") {}
            }

            Section("Sync") {
                Text("iCloud sync: Phase 2")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private func decimalField(_ value: Binding<Decimal>) -> some View {
        TextField("0", text: Binding(
            get: { NSDecimalNumber(decimal: value.wrappedValue).stringValue },
            set: { value.wrappedValue = Decimal(string: $0) ?? 0 }
        ))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(width: 120)
    }
}
