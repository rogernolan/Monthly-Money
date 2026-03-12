# Editable Money Chip Dismiss Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add one shared animated dismiss interaction for all editable money chips in Daily and Month.

**Architecture:** Introduce a small pure layout helper plus a reusable SwiftUI `EditableMoneyChipValue` component. Keep formatting, focus, and dismiss behavior inside that component, and replace the separate Daily and Month editable field implementations with it.

**Tech Stack:** SwiftUI, XCTest

---

### Task 1: Add failing shared-layout tests

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift`

**Step 1: Write the failing test**
- Replace the Daily-specific layout test with a shared helper test for dismiss-button visibility and reserved trailing width.

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testEditableMoneyChipLayoutShowsDismissButtonOnlyWhileFocused CODE_SIGNING_ALLOWED=NO`

**Step 3: Write minimal implementation**
- Add the helper in app code with static resting/editing presets.

**Step 4: Run test to verify it passes**
- Run the same command and confirm it passes.

### Task 2: Replace Daily-only field with shared editable chip value

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift`
- Create or Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/EditableMoneyChipValue.swift`

**Step 1: Write a failing interaction test if needed**
- Extend the current test file only if the shared helper needs more coverage than the layout test.

**Step 2: Implement the shared component**
- Build the text-field wrapper, focus handling, currency/resting text logic, reserved trailing space, and animated green tick dismiss button.

**Step 3: Wire Daily chips to the shared component**
- Starting budget
- Current balance when separate-account mode is enabled

**Step 4: Run targeted tests**
Run: `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO`

### Task 3: Apply the shared component to Month cards

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthView.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/EditableMoneyChipValue.swift`

**Step 1: Replace Month editable amount fields**
- Update `amountCard` to render the shared component for any editable card.

**Step 2: Verify editable Month chips behave the same as Daily**
- Ensure keyboard dismissal, animation, and formatted/unformatted states are consistent.

**Step 3: Run full verification**
Run:
- `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO`
- `swift test --package-path MonthlyMoneyCorePackage`
- `xcodebuild build -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
