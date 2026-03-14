# iPad Chip Layout Design

## Goal
Add a UI regression test for iPad layout and make Month and Daily chip values scale up on larger screens so the value text remains visible and legible on iPad.

## Context
The current chip views use fixed value font sizes:
- Month chip values use `25.5`
- Daily chip values use `28`

Those fixed sizes do not adapt to regular-width layouts. The bug report is that chip numbers do not render correctly on large screens. The app already shares a common visual language between Month and Daily, so the safest fix is to introduce one shared typography rule rather than diverging the two screens.

## Chosen Approach
Use size-class-based chip typography and a single iPad UI test path.

Why this approach:
- small diff
- directly targets the rendering bug
- gives us a stable UITest regression for iPad
- keeps Month and Daily chip values visually consistent

## Non-Goals
- redesigning chip layout for iPad
- changing chip colors or card structure
- creating separate iPad-only views
- adding screenshot-based snapshot testing

## Design
### Shared Typography
Introduce a small shared helper that returns chip value font sizes for compact and regular horizontal size classes.

Expected behavior:
- compact width keeps current sizes roughly as-is
- regular width increases value text noticeably for iPad
- the helper is used by both Month and Daily chip values

This keeps the implementation simple and avoids geometry-heavy layout code.

### Accessibility Hooks
Add explicit accessibility identifiers to the key value elements so UI tests can target them reliably.

Month value identifiers:
- `month-chip-current-balance-value`
- `month-chip-projected-balance-value`
- `month-chip-outgoings-due-value`
- `month-chip-credits-due-value`

Daily value identifiers:
- `daily-chip-budget-value`
- `daily-chip-average-budget-value`
- `daily-chip-current-balance-value`
- `daily-chip-ahead-behind-value`
- `daily-chip-current-daily-budget-value`
- `daily-chip-days-until-payday-value`

The identifiers should be attached to the rendered value text or editable value component.

### UI Test Coverage
Add a new UITest that launches the app in an iPad simulator and verifies:
- Month chip values exist and are hittable
- Daily chip values exist and are hittable after switching tabs

This is a pragmatic UI regression test. It does not prove exact typography size, but it does prove that the value content is rendering and accessible on iPad.

## Files Expected To Change
- `MonthlyMoney/MonthView.swift`
- `MonthlyMoney/DailyView.swift`
- `MonthlyMoney/EditableMoneyChipValue.swift`
- `MonthlyMoneyUITests/MonthlyMoneyUITests.swift`

Possible small helper file if needed:
- `MonthlyMoney/ChipTypography.swift`

## Testing Strategy
### UI Test
Run the new test on an iPad simulator target, for example:
- `platform=iOS Simulator,name=iPad Pro 13-inch (M4)`

### Existing Verification
Also run:
- app unit tests
- core package tests
- full app build

## Risks
- attaching identifiers to the wrong view layer could make the UITest flaky
- increasing font sizes without sharing the rule could make Month and Daily drift visually

## Mitigation
- keep identifiers on the actual visible value view
- centralize size choice in a shared helper
- verify on both Month and Daily in the same UITest
