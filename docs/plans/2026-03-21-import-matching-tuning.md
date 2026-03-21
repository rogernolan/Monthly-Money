# Import Matching Tuning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make OFX reconciliation reliable on re-import by exposing statement keywords in the month-item editor, matching on text plus amount/date tolerance, updating matched item due days from OFX, and promoting edited imported-unplanned items to manual.

**Architecture:** Keep import-row dedupe based on OFX source identity, but strengthen month-item reconciliation with a composite matcher that uses statement keywords (fallback to label), amount tolerance, and due-day tolerance. Reconciliation continues to write through the existing `ImportedTransactionReconciliationService`, while editing flows through `MonthItemEditorView` and `AppState.update(item:...)`.

**Critical Assumptions:**
- `PlannedItem.matchingString` is already persisted and can be surfaced directly in the editor. Validate by adding a failing editor/update-path test first.
- Reconciliation can distinguish business-level month-item matches from source-level OFX dedupe without new persistence models. Validate with failing reconciliation tests before editing implementation code.
- Existing imported-unplanned items should be reused on re-import via the same tolerance matcher. Validate with a failing regression test before changing the matcher.

**Tech Stack:** SwiftUI, SwiftData repository pattern, XCTest, Decimal money handling, OFX import pipeline

---

### Task 1: Cover statement keywords editing and imported-item promotion

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/AppStateTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/MonthView.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/AppState.swift`

**Step 1: Write the failing tests**

Add tests that prove:

- updating a month item can persist `matchingString`
- clearing `matchingString` is allowed
- editing an `importedUnplanned` item promotes `source` to `.manual`

**Step 2: Run the targeted tests to verify they fail**

Run:

```bash
xcodebuild test -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MonthlyMoneyTests/AppStateTests
```

Expected: failing assertions or compile errors because `matchingString` is not yet exposed through the update path.

**Step 3: Write the minimal implementation**

- add a `Statement keywords` field to `MonthItemEditorView`
- thread `matchingString` through the editor save path
- update `AppState.update(item:...)` to persist it
- if the item source is `.importedUnplanned` and any edit is saved, promote it to `.manual`

**Step 4: Run the targeted tests to verify they pass**

Run the same `xcodebuild test` command.

Expected: PASS for the new editor/update behavior.

**Step 5: Commit**

```bash
git -C /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import add \
  MonthlyMoneyTests/AppStateTests.swift \
  MonthlyMoney/MonthView.swift \
  MonthlyMoney/AppState.swift
git -C /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import commit -m "feat: expose statement keywords in month editor"
```

### Task 2: Lock in the new composite reconciliation matcher in tests

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/ImportedTransactionReconciliationServiceTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/ImportedTransactionReconciliationService.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/ImportedTransactionReconciliationService.swift`

**Step 1: Write the failing tests**

Add regression tests that prove:

- text + amount (+/- 5%) + due-day (+/- 3 days) matches an unpaid planned item
- amount outside tolerance does not match
- date outside tolerance does not match
- a previously created `importedUnplanned` item is reused on re-import instead of creating a duplicate

**Step 2: Run the package tests to verify they fail**

Run:

```bash
swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter ImportedTransactionReconciliationServiceTests
```

Expected: FAIL because the matcher is still text-only and does not reuse imported-unplanned items with the new tolerance rule.

**Step 3: Write the minimal implementation**

- add helper logic for normalized text match, relative amount delta, and day delta
- require all three conditions to pass for eligible candidates
- reuse the same matcher for planned items and imported-unplanned item recognition
- keep `FITID`-based import linkage as the first idempotency check

**Step 4: Run the package tests to verify they pass**

Run the same `swift test` command.

Expected: PASS for the new reconciliation rules.

**Step 5: Commit**

```bash
git -C /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import add \
  MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift \
  MonthlyMoneyTests/ImportedTransactionReconciliationServiceTests.swift \
  MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/ImportedTransactionReconciliationService.swift \
  MonthlyMoney/ImportedTransactionReconciliationService.swift
git -C /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import commit -m "feat: add tolerant import reconciliation matching"
```

### Task 3: Set OFX posted day on matched and created month items

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyTests/ImportedTransactionReconciliationServiceTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/ImportedTransactionReconciliationService.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/ImportedTransactionReconciliationService.swift`

**Step 1: Write the failing tests**

Add tests that prove:

- a matched planned item has its `dueDay` updated to the OFX posted day
- a newly created imported-unplanned item gets `dueDay` from the OFX posted day

**Step 2: Run the package tests to verify they fail**

Run:

```bash
swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage --filter ImportedTransactionReconciliationServiceTests
```

Expected: FAIL because matched items currently preserve old due day and newly created imported items do not set one.

**Step 3: Write the minimal implementation**

- derive posted day from `record.postedAt`
- assign it to matched items before saving
- assign it to newly created imported-unplanned items

**Step 4: Run the package tests to verify they pass**

Run the same `swift test` command.

Expected: PASS for due-day propagation.

**Step 5: Commit**

```bash
git -C /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import add \
  MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/ImportedTransactionReconciliationServiceTests.swift \
  MonthlyMoneyTests/ImportedTransactionReconciliationServiceTests.swift \
  MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/ImportedTransactionReconciliationService.swift \
  MonthlyMoney/ImportedTransactionReconciliationService.swift
git -C /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import commit -m "feat: carry OFX day into month items"
```

### Task 4: Verify the full import and app integration path

**Files:**
- Modify if needed: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/SettingsView.swift`
- Modify if needed: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/ImportModels.swift`
- Modify if needed: `/Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney/ImportedTransactionService.swift`

**Step 1: Run package tests**

Run:

```bash
swift test --package-path /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoneyCorePackage
```

Expected: PASS

**Step 2: Run app build**

Run:

```bash
xcodebuild -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
```

Expected: BUILD SUCCEEDED

**Step 3: Run targeted app tests**

Run:

```bash
xcodebuild test -project /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:MonthlyMoneyTests/AppStateTests \
  -only-testing:MonthlyMoneyTests/ImportedTransactionReconciliationServiceTests
```

Expected: PASS

**Step 4: Fix any integration wording or alert text drift**

- make sure success summaries still describe created unplanned items accurately
- avoid touching unrelated import service code unless verification reveals a real issue

**Step 5: Commit**

```bash
git -C /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import add \
  MonthlyMoney/SettingsView.swift \
  MonthlyMoney/ImportModels.swift \
  MonthlyMoney/ImportedTransactionService.swift
git -C /Users/rog/Development/MonthlyMoney/.worktrees/codex-ofx-import commit -m "test: verify tolerant import reconciliation end to end"
```
