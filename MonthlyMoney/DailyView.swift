import SwiftUI

enum DailyChipKind {
    case budget
    case dailyBudget
    case currentBalance
    case aheadBehind
    case currentDailyBudget
    case daysUntilPayday
}

enum DailyChipTone: Equatable {
    case plain
    case negative
    case neutral
    case positive
}

enum DailyChipToneResolver {
    static func tone(
        for kind: DailyChipKind,
        metrics: DailyBudgetCycleMetrics,
        currentBalance: Decimal
    ) -> DailyChipTone {
        switch kind {
        case .budget, .dailyBudget, .daysUntilPayday:
            return .plain
        case .currentBalance:
            return tone(for: currentBalance)
        case .aheadBehind:
            return tone(for: metrics.aheadBehind)
        case .currentDailyBudget:
            return comparisonTone(lhs: metrics.currentDailyBudget, rhs: metrics.dailyBudget)
        }
    }

    static func tone(for value: Decimal) -> DailyChipTone {
        if value < 0 { return .negative }
        if value == 0 { return .neutral }
        return .positive
    }

    static func comparisonTone(lhs: Decimal, rhs: Decimal) -> DailyChipTone {
        if lhs < rhs { return .negative }
        if lhs == rhs { return .neutral }
        return .positive
    }
}

enum DailyPresentationContent {
    static let budgetTitle = "Starting budget at beginning of month"
    static let dailyBudgetTitle = "Average daily budget"
    static let currentBalanceTitle = "Current balance"
    static let projectedFundsTitle = "Predicted remaining funds"

    static func balanceTitle(usesSeparateAccount: Bool) -> String {
        usesSeparateAccount ? currentBalanceTitle : projectedFundsTitle
    }

    static func daysUntilPaydayTitle(paydayDay: Int) -> String {
        "Days until payday (\(MonthItemRowContent.ordinal(paydayDay)))"
    }
}

struct DailyView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                let cardWidth = max((proxy.size.width - 10) / 2, 0)
                let metrics = state.dailyCycleMetrics
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        budgetChip
                            .frame(width: cardWidth)
                        dailyBudgetChip(metrics: metrics)
                            .frame(width: cardWidth)
                    }

                    HStack(spacing: 10) {
                        currentBalanceChip(metrics: metrics)
                            .frame(width: cardWidth)
                        aheadBehindChip(metrics: metrics)
                            .frame(width: cardWidth)
                    }

                    HStack(spacing: 10) {
                        currentDailyBudgetChip(metrics: metrics)
                            .frame(width: cardWidth)
                        daysUntilPaydayChip(metrics: metrics)
                            .frame(width: cardWidth)
                    }
                }
            }
            .frame(height: 326)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Daily")
    }

    private var budgetChip: some View {
        dailyChip(
            title: DailyPresentationContent.budgetTitle,
            tone: .plain
        ) {
            DailyCurrencyField(value: $state.dailyBudgetAmount)
        }
    }

    private func dailyBudgetChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: DailyPresentationContent.dailyBudgetTitle,
            tone: .plain
        ) {
            Text(AppState.currency(metrics.dailyBudget))
                .font(.system(size: 28, weight: .semibold))
        }
    }

    private func currentBalanceChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: DailyPresentationContent.balanceTitle(usesSeparateAccount: state.usesSeparateAccountForDailyBudget),
            tone: DailyChipToneResolver.tone(for: .currentBalance, metrics: metrics, currentBalance: state.dailyBudgetCurrentBalance)
        ) {
            if state.usesSeparateAccountForDailyBudget {
                DailyCurrencyField(value: $state.dailyBudgetSeparateAccountBalance)
            } else {
                Text(AppState.currency(state.dailyBudgetCurrentBalance))
                    .font(.system(size: 28, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func aheadBehindChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: "Ahead / behind",
            tone: DailyChipToneResolver.tone(for: .aheadBehind, metrics: metrics, currentBalance: state.dailyBudgetCurrentBalance)
        ) {
            Text(AppState.currency(metrics.aheadBehind))
                .font(.system(size: 28, weight: .semibold))
        }
    }

    private func currentDailyBudgetChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: "Current daily budget",
            tone: DailyChipToneResolver.tone(for: .currentDailyBudget, metrics: metrics, currentBalance: state.dailyBudgetCurrentBalance)
        ) {
            Text(AppState.currency(metrics.currentDailyBudget))
                .font(.system(size: 28, weight: .semibold))
        }
    }

    private func daysUntilPaydayChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: DailyPresentationContent.daysUntilPaydayTitle(paydayDay: state.dailyBudgetPaydayDay),
            tone: .plain
        ) {
            Text("\(metrics.remainingDaysToPayday)")
                .font(.system(size: 28, weight: .semibold))
        }
    }

    private func dailyChip<Content: View>(
        title: String,
        tone: DailyChipTone,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let style = style(for: tone)
        return VStack(alignment: .trailing, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .frame(minHeight: 92, alignment: .topTrailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [style.top, style.bottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.border.opacity(0.35), lineWidth: 1)
        )
    }

    private func style(for tone: DailyChipTone) -> (top: Color, bottom: Color, border: Color) {
        switch tone {
        case .plain:
            return (
                Color.white,
                Color(red: 0.96, green: 0.96, blue: 0.96),
                Color.black.opacity(0.15)
            )
        case .negative:
            return (
                Color(red: 0.98, green: 0.86, blue: 0.86),
                Color(red: 0.93, green: 0.70, blue: 0.70),
                .red
            )
        case .neutral:
            return (
                Color(red: 0.99, green: 0.95, blue: 0.82),
                Color(red: 0.96, green: 0.88, blue: 0.63),
                .orange
            )
        case .positive:
            return (
                Color(red: 0.87, green: 0.95, blue: 0.89),
                Color(red: 0.72, green: 0.88, blue: 0.76),
                .green
            )
        }
    }
}

private struct DailyCurrencyField: View {
    @Binding var value: Decimal
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("0", text: Binding(
            get: {
                if !isFocused {
                    return AppState.currency(value)
                }
                if draft.isEmpty {
                    return NSDecimalNumber(decimal: value).stringValue
                }
                return draft
            },
            set: {
                draft = $0
                value = Decimal(string: sanitizedNumericString(from: $0), locale: Locale.current) ?? 0
            }
        ))
        .focused($isFocused)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .font(.system(size: 28, weight: .semibold))
        .onAppear {
            draft = NSDecimalNumber(decimal: value).stringValue
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                draft = NSDecimalNumber(decimal: value).stringValue
            }
            if !focused {
                draft = ""
            }
        }
    }

    private func sanitizedNumericString(from input: String) -> String {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let groupingSeparator = Locale.current.groupingSeparator ?? ","
        let filtered = input
            .replacingOccurrences(of: Locale.current.currencySymbol ?? "", with: "")
            .replacingOccurrences(of: groupingSeparator, with: "")
            .filter { $0.isNumber || String($0) == decimalSeparator || $0 == "-" }
        return filtered.isEmpty ? "0" : filtered
    }
}
