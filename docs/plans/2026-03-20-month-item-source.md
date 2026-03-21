# Month Item Source Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add month-item source states, show them in Month View, make unmatched imports create unplanned month items with copy-forward disabled, and promote unplanned items to planned when the user edits them.

**Architecture:** Add a small source/state enum to `PlannedItem`, stamp that source at item creation time, and update only unmatched import reconciliation to create `PlannedItem` rows instead of transaction-only records. Treat `importedUnplanned` as temporary state: any user edit promotes that item to `manual`. Matched imports must leave the existing planned item source unchanged. Keep the Month View change lightweight by extending the existing metadata row layout and adding a warning icon only for import-created unplanned rows.

**Critical Assumptions:**
- `PlannedItem` is the canonical model for Month View and month totals. Validate by keeping the first test at the package/app model layer and by preserving `MonthCalculationEngine`’s planned-item inputs.
- Persisted planned items can safely gain a new source field with a default `manual` value. Validate with existing persistence round-trip tests before changing reconciliation behavior.
- Replacing unmatched imported transaction creation with planned-item creation will not break any visible app flow, because Month View currently does not render `Transaction` rows. Validate with focused reconciliation tests and a full app build.
- Promoting edited unplanned items to `manual` is the intended product behavior for this slice. Validate with an app-side test around the existing edit path.

**Tech Stack:** Swift, SwiftUI, SwiftData, Core Data mapping layer, XCTest, existing import/reconciliation services

---

### Task 1: Add failing tests for planned-item source metadata

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`

**Step 1: Write a failing app persistence round-trip test**

Extend the planned-item persistence expectations so a newly added source field round-trips correctly and defaults to `manual`.

**Step 2: Write a failing package test for copied-item source stamping**

Add a test that copies a planned item into a new month and expects the copy to be marked `copiedFromPreviousMonth`.

**Step 3: Run the targeted tests to verify they fail**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter SharingAndMonthTests`

Expected: FAIL because the source enum/field does not exist yet

**Step 4: Run the app-side targeted tests**

Run: `xcodebuild test -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MonthlyMoneyTests`

Expected: FAIL in the new persistence assertions, or pass all tests but show only the existing simulator harness restart issue with the new assertions failing before implementation

**Step 5: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift
git commit -m "test: add failing month item source coverage"
```

### Task 2: Add planned-item source to models and persistence

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/CoreDataMapping.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/CoreDataCloudKitProbe.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Add a `PlannedItemSource` enum**

Add:

- `manual`
- `copiedFromPreviousMonth`
- `importedUnplanned`

to both app and package model layers.

**Step 2: Add the stored field to `PlannedItem`**

Add `source: PlannedItemSource` with default `.manual` to both model copies.

**Step 3: Update Core Data mapping**

Add the new persisted field and round-trip it through the Core Data mapper.

**Step 4: Re-run the targeted tests**

Run:

- `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter SharingAndMonthTests`
- `xcodebuild -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Expected: package metadata tests pass and app builds cleanly

**Step 5: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/DomainModels.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/CoreDataMapping.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/CoreDataCloudKitProbe.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift
git commit -m "feat: add planned item source state"
```

### Task 3: Add failing reconciliation tests for unmatched imports creating unplanned month items

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift`

**Step 1: Replace the unmatched-import expectation**

Change the existing unmatched-import test so it expects:

- no transaction is created
- one planned item is created
- that planned item has `source = importedUnplanned`
- that planned item has `copiesToNextMonthAutomatically = false`
- the imported record links to the created planned item

**Step 2: Add a matched-import regression expectation**

Assert that when reconciliation matches an existing planned item, it marks that item paid but does not change its existing `source`.

**Step 3: Add an idempotency test for repeated unmatched reconciliation**

Run reconciliation twice and assert there is still only one import-created planned item.

**Step 4: Run the targeted package tests to verify they fail**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter ImportedTransactionReconciliationServiceTests`

Expected: FAIL because unmatched reconciliation still creates transactions

**Step 5: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift
git commit -m "test: add failing unplanned import item tests"
```

### Task 4: Implement unmatched import creation as planned items

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/ImportedTransactionReconciliationService.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/Repository.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/ImportedTransactionReconciliationService.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/Repository.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift`

**Step 1: Add repository support for saving and querying created planned items**

Expose the minimal helpers needed by reconciliation to create and save `PlannedItem` rows idempotently.

**Step 2: Change unmatched reconciliation in the package**

Replace transaction creation with planned-item creation using:

- `label = imported payee`
- `matchingString = imported payee`
- sign-to-type mapping
- `copiesToNextMonthAutomatically = false`
- `source = importedUnplanned`
- `isPaid = true`

**Step 3: Keep imported-record linkage idempotent**

Reuse `appliedPlannedItemID` for both matched existing items and created unplanned items, or add a separate created-item link only if the distinction is essential during implementation.

**Step 4: Mirror the same behavior into the app target**

Update the duplicated app-side reconciliation service to match the package behavior.

**Step 5: Re-run the targeted package tests**

Run:

- `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter ImportedTransactionReconciliationServiceTests`
- `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage`

Expected: PASS

**Step 6: Build the app**

Run: `xcodebuild -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/ImportedTransactionReconciliationService.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/Repository.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/ImportedTransactionReconciliationService.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/Repository.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift
git commit -m "feat: create unplanned month items from imports"
```

### Task 5: Stamp source during manual creation and month copying

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`

**Step 1: Set manual source on user-created items**

Ensure `createEntry` and any other direct item-creation helpers explicitly stamp `.manual`.

**Step 2: Set copied source on populated next-month items**

Update `copyItems` so copies are stamped `.copiedFromPreviousMonth`.

**Step 3: Promote edited imported-unplanned items to manual**

Update the existing edit path so any change to an `importedUnplanned` item sets its source to `.manual`.

**Step 4: Re-run focused tests**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter SharingAndMonthTests`

Expected: PASS

**Step 5: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift
git commit -m "feat: stamp month item source on creation"
```

### Task 6: Add month-row source text and unplanned warning icon

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/MonthView.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write failing UI-content helper tests**

Add tests for:

- source label text per state
- metadata lines include the source label
- imported-unplanned rows request a warning icon

**Step 2: Extend `MonthItemRowContent`**

Add helpers for:

- source caption text
- metadata lines that include source
- `showsUnplannedWarning(for:)`

**Step 3: Update the row layout**

Add a red `exclamationmark.circle.fill` just left of the checkbox when the item source is `importedUnplanned`.

**Step 4: Re-run focused app tests or build if the simulator harness is unstable**

Run:

- `xcodebuild -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MonthlyMoneyTests build-for-testing`
- if stable, `xcodebuild ... test -only-testing:MonthlyMoneyTests`

Expected: helper assertions pass; if the harness restarts again, document that and rely on the successful build plus package coverage

**Step 5: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/MonthView.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift
git commit -m "feat: show month item source and import warning"
```

### Task 7: Final verification

**Files:**
- Verify only

**Step 1: Run the full package suite**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage`

Expected: PASS

**Step 2: Build the app**

Run: `xcodebuild -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Expected: BUILD SUCCEEDED

**Step 3: Run app tests if the harness permits**

Run: `xcodebuild test -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MonthlyMoneyTests`

Expected: pass, or no assertion failures with only the known simulator restart issue if it recurs

**Step 4: Commit**

```bash
git add -A
git commit -m "test: verify month item source flow"
```
