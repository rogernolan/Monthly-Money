# Empty Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make fresh installs create only an empty top-level budget/account graph with zero balances and no seeded planned items, transactions, or Wheel of Money rows.

**Architecture:** Keep `AppState.bootstrapIfNeeded()` and `restoreLocalBudgetIfNeeded()` responsible for creating the minimal local budget/account state, but stop invoking sample-data seeding helpers. Update tests that currently encode seeded first-run content so they assert the new empty-state behavior instead.

**Critical Assumptions:**
- The app still functions when `monthItems` and `wheelOfMoneyItems` are empty on first launch. Validate by updating tests first and running them red/green.
- Keeping one empty account preserves current UI assumptions better than a fully account-less launch. Validate by building the app after implementation.

**Tech Stack:** Swift, SwiftUI, XCTest, XCUITest, Xcodebuild

---

### Task 1: Update fresh-install expectations

**Files:**
- Modify: `MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Modify: `MonthlyMoneyUITests/MonthlyMoneyUITests.swift`

**Step 1: Write the failing tests**
- Change the bootstrap unit tests to expect empty month/WoM data and zero balances on fresh install.
- Change the UI test to stop expecting seeded WoM row labels.

**Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=0D618A40-1A2D-49C7-BD62-4295D747E18E' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testBootstrapCreatesLocalBudgetAndLoadsCurrentMonth -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testBootstrapSeedsWheelOfMoneyItems
```

**Step 3: Implement the bootstrap change**

**Files:**
- Modify: `MonthlyMoney/AppState.swift`

- Remove sample/default seeding from `bootstrapIfNeeded()`.
- Remove sample/default seeding from `restoreLocalBudgetIfNeeded()`.
- Preserve minimal account creation and refresh behavior.

**Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=0D618A40-1A2D-49C7-BD62-4295D747E18E' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testBootstrapCreatesLocalBudgetAndLoadsCurrentMonth -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testBootstrapSeedsWheelOfMoneyItems
```

### Task 2: Remove dead bootstrap seeding helpers

**Files:**
- Modify: `MonthlyMoney/AppState.swift`

**Step 1: Remove no-longer-used helpers**
- Delete `seedDefaultsFromSheet`, `seedPlannedItems`, and unused bootstrap helpers if they are no longer referenced.
- Keep unrelated user-created copy/generation behavior intact.

**Step 2: Run focused tests**

Run:
```bash
xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=0D618A40-1A2D-49C7-BD62-4295D747E18E' -only-testing:MonthlyMoneyUITests/MonthlyMoneyUITests/testIPadShowsMonthDailyAndWoMValues
```

### Task 3: Full verification

**Files:**
- No additional code changes expected

**Step 1: Run relevant app tests**

Run:
```bash
xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=0D618A40-1A2D-49C7-BD62-4295D747E18E' -only-testing:MonthlyMoneyTests
```

**Step 2: Run app build**

Run:
```bash
xcodebuild build -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=0D618A40-1A2D-49C7-BD62-4295D747E18E'
```
