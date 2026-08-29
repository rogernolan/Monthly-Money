# Imported Date Retention and Repeat Copying Design

## Goal

Preserve concrete dates when editing planned items, retain the original bank-imported date as immutable provenance, and make repeat mode—not a separate toggle—the source of truth for copying entries into later budget months.

## Product rules

- `dueDay` is independent of repeat mode.
- A dated one-off item keeps its `dueDay`, and that day remains editable.
- Changing an item to “Does not repeat” changes recurrence behavior only; it never clears an existing date.
- A floating item is an item with no concrete `dueDay`; it means the timing is unknown within the budget month.
- Calendar and periodic items copy automatically.
- One-off items do not copy automatically.
- The legacy “Copy to next month automatically” control is removed from the editor. Persisted legacy values remain readable but no longer control new behavior.
- An imported item remembers the original OFX `postedAt` independently of later edits to its title, amount, repeat mode, or `dueDay`.

## Data model and migration

Add an optional `importedPostedAt: Date?` attribute to `PlannedItem`. It is provenance, not the item’s editable date, and is copied to generated entries and periodic occurrences.

Add an explicit Core Data model migration for the optional attribute. Existing dates and repeat metadata must survive unchanged. Previously erased dates cannot be reconstructed. The migration must continue to load legacy rows whose repeat mode was inferred from older fields.

The existing `copiesToNextMonthAutomatically` storage may remain temporarily for backward-compatible decoding and migration, but runtime copy eligibility must use `repeatMode`:

- `.calendar`: eligible
- `.periodic`: eligible
- `.oneOff`: not eligible

## Editor behavior

Separate repeat-mode state from date state in `MonthItemEditorDraft`.

- The day editor remains available for any item with a concrete `dueDay`, including one-off items.
- Calendar repeat edits the concrete day used by that occurrence series.
- Periodic repeat retains the existing concrete day as its anchor and edits only the interval in its periodic controls.
- Selecting “Does not repeat” leaves the concrete day untouched.
- An item with no concrete day remains floating; no date is invented when its repeat mode changes.

Saving an edit must pass the retained or newly edited `dueDay` through to the planned item while changing only recurrence fields required by the selected repeat mode.

## Import and details display

When reconciliation links an imported record to an existing planned item, or creates an imported unplanned item, it stores the record’s original `postedAt` in `importedPostedAt`. Once present, later reconciliation and ordinary edits do not replace it.

At the bottom of the details screen, in the existing read-only bank-statement metadata block, show:

- `Shown on bank statement as <payee>`
- `Imported on <formatted original date>`

The imported date is not an editable field and is not displayed beside the editable “Search string for import” field. Omit the imported-date line when provenance is unavailable. Use the app’s existing locale-aware date formatting conventions.

## Copy and occurrence behavior

Update ordinary next-month copying to select calendar and periodic repeat modes directly. One-off entries, including imported unplanned entries, are excluded regardless of the legacy boolean.

Copies and periodic occurrences retain `importedPostedAt`. Their current `dueDay` may represent the generated occurrence and may differ from the original imported date.

Existing periodic harvesting and payday-to-payday budget boundaries remain unchanged. Same-month occurrence generation continues to use the existing recurrence rules.

## Verification

Add regression coverage for:

1. Editing a dated item to one-off preserves its concrete day.
2. A dated one-off’s day remains editable and is saved.
3. Reconciliation stores the original imported `postedAt`.
4. Editing the linked item does not change `importedPostedAt`.
5. Ordinary copies and periodic occurrences retain imported provenance.
6. Only calendar and periodic modes are copied; one-off mode is not.
7. Core Data migration adds the optional attribute without losing existing rows or repeat metadata.

Run focused package/app tests, the full Swift package test suite, and an unsigned generic iOS build. Report any existing simulator allocator or harness failure separately from product regressions.
