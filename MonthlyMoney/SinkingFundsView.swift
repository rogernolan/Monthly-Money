import SwiftUI

struct SinkingFundsView: View {
    @EnvironmentObject private var state: AppState

    private var funds: [PlannedItem] {
        state.monthItems.filter {
            $0.label.localizedCaseInsensitiveContains("fund") || $0.label.localizedCaseInsensitiveContains("wheel")
        }
    }

    private var averageMonthlyCost: Decimal {
        guard !funds.isEmpty else { return 0 }
        return funds.reduce(0) { $0 + $1.amount } / Decimal(funds.count)
    }

    var body: some View {
        List {
            Section("Overview") {
                HStack {
                    Text("Average monthly cost")
                    Spacer()
                    Text(AppState.currency(averageMonthlyCost)).bold()
                }
            }

            Section("Wheel of money") {
                if funds.isEmpty {
                    Text("No sinking fund items in this month")
                        .foregroundStyle(.secondary)
                }
                ForEach(funds) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.label)
                            Text(item.dueText ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AppState.currency(item.amount))
                    }
                    .swipeActions {
                        Button("Taken") {
                            state.setPaid(item: item, paid: true)
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("Sinking Funds")
    }
}
