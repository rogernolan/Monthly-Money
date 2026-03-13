# Editable Money Chip Affordance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a visible edit badge and whole-chip tap-to-edit interaction to all shared editable money chips.

**Architecture:** Extend the shared `EditableMoneyChipValue` component and its small pure layout helper rather than changing Month and Daily separately. Keep the existing dismiss interaction and add a permanent top-left edit badge plus whole-chip focus behavior.

**Tech Stack:** SwiftUI, XCTest

---

### Task 1: Add failing layout-helper test

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/EditableMoneyChipValue.swift`

**Step 1: Write the failing test**
- Add a test asserting the shared layout helper exposes a visible edit badge in both resting and editing states.

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testEditableMoneyChipLayoutShowsPersistentEditBadge CODE_SIGNING_ALLOWED=NO`

**Step 3: Write minimal implementation**
- Extend the helper with the badge visibility state.

**Step 4: Run test to verify it passes**
- Run the same command and confirm it passes.

### Task 2: Implement the shared badge and tap target

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/EditableMoneyChipValue.swift`

**Step 1: Add the top-left edit badge**
- Render a small grey rounded square with a pencil icon that stays visible while editing.

**Step 2: Make the whole component tappable**
- Tapping anywhere on the chip should focus the field and start editing.

**Step 3: Keep existing dismiss behavior intact**
- Preserve the green tick button, spring animation, and formatted/unformatted text transitions.

**Step 4: Run full verification**
Run:
- `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO`
- `swift test --package-path MonthlyMoneyCorePackage`
- `xcodebuild build -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
