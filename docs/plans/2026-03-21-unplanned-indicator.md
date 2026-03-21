# Unplanned Indicator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show an `unplanned` marker under the amount for month items that came from imported unplanned transactions.

**Architecture:** Keep the change local to `MonthView.swift` by adding a tiny row-content helper that decides whether an item should show the marker. Use that helper from the month row’s trailing amount stack so the label is right-aligned, red, and uses the same caption typography as notes.

**Critical Assumptions:**
- The intended signal for “unplanned” is `PlannedItem.source == .importedUnplanned`. Validated by the existing domain model and reconciliation flow.
- A pure row-content helper can cover the display rule in unit tests without introducing SwiftUI snapshot tests. Validated by adding a focused XCTest first.

**Tech Stack:** Swift, SwiftUI, XCTest, xcodebuild

---

### Task 1: Add regression coverage for the unplanned marker rule

**Files:**
- Modify: `MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Test: `MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing test**

Add one test that expects `unplanned` for `.importedUnplanned` items and another that expects `nil` for manual items.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testMonthItemRowShowsUnplannedIndicatorForImportedUnplannedItems`

Expected: FAIL because the helper does not exist yet.

### Task 2: Implement the month-row unplanned indicator

**Files:**
- Modify: `MonthlyMoney/MonthView.swift`
- Test: `MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write minimal implementation**

Add a helper on `MonthItemRowContent` and render the returned marker in a trailing amount `VStack`.

**Step 2: Run focused tests to verify they pass**

Run: `xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testMonthItemRowShowsUnplannedIndicatorForImportedUnplannedItems`

Expected: PASS

### Task 3: Verify integration

**Files:**
- Modify: `MonthlyMoney/MonthView.swift`
- Test: `MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Run broader verification**

Run: `xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testMonthItemRowShowsUnplannedIndicatorForImportedUnplannedItems -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testMonthItemRowMetadataLinesShowDayThenNotes`

Expected: PASS

**Step 2: Run build**

Run: `xcodebuild build -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4'`

Expected: `** BUILD SUCCEEDED **`
