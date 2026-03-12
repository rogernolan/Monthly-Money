# MonthlyMoney Handoff

Date: 2026-03-04
Repo: /Users/rog/Development/MonthlyMoney

## Current Focus
Month tab behavior and month lifecycle logic (current + next month generation) for the iOS app version of the spreadsheet.

## What Is Implemented

### Data/logic state
- Startup/bootstrap now targets the **current month** (not hard-coded February).
- Bootstrap ensures:
  - current month exists and has seed/copy data
  - next month exists by copying current month rows with `isPaid = false`
- Copy flow preserves row fields (label/type/amount/due/notes) and resets paid state.
- Logic is idempotent (won’t duplicate if target month already has rows).
- Future-month opening balance path was updated to derive from previous month closing logic.
- Floating items sort to top (day zero semantics).

### Month UI state
- Removed "Month" header title.
- Month control simplified to arrows + month name; tapping month label resets to current month.
- Current balance shows currency symbol when not editing; symbol is removed while editing.
- For future months, first card uses opening-balance behavior/title path.
- Past months show paid state but toggles are disabled.

### Tests/build state (last known)
- iOS project build succeeded.
- Swift package tests passed (`MonthlyMoneyCorePackage`).

## Open Product Decisions / Pending Work
- Reimplement Month tab against latest updated spec (user indicated current implementation still diverges).
- Confirm exact default sample-data set from spreadsheet and desired month population policy.
- Confirm if startup should always force selected month to current month in app state.
- Continue phasing out v1 account sharing complexity if not needed yet in UI path.

## Important Constraints Agreed In Thread
- Use English account terminology (not US-centric naming where avoidable).
- Do not ask permission to kill simulator/emulator/xcodebuild processes started by agent.
- For tests that regress, assume real bug first.

## Files Most Recently Touched
- `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthView.swift`

## Working Tree Notes
- Repository currently has unrelated/dirty changes, including generated `.build` artifacts under `MonthlyMoneyCorePackage/.build`.
- New docs added at root during this work period: `SPEC.md`, `AGENTS.md` (currently untracked in this repo state).

## Suggested Next Session First Steps
1. Cleanly separate generated `.build` noise from source diffs before further feature work.
2. Validate month bootstrap behavior on fresh install and with existing persisted data.
3. Reimplement Month tab layout/interaction from latest spec revision before expanding other tabs.
