# Import Reconciliation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a reconciliation step that matches imported OFX rows to planned items using a simple substring matcher, creates first-class transactions for unmatched rows, stays idempotent, and removes bootstrap sample data.

**Architecture:** Extend the existing imported-row pipeline rather than matching during file parsing. Add planned-item matcher metadata, add transaction source-identity fields for idempotency, and implement a small reconciliation service that updates imported rows with the applied result.

**Critical Assumptions:**
- Nationwide OFX `FITID` is present and stable enough to use as the primary unmatched-transaction idempotency key. Validate with existing parser fixture and tests.
- Current transaction UI can continue using `note` as the visible payee field for newly created transactions. Validate by keeping UI changes out of scope unless tests show a missing field is required.
- The app can start with an empty budget/account shell after bootstrap seeding is removed. Validate with an `AppState.bootstrapIfNeeded` test before deleting the seed path.

**Tech Stack:** Swift, SwiftUI, SwiftData, Core Data mapping layer, XCTest, existing repository/import pipeline

---

### Task 1: Add failing model and repository tests for reconciliation metadata

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Step 1: Write a failing package test for planned-item matcher fallback**

Add a unit test that creates planned items with and without `matchingString` and asserts the intended matching text is `matchingString` first, then `label`.

**Step 2: Write a failing app persistence test for new stored fields**

Extend the Core Data round-trip tests so they expect:

- `PlannedItem.matchingString`
- `Transaction.sourceKind`
- `Transaction.sourceExternalTransactionID`
- `Transaction.sourcePostedAt`
- `ImportedTransactionRecord.appliedPlannedItemID`
- `ImportedTransactionRecord.createdTransactionID`

**Step 3: Run the targeted tests to verify they fail**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter SharingAndMonthTests`

Expected: FAIL because the new fields and helpers do not exist yet

**Step 4: Run the app-side target for the persistence expectations**

Run: `xcodebuild test -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MonthlyMoneyTests`

Expected: FAIL in the new persistence assertions

**Step 5: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift
git commit -m "test: add failing reconciliation metadata coverage"
```

### Task 2: Add reconciliation metadata to models and persistence

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/CoreDataMapping.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/CoreDataAccountDataStore.swift`

**Step 1: Add the new model fields**

Add:

- `PlannedItem.matchingString`
- `Transaction.sourceKind`
- `Transaction.sourceExternalTransactionID`
- `Transaction.sourcePostedAt`
- `ImportedTransactionRecord.appliedPlannedItemID`
- `ImportedTransactionRecord.createdTransactionID`

in both the app target and package models.

**Step 2: Update Core Data mapping and entity definitions**

Add the matching attributes and round-trip mapping in the Core Data builder and mapper.

**Step 3: Update any budget relationship repair logic if needed**

Keep imported record relationship repair intact with the expanded imported-record schema.

**Step 4: Re-run the targeted tests**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter SharingAndMonthTests`

Expected: PASS for package-side metadata expectations

**Step 5: Re-run app tests**

Run: `xcodebuild test -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MonthlyMoneyTests`

Expected: app tests pass, or the suite passes with only the known simulator restart harness issue and no actual failing test cases

**Step 6: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/DomainModels.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/CoreDataMapping.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/CoreDataAccountDataStore.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift
git commit -m "feat: add reconciliation metadata fields"
```

### Task 3: Add failing reconciliation service tests

**Files:**
- Create: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift`

**Step 1: Write a failing test for matching with `matchingString`**

Create:

- an account
- a planned item with `matchingString = "tesco"`
- an imported record with payee `"TESCO STORES 123"`

Assert reconciliation marks the planned item paid, updates the amount, and records `appliedPlannedItemID`.

**Step 2: Write a failing test for fallback to `label`**

Use a planned item with empty `matchingString` and label `"Council Tax"`, and assert it still matches an imported row with payee containing that phrase.

**Step 3: Write a failing test for unmatched row transaction creation**

Assert reconciliation creates exactly one transaction whose `note` equals the imported payee and whose source identity fields are populated from the imported row.

**Step 4: Write a failing idempotency test**

Run reconciliation twice over the same imported records and assert:

- no duplicate transactions are created
- matched planned items are not re-applied
- imported rows remain linked to the same result

**Step 5: Run the new test target**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter ImportedTransactionReconciliationServiceTests`

Expected: FAIL because the reconciliation service does not exist yet

**Step 6: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift
git commit -m "test: add failing reconciliation service tests"
```

### Task 4: Implement the reconciliation service in the package

**Files:**
- Create: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/ImportedTransactionReconciliationService.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/Repository.swift`
- Test: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift`

**Step 1: Add repository helpers needed by reconciliation**

Add the minimal read/write surface needed for:

- fetching transactions for an account
- saving updated planned items
- saving updated imported records
- creating transactions idempotently

Keep the API narrow and aligned with current repository patterns.

**Step 2: Implement planned-item matcher selection**

Add a small helper that returns `matchingString` when non-empty, else `label`, then does normalized case-insensitive substring matching.

**Step 3: Implement matched-row handling**

For each unapplied imported row:

- find planned items in the same month
- ignore paid items
- choose the best deterministic match
- mark the planned item paid
- update its amount
- set `appliedPlannedItemID` on the imported row

**Step 4: Implement unmatched-row handling**

Create a transaction only if one does not already exist with the same source identity.

Populate:

- `note = imported payee`
- `sourceKind`
- `sourceExternalTransactionID`
- `sourcePostedAt`

Then set `createdTransactionID` on the imported row.

**Step 5: Run the reconciliation tests**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter ImportedTransactionReconciliationServiceTests`

Expected: PASS

**Step 6: Run the full package suite**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage`

Expected: PASS

**Step 7: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/ImportedTransactionReconciliationService.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/Repository.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift
git commit -m "feat: reconcile imported transactions into budget data"
```

### Task 5: Mirror reconciliation support into the app target and wire post-import apply

**Files:**
- Create: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/ImportedTransactionReconciliationService.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/Repository.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/SettingsView.swift`

**Step 1: Mirror the package reconciliation service into the app target**

Follow the current package/app duplication pattern already used for parser and import persistence.

**Step 2: Reconcile immediately after a successful import**

After storing imported rows in `AppState.importOFXData`, run reconciliation for the selected account.

**Step 3: Return a richer import summary**

Expand the success message to include:

- imported rows inserted
- duplicates skipped
- planned items matched
- new transactions created

**Step 4: Keep errors user-friendly**

Parser, persistence, and reconciliation failures should still surface in the existing import alert path without crashing the app.

**Step 5: Build the app**

Run: `xcodebuild -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/ImportedTransactionReconciliationService.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/Repository.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/SettingsView.swift
git commit -m "feat: apply imported transactions after OFX import"
```

### Task 6: Remove bootstrap sample data with failing-first app tests

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift`

**Step 1: Write a failing bootstrap test**

Assert that after `bootstrapIfNeeded()` on a fresh repository:

- an active budget/account exists
- no planned items exist
- no wheel-of-money items exist
- no sample balances are injected

**Step 2: Remove seed/sample paths**

Delete the calls that populate starter sheet data, sample balances, WoM seed data, and auto-copied future-month sample content from bootstrap and restore flows.

**Step 3: Run the targeted app tests**

Run: `xcodebuild test -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MonthlyMoneyTests`

Expected: tests pass, or the suite passes with only the known simulator restart harness issue and no actual failing test cases

**Step 4: Commit**

```bash
git add /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/MonthlyMoneyTests.swift /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift
git commit -m "feat: remove bootstrap sample budget data"
```

### Task 7: Final verification

**Files:**
- No code changes required unless verification uncovers an issue

**Step 1: Run full package verification**

Run: `swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage`

Expected: PASS

**Step 2: Run app build verification**

Run: `xcodebuild -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Expected: BUILD SUCCEEDED

**Step 3: Run app test verification**

Run: `xcodebuild test -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MonthlyMoneyTests`

Expected: all `MonthlyMoneyTests` test cases pass; if `xcodebuild` still exits 65, capture the log and confirm there are zero failing test cases and the failure is only the existing simulator restart harness issue

**Step 4: Summarize any residual risk**

Call out:

- matching is substring-based and may need regex later
- automatic post-import reconciliation may need a manual review step in the future
- existing `xcodebuild` harness instability if still present

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: reconcile imported OFX rows into planned items and transactions"
```
