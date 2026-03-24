# Daily Import And Chart Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a hidden daily account with split OFX import UI, silent daily transaction storage for the current payday cycle, and a Daily screen chart.

**Architecture:** Keep the existing monthly OFX parser/import path intact and add a parallel daily-account path that targets a hidden internal account. Build the work in three milestones so UI branching, data retention, and Daily view/chart changes are introduced incrementally and remain test-driven.

**Critical Assumptions:**
- A hidden/internal account can be represented with the current account model plus a small persisted discriminator or identifier. Validate this before wiring import behavior broadly.
- The existing idempotent imported-record storage can be reused for daily-account imports without monthly reconciliation side effects. Validate with focused repository/import tests first.
- Payday-cycle retention can be derived from the same calendar/payday logic already used elsewhere in the app. Validate with unit tests before adding cleanup to refresh/import flows.
- Hidden daily-account records and imported transactions can follow the same single-share budget model and sync through the same private/shared store routing as other account-bound data. Validate with repository/store-selection coverage.

**Tech Stack:** SwiftUI, SwiftData/Core Data hybrid persistence layer, XCTest, existing Nationwide OFX parser/import services.

---

### Task 1: Validate Hidden Daily Account Persistence Shape

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/CoreDataMapping.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing test**
- Add a test proving a budget with separate daily mode can create/find exactly one hidden daily account and that it is excluded from normal visible-account expectations.

**Step 2: Run test to verify it fails**
- Run: `xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testSeparateDailyBudgetCreatesSingleHiddenDailyAccount`
- Expected: FAIL because no hidden daily-account discriminator/lookup exists yet.

**Step 3: Write minimal implementation**
- Add the smallest persisted representation needed to mark/find the hidden daily account.
- Thread that through model mapping and repository accessors.

**Step 4: Run test to verify it passes**
- Run the same targeted test.
- Expected: PASS.

**Step 5: Commit**
- `git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/DomainModels.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/CoreDataMapping.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- `git commit -m "Add hidden daily account persistence"`

### Task 2: Add Migration For Hidden Daily Account Support

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/CoreDataMapping.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthlyMoneyPersistenceFactory.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing test**
- Add a test proving an older-style budget enabling separate daily mode gains a hidden daily account on load/migration without duplicating visible accounts.

**Step 2: Run test to verify it fails**
- Run the targeted migration/bootstrap test.
- Expected: FAIL because migration/bootstrap does not create the hidden account yet.

**Step 3: Write minimal implementation**
- Add the explicit migration/bootstrap path required for the new persisted model shape.
- Ensure repeated refresh/open calls do not duplicate the hidden account.
- Ensure the hidden account is created in the correct store context so a shared budget shares it automatically.

**Step 4: Run test to verify it passes**
- Re-run the targeted migration/bootstrap test.
- Expected: PASS.

**Step 5: Commit**
- `git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/CoreDataMapping.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthlyMoneyPersistenceFactory.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- `git commit -m "Migrate budgets to support hidden daily account"`

### Task 3: Milestone 1 Settings Import UI Split

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/SettingsView.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyUITests/MonthlyMoneyUITests.swift`

**Step 1: Write the failing tests**
- Add coverage for:
  - single `Import OFX` when separate daily mode is off
  - `Import OFX to monthly account` plus `Import OFX to daily account` when it is on

**Step 2: Run tests to verify they fail**
- Run the targeted settings tests.
- Expected: FAIL because the UI has only one import section today.

**Step 3: Write minimal implementation**
- Branch the import section labels/actions in `SettingsView`.
- Keep the current monthly import chooser behavior unchanged.

**Step 4: Run tests to verify they pass**
- Re-run the targeted settings tests.
- Expected: PASS.

**Step 5: Commit**
- `git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/SettingsView.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyUITests/MonthlyMoneyUITests.swift`
- `git commit -m "Split monthly and daily OFX import actions"`

### Task 4: Milestone 1 Daily Import Updates Balance Only

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/SettingsView.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/ImportModels.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing tests**
- Add tests proving daily import:
  - targets the hidden daily account
  - updates current balance from OFX ledger balance
  - does not create monthly planned items or imported transaction rows yet

**Step 2: Run tests to verify they fail**
- Run the targeted daily-import milestone-1 tests.
- Expected: FAIL because daily import path does not exist yet.

**Step 3: Write minimal implementation**
- Add a dedicated daily import entry point that reuses parsing but only applies statement balance to the hidden daily account.

**Step 4: Run tests to verify they pass**
- Re-run the targeted tests.
- Expected: PASS.

**Step 5: Commit**
- `git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/SettingsView.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/ImportModels.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- `git commit -m "Add balance-only daily OFX import"`

### Task 5: Milestone 2 Daily Import Record Storage

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/ImportedTransactionService.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing tests**
- Add tests proving daily-account transaction import is idempotent and stored silently.
- Add tests proving those imported records follow the same shared-budget sync/store routing as other account-scoped imported data.

**Step 2: Run tests to verify they fail**
- Run the targeted daily-import storage tests.
- Expected: FAIL because daily imports still discard transactions.

**Step 3: Write minimal implementation**
- Reuse/import the existing imported-record path for the hidden daily account.
- Avoid monthly reconciliation for this path.
- Keep imported daily records in the same shared/private store as the hidden daily account so one budget share carries all data.

**Step 4: Run tests to verify they pass**
- Re-run the targeted tests.
- Expected: PASS.

**Step 5: Commit**
- `git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/ImportedTransactionService.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- `git commit -m "Store daily account imports idempotently"`

### Task 6: Milestone 2 Payday-Cycle Cleanup

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing tests**
- Add tests proving daily imported transactions outside the current payday cycle are cleared when the cycle advances.

**Step 2: Run tests to verify they fail**
- Run the targeted cleanup tests.
- Expected: FAIL because no retention cleanup exists yet.

**Step 3: Write minimal implementation**
- Add current-cycle detection and cleanup hook during refresh/import/bootstrap as appropriate.

**Step 4: Run tests to verify they pass**
- Re-run the targeted cleanup tests.
- Expected: PASS.

**Step 5: Commit**
- `git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- `git commit -m "Clear stale daily imports outside payday cycle"`

### Task 7: Milestone 3 Daily Chart Data Model

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Create: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyBalanceChartData.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing tests**
- Add tests for payday-cycle chart points:
  - cycle start/end handling
  - ordering
  - balance evolution from imported daily transactions

**Step 2: Run tests to verify they fail**
- Run the targeted chart-data tests.
- Expected: FAIL because no chart-series builder exists yet.

**Step 3: Write minimal implementation**
- Build a small chart data transformer that produces balance-by-day points for the current cycle.

**Step 4: Run tests to verify they pass**
- Re-run the targeted chart-data tests.
- Expected: PASS.

**Step 5: Commit**
- `git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift /Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyBalanceChartData.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- `git commit -m "Add daily balance chart data series"`

### Task 8: Milestone 3 Daily View Layout And Chart

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyUITests/MonthlyMoneyUITests.swift`

**Step 1: Write the failing tests**
- Add tests/smoke coverage for:
  - tighter top layout
  - chart presence below chips
  - navbar title remaining `Daily`

**Step 2: Run tests to verify they fail**
- Run the targeted Daily view tests.
- Expected: FAIL because the chart and tightened layout do not exist yet.

**Step 3: Write minimal implementation**
- Tighten top spacing.
- Keep the nav title behavior.
- Add the chart view beneath the chips using the chart data from task 7.

**Step 4: Run tests to verify they pass**
- Re-run the targeted Daily view tests.
- Expected: PASS.

**Step 5: Commit**
- `git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift /Users/rog/Development/MonthlyMoney/MonthlyMoneyUITests/MonthlyMoneyUITests.swift`
- `git commit -m "Add daily balance chart view"`

### Task 9: Full Verification Sweep

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/docs/plans/2026-03-24-daily-import-and-chart-design.md`
- Modify: `/Users/rog/Development/MonthlyMoney/docs/plans/2026-03-24-daily-import-and-chart.md`

**Step 1: Run focused milestone tests**
- Run the targeted tests added in tasks 1-8.

**Step 2: Run broader regression coverage**
- Run: `xcodebuild test -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests`

**Step 3: Run full build**
- Run: `xcodebuild build -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4'`
- Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit final verification/docs touch-up**
- `git add /Users/rog/Development/MonthlyMoney/docs/plans/2026-03-24-daily-import-and-chart-design.md /Users/rog/Development/MonthlyMoney/docs/plans/2026-03-24-daily-import-and-chart.md`
- `git commit -m "Document daily import and chart rollout"`
