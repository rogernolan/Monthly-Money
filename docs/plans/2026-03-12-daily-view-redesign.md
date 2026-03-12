# Daily View Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current Daily tab with a payday-cycle dashboard that uses the new budget-level switch and shows three editable chips plus three calculated chips.

**Architecture:** Keep Month logic intact and add a small Daily-specific calculation layer in `AppState` backed by persisted budget inputs. Reuse Month chip styling for presentation, and keep the separate-account switch as a source-of-truth toggle for whether Daily balance is editable or derived from Month projected closing balance.

**Tech Stack:** SwiftUI, SwiftData `@Model`, XCTest, existing `AppState` / repository layer.

---

### Task 1: Persist the Daily input fields on `Budget`

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/Repository.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AccountSharingService.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/AccountSharingService.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`

**Step 1: Write the failing test**
Add assertions in `testLocalBudgetDefaults` for:
- `dailyBudgetAmount == 0`
- `dailyBudgetPaydayDay == 1` (or chosen default)

**Step 2: Run test to verify it fails**
Run: `swift test --package-path MonthlyMoneyCorePackage --filter SharingAndMonthTests/testLocalBudgetDefaults`
Expected: FAIL because `Budget` has no new fields yet.

**Step 3: Write minimal implementation**
Add to `Budget` in app + core:
- `dailyBudgetAmount: Decimal`
- `dailyBudgetPaydayDay: Int`
with defaults.
Update SwiftData budget upsert logic to persist them.
Preserve them during whole-budget sharing.

**Step 4: Run test to verify it passes**
Run: `swift test --package-path MonthlyMoneyCorePackage --filter SharingAndMonthTests/testLocalBudgetDefaults`
Expected: PASS.

**Step 5: Commit**
```bash
git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/DomainModels.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/Repository.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoney/AccountSharingService.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/AccountSharingService.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift

git commit -m "persist daily budget inputs on budget"
```

### Task 2: Add pure payday-cycle calculations to app state support code

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing tests**
Add pure-ish tests for:
- payday wrap across a month boundary
- daily budget calculation
- ahead/behind calculation
- current daily budget calculation

Use explicit dates such as March 12, 2026 and a payday on April 1, 2026 via helper functions that accept a `Date` or date components.

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL with missing helpers / wrong values.

**Step 3: Write minimal implementation**
Add helpers in `AppState` (or a tiny nested helper type) for:
- previous payday date
- next payday date
- cycle days
- remaining days to payday
- elapsed cycle days
- daily budget
- expected balance today
- ahead/behind
- current daily budget

Make helpers deterministic by accepting a `Date` input for testability.

**Step 4: Run test to verify it passes**
Run the same `xcodebuild test ... -only-testing:MonthlyMoneyTests ...` command.
Expected: PASS.

**Step 5: Commit**
```bash
git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift

git commit -m "add daily payday cycle calculations"
```

### Task 3: Expose Daily-specific editable state in `AppState`

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write the failing tests**
Add tests for:
- active budget exposes persisted `dailyBudgetAmount` and `dailyBudgetPaydayDay`
- when `usesSeparateAccountForDailyBudget` is `false`, Daily current balance equals Month projected closing balance
- when `true`, Daily current balance uses a stored editable value

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because the new app-state surface does not exist yet.

**Step 3: Write minimal implementation**
Add to `AppState`:
- `dailyBudgetAmount` binding-backed computed property
- `dailyBudgetPaydayDay` binding-backed computed property
- `dailyBudgetCurrentBalance` property that switches between derived and editable modes
- optional local storage keyed by cycle/month for the editable separate-account balance if needed for this pass

Persist budget-backed values with `repository.saveBudget`.

**Step 4: Run test to verify it passes**
Run the same hosted test command.
Expected: PASS.

**Step 5: Commit**
```bash
git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift

git commit -m "expose daily budget state in app state"
```

### Task 4: Replace the `DailyView` UI

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift`
- Optionally modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthView.swift` (only if extracting shared chip styling is cleaner)
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift` (only for lightweight helper coverage, not layout assertions)

**Step 1: Write the failing test**
If you extract styling or labels into helpers, add a small test for the color-state helper. Do not add brittle view-tree snapshot tests.

**Step 2: Run test to verify it fails**
Run the relevant hosted test command if you added one.
Expected: FAIL for missing helper.

**Step 3: Write minimal implementation**
Rebuild `DailyView` to:
- remove the old sections
- show three editable chips: `Budget`, `Current Balance`, `Payday`
- show three calculated chips: `Daily budget`, `Ahead / behind`, `Current daily budget`
- make `Current Balance` non-editable when `usesSeparateAccountForDailyBudget == false`
- style positive/neutral/negative states to match Month cards
- use the system currency symbol

Keep the diff scoped to Daily unless a tiny shared chip helper meaningfully reduces duplication.

**Step 4: Run test/build to verify it passes**
Run:
- `xcodebuild build -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS.

**Step 5: Commit**
```bash
git add /Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthView.swift \
  /Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift

git commit -m "rebuild daily view around payday cycle"
```

### Task 5: Full verification

**Files:**
- No code changes required unless verification finds a bug.

**Step 1: Run package tests**
Run: `swift test --package-path MonthlyMoneyCorePackage`
Expected: PASS.

**Step 2: Run hosted app tests**
Run: `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS.

**Step 3: Run app build**
Run: `xcodebuild build -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
Expected: PASS.

**Step 4: Inspect git status**
Run: `git status --short`
Expected: only intended source changes, no accidental `.build` artifacts staged.

**Step 5: Commit any verification-driven fixes**
```bash
git add <fixed-files>
git commit -m "fix daily view verification issues"
```
