# Every n Days Repeat Design

## Goal

Add a repeat mode for planned items that advances by a positive integer number of calendar days rather than repeating on a fixed day of the month. The canonical example is a UK pension payment every 28 days.

## User experience

The existing date picker gains an `Every n days` option alongside `Floating` and fixed days. Selecting it reveals a secondary number field labelled `Repeat days`.

The field accepts only a positive integer. Invalid, empty, zero, negative, or non-integer values prevent saving.

When a brand-new item is saved with this mode, the entered row is the only occurrence created in the selected month. It is the anchor occurrence and is not backfilled with additional occurrences from that month.

When an existing item is changed to this mode, the edited row becomes the anchor occurrence. Earlier dates are never inferred. If later occurrences derived from the anchor fall within the selected month, the app offers to create all of them. Declining leaves the anchor saved without those additional rows.

## Persistence model

`PlannedItem` gains:

- `repeatDays: Int?`, nil for existing repeat modes and otherwise a positive interval.
- `recurrenceID: UUID?`, shared by all occurrences in one every-n-days series.

The fields are added to both the app and core package model definitions and included in the explicit SwiftData/Core Data model migration required by the project. Existing items remain unchanged with both fields nil.

Every occurrence stores its concrete calendar position using its existing `monthKey` and `dueDay`. The recurrence ID prevents unrelated items with identical visible fields from being grouped together.

Changing an item into every-n-days starts a new series with a new recurrence ID. Generated same-month and next-month occurrences inherit that ID and interval. Changing an occurrence back to another repeat mode clears the interval and recurrence ID for that row.

## Month-copy behavior

For ordinary floating and fixed-day items, existing copy behavior remains unchanged.

For every-n-days items copied from one month into the next:

1. Group source occurrences by recurrence ID.
2. Select only the latest occurrence in each group as the continuation anchor.
3. Add the repeat interval repeatedly to that anchor's concrete date.
4. Create one copied row for every resulting date whose calendar month is the target month.
5. Preserve the series ID, interval, item details, and automatic-copy setting on each generated row; reset paid state as with existing copies.

This means a series with several occurrences in the source month advances once from its latest occurrence, while a target month can receive multiple rows. Calendar arithmetic handles month lengths, year changes, and leap years.

## Code boundaries

- `MonthItemEditorDraft` owns picker state, repeat-day text, validation, and conversion to persisted repeat fields.
- `PlannedItem` owns repeat metadata and pure occurrence/copy helpers where practical.
- `AppState` owns save-time coordination, including the optional same-month population prompt and repository writes.
- The month editor presents the conditional field and confirmation UI but does not calculate recurrence dates.

## Testing

Add focused unit tests covering:

- picker/draft initialization and positive-integer validation;
- new every-n-days items creating only their anchor occurrence;
- existing-item conversion offering and creating all later same-month occurrences;
- 28-day sequences across month and year boundaries;
- multiple occurrences in a target month;
- only the latest source occurrence continuing a series;
- separate recurrence IDs preventing accidental grouping;
- preservation of ordinary floating and fixed-day copy behavior;
- explicit migration defaults for existing items.

Each milestone must build and run the relevant XCTest targets, followed by the full test suite before completion.

## Error handling

Invalid repeat-day input keeps Save disabled and does not write partial recurrence metadata. If generation or repository persistence fails, the existing error handling reports the failure and leaves the source anchor intact; generated writes should be performed through the repository's normal transaction/error path.
