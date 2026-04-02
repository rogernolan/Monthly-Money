import SwiftUI

struct MonthlyMoneyWatchView: View {
    @StateObject private var viewModel = MonthlyMoneyWatchViewModel()
    private enum Layout {
        static let gridSpacing: CGFloat = 6
        static let titleFontSize: CGFloat = 9
        static let valueFontSize: CGFloat = 14
        static let cardMinHeight: CGFloat = 42
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 4
        static let cornerRadius: CGFloat = 12
    }

    private let columns = [
        GridItem(.flexible(), spacing: Layout.gridSpacing),
        GridItem(.flexible(), spacing: Layout.gridSpacing)
    ]

    var body: some View {
        ScrollView {
            if let snapshot = viewModel.snapshot, !snapshot.chips.isEmpty {
                LazyVGrid(columns: columns, spacing: Layout.gridSpacing) {
                    ForEach(Array(snapshot.chips.enumerated()), id: \.offset) { _, chip in
                        chipView(chip)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "iphone.slash")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No Daily Data")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 8)
        .navigationTitle("Daily")
        .onAppear {
            viewModel.refreshFromCache()
        }
    }

    private func chipView(_ chip: WatchDailyBudgetChipSnapshot) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(chip.title)
                .font(.system(size: Layout.titleFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(chip.value)
                .font(.system(size: Layout.valueFontSize, weight: .semibold))
                .foregroundStyle(valueColor(for: chip.tone))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.cardMinHeight, alignment: .topTrailing)
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private func valueColor(for tone: WatchDailyBudgetChipTone) -> Color {
        switch tone {
        case .plain:
            return .primary
        case .negative:
            return .red
        case .neutral:
            return .yellow
        case .positive:
            return .green
        }
    }
}

#Preview {
    NavigationStack {
        MonthlyMoneyWatchView()
    }
}
