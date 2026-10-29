# Monthly row projections implementation plan

> **For agentic workers:** Use superpowers:executing-plans for this single, coupled change. Steps use checkbox syntax for tracking.

**Goal:** Show an automatically updated projected balance beneath each monthly transaction amount.

**Architecture:** MonthCalculationEngine computes a UUID-to-Decimal projection for an ordered item list. AppState supplies the full payday-sorted list and the existing current/future balance basis. MonthView reads the resulting values before applying its row filter.

**Tech stack:** Swift, SwiftUI, XCTest, iOS Simulator.

## Global constraints

- Use Decimal for all money. Never Double.
- Paid items do not change the projection; unpaid credits add and unpaid debits/transfers subtract.
- Preserve the existing payday order, filter-independent balances, and final projected-balance card arithmetic.
- Display smaller, right-aligned text directly below the transaction amount; highlight zero and negative values with a red rounded rectangle.
- Derive values from live state; do not add stored fields or migrations.

## Task 1: Calculate and display row balances

**Files:** Modify MonthlyMoney/MonthCalculationEngine.swift, MonthlyMoney/AppState.swift, MonthlyMoney/MonthView.swift, and MonthlyMoneyTests/MonthlyMoneyTests.swift.

**Interfaces:** Add `MonthCalculationEngine.projectedBalances(startingBalance: Decimal, items: [PlannedItem]) -> [UUID: Decimal]` and `AppState.monthItemProjectedBalances: [UUID: Decimal]`. Reuse MonthItemSortRules and MonthItemFilterRules.

- [x] Add focused XCTest cases for mixed transaction types and paid items; fractional values reaching zero and negative; payday ordering and filter independence; creation, balance edits, paid-status changes, and deletion; future opening balance; OFX import updating the ledger balance and reconciling paid entries.
- [x] Run the tests before implementation and confirm the new projection API is missing.
- [x] Implement the running calculation:

```swift
static func projectedBalances(startingBalance: Decimal, items: [PlannedItem]) -> [UUID: Decimal] {
    var balance = startingBalance
    var balances: [UUID: Decimal] = [:]
    for item in items {
        if !item.isPaid {
            balance += item.type == .credit ? item.amount : -item.amount
        }
        balances[item.id] = balance
    }
    return balances
}
```

- [x] Supply the full sorted monthly item list from AppState, using `isSelectedMonthInFuture ? openingBalance : primaryBankBalance` as the starting balance.
- [x] In MonthView.itemSection, compute the projection map once per section and read by item ID. Put the balance Text immediately after the amount Text in the trailing VStack. Use caption font, secondary text for positive values, and white text over a red rounded rectangle for values at or below zero. Give the balance an accessibility label and stable item-based identifier. Keep the unplanned marker beneath it.
- [x] Run focused tests, then the entire app unit suite:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=4A55E9C8-7B00-4E74-90CE-4B1641A6CEF5' -derivedDataPath /private/tmp/monthly-row-projections-build -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO
```

Expected: app builds, all unit tests pass. For the first run, add individual `-only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testName` selectors for new tests.

- [x] Inspect the resulting UI with positive, zero, and negative balances at phone width, including an unplanned marker. Review the final diff for money arithmetic, update paths, and unrelated changes.
- [x] Commit only the feature files, tests, and plan after verification. Preserve the original checkout's existing edits.

Verification: 232 application unit tests passed on the iPhone 18 Pro simulator; the simulator app build succeeded. Phone-width renders were inspected in light and dark mode. Read-only code review found no material issues. Physical devices and VoiceOver were not exercised.
