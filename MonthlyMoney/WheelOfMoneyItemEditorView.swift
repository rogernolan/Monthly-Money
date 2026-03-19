import SwiftUI

struct WheelOfMoneyItemEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private let item: WheelOfMoneyItem?
    @State private var draft: WheelOfMoneyItemEditorDraft

    init(item: WheelOfMoneyItem) {
        self.item = item
        _draft = State(initialValue: WheelOfMoneyItemEditorDraft(item: item))
    }

    init() {
        item = nil
        _draft = State(initialValue: WheelOfMoneyItemEditorDraft())
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $draft.title)

                TextField("Amount", text: $draft.amountText)
                    .keyboardType(.decimalPad)

                Picker("Month", selection: $draft.month) {
                    ForEach(WheelOfMoneyMonth.allCases, id: \.rawValue) { month in
                        Text(month.title).tag(month.rawValue)
                    }
                }

                if let item {
                    LabeledContent("Paid", value: item.isPaid ? "Yes" : "No")
                }
            }

            Section("Notes") {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 160)
            }
        }
        .navigationTitle(draft.title.isEmpty ? "WoM Item" : draft.title)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(!draft.canSave)
            }
        }
    }

    private func save() {
        if let item {
            state.update(
                wheelOfMoneyItem: item,
                title: draft.title,
                amount: draft.amount,
                month: draft.month,
                notes: draft.notes
            )
        } else {
            _ = state.createWheelOfMoneyEntry(
                title: draft.title,
                amount: draft.amount,
                month: draft.month,
                notes: draft.notes
            )
        }
        dismiss()
    }
}

private extension WheelOfMoneyMonth {
    var title: String {
        switch self {
        case .january: return "January"
        case .february: return "February"
        case .march: return "March"
        case .april: return "April"
        case .may: return "May"
        case .june: return "June"
        case .july: return "July"
        case .august: return "August"
        case .september: return "September"
        case .october: return "October"
        case .november: return "November"
        case .december: return "December"
        }
    }
}
