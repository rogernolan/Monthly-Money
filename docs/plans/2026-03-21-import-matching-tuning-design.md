# Import Matching Tuning Design

## Goal

Make OFX reconciliation reliable enough for real re-import workflows by exposing statement keywords in the editor, matching on text plus amount/date tolerance, and carrying the OFX posted day into month items.

## Context

The current reconciliation path is still too strict and too opaque:

- month items cannot be edited with a dedicated statement-matching field
- matching is effectively text-only
- auto-created unplanned items do not carry the OFX posted day into `dueDay`
- editing an imported-unplanned item does not yet promote it to a user-planned item

That leads to the failure the user reported: if an imported item is unticked and the file is re-imported, the app does not reliably find the same month entry and mark it complete again.

## Approaches

### 1. Recommended: composite matcher for month items, source identity for import rows

Keep `FITID` as the primary dedupe identity for imported source records, but use a separate month-item matcher when deciding what should be marked complete.

The month-item matcher requires all of these:

- imported title contains the item's statement keywords, or the item name if keywords are empty
- imported amount is within +/- 5% of the month item amount
- imported posted date is within +/- 3 days of the month item `dueDay`

This gives flexible matching for planned items and for previously auto-created unplanned items while keeping source-level dedupe safe.

### 2. Text matcher with stronger normalization

We could stay text-based and add token cleanup or punctuation stripping. This would be smaller, but it still fails when the bank description changes slightly and the amount/date signal is what really identifies the item.

### 3. Source-ID-only reconciliation

We could require source identity for all reconciliation. This is safest for exact re-imports, but it does not solve the user workflow of matching an import to an existing month item that was created or edited independently.

## Recommendation

Use the composite matcher for month-item reconciliation, but keep `FITID` as the first-line import idempotency key.

This preserves the current architecture:

- imported OFX rows are the audit trail
- `FITID` keeps duplicate source rows out
- month reconciliation remains a business-rule layer that can evolve without weakening import safety

## Platform Assumptions

- Verified: Nationwide OFX provides `FITID`, `DTPOSTED`, `TRNAMT`, and `NAME`
- Verified: `PlannedItem` already has an optional `matchingString`
- Verified: month item editing currently flows through `MonthItemEditorView` and `AppState.update(item:...)`
- Verified: import-created unmatched items are currently represented as `PlannedItem(source: .importedUnplanned)`
- Unverified: whether any non-month editor screen also needs to expose `matchingString` in v1. For this slice, month editor only is sufficient.

## Data Model Changes

No new top-level model is required for this slice.

We will use the existing `PlannedItem.matchingString` field as the editable "statement keywords" value.

Behavioral rules:

- empty `matchingString` means "fall back to label"
- unmatched imported items are created with `label == matchingString == imported payee`
- editing an `importedUnplanned` item promotes `source` to `.manual`
- matching an existing item does not change its `source`

## Matching Rules

### Primary import idempotency

Imported source rows remain deduped by account + source kind + external transaction id (`FITID`).

This continues to protect Milestones 1 and 2.

### Month-item reconciliation

An imported record matches an existing month item only if all of the following are true:

1. text match
   the normalized imported payee/title contains the item's normalized `matchingString`, or if that is empty, the item's normalized `label`
2. amount match
   the imported amount is within +/- 5% of the month item amount
3. date match
   the imported posted day is within +/- 3 days of the item `dueDay`

If multiple items qualify, prefer:

1. the smallest amount delta
2. the smallest day delta
3. stable id tie-breaker

### Reimport recognition for auto-created unplanned items

The same composite matcher should also be used to recognize an already-created `importedUnplanned` item when re-importing, so the app re-marks that item complete instead of creating another copy.

`FITID` still wins first when available, but the tolerance matcher provides the business-level fallback the user wants.

## Reconciliation Behavior

### When an existing month item matches

- mark it paid
- update `amount` to the imported absolute amount
- update `dueDay` to the OFX posted day of month
- persist the imported record's `appliedPlannedItemID`
- do not change `source`

### When no existing item matches

Create a new month item with:

- `source = .importedUnplanned`
- `label = imported payee`
- `matchingString = imported payee`
- `amount = abs(imported amount)`
- `dueDay = posted day of month`
- `isPaid = true`
- `copiesToNextMonthAutomatically = false`

## Editing Behavior

Expose `matchingString` in the month-item editor as:

- label: `Statement keywords`

Save behavior:

- if the user clears the field, matching falls back to the item name
- if the edited item was `importedUnplanned`, any successful user edit promotes it to `manual`

This keeps imported surprises visible until the user consciously adopts them into the plan.

## Error Handling

- If an imported record has no usable payee text, treat text match as failing and fall back to creating an `importedUnplanned` item.
- If an item has no `dueDay`, it is not eligible for date-tolerant matching and should not be auto-matched in this slice.
- If multiple candidates remain tied after amount/day comparison, choose deterministically by id to keep reconciliation stable.

## Testing

Add coverage for:

- editor round-trip of `matchingString`
- editing `importedUnplanned` promotes to `manual`
- match succeeds when text, amount, and date are all within tolerance
- match fails when amount exceeds 5%
- match fails when date exceeds 3 days
- matched import updates `dueDay`
- unmatched import-created item gets OFX posted day as `dueDay`
- reimport reuses an existing `importedUnplanned` item instead of creating another

## Out of Scope

- user-configurable tolerance settings
- regex-based statement matching
- matching items with no `dueDay`
- changing `source` for items that were already planned
