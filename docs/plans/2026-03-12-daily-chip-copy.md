# Daily Chip Copy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update Daily card copy, layout, and resting currency formatting without changing Daily budget calculations.

**Architecture:** Keep the existing `DailyBudgetCycleMetrics` and `AppState` logic. Add a tiny presentation helper for Daily card titles and payday label text, then reshape `DailyView` into a fixed 3x2 card grid and update the resting display of editable money fields.

**Tech Stack:** SwiftUI, XCTest, SwiftData-backed app state

---

### Task 1: Add failing presentation tests

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift`

**Step 1: Write the failing test**
- Add a test covering:
  - conditional current-balance title
  - `Days until payday (17th)` style label text

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testDailyPresentationHelpersExposeUpdatedTitlesAndPaydayLabel CODE_SIGNING_ALLOWED=NO`

**Step 3: Write minimal implementation**
- Add a small presentation helper in `DailyView.swift`

**Step 4: Run test to verify it passes**
Run the same command and confirm it passes.

### Task 2: Update DailyView layout and money field presentation

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift`
- Reuse: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthView.swift`

**Step 1: Update copy and layout**
- Use the new titles
- Make the bottom row two half-width cards
- Add the days-until-payday white card

**Step 2: Update editable money field resting format**
- Show the locale currency symbol while not focused
- Keep plain numeric editing while focused
- Increase displayed font size

**Step 3: Run full verification**
Run:
- `xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=35D3E526-9398-48CC-AB55-F4927A5E103A' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO`
- `swift test --package-path MonthlyMoneyCorePackage`
- `xcodebuild build -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
