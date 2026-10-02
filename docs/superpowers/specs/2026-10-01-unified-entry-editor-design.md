# Unified Entry Editor Design

Month entries and WoM periodic occurrences use the same three-section form layout.

## Details

Show Title, Match string, Amount, Type, and Repeat in that order. Type is a plain Debit/Credit pop-up menu. Repeat is the standard system segmented picker with None, Calendar, and Periodic choices. Show Planned only when Repeat is None; Calendar and Periodic entries are always planned. Existing repeat entries may change to None for this occurrence. Direct Calendar-to-Periodic and Periodic-to-Calendar conversions are unavailable. New entries can choose any repeat type. Existing one-off entries can become periodic while retaining their identity and paid/import metadata.

## Repeat details

None shows no repeat fields. Calendar shows Day of month. Periodic shows Start date and Repeat period. Keep existing explanatory text in the same cell as its associated control. This-occurrence edits cannot change the repeat period; This and future can.

## Notes and deletion

The final section contains Notes and Delete. Periodic entries default to This occurrence, with This and future available for edits and deletion. Changing a periodic occurrence to None detaches that occurrence without ending its series. Changing a Calendar entry to None leaves that row one-off and keeps the following month's calendar copy: the row stores the original calendar details in an optional continuation payload, and the copy flow resumes Calendar mode next month using those original details. The picker does not offer Periodic on such a continuation row. The Month detail and swipe delete actions apply periodic deletion by scope; swipe deletes only the selected occurrence. A Month one-off or calendar entry deletes its stored row. Preserve imported-item matching and statement information where applicable, as well as existing edit permissions.

## Implementation and checks

Use shared presentation controls for the two forms while retaining their distinct save paths for stored Month rows and projected WoM occurrences. Persist detached periodic occurrences as one-off rows without changing their planned-item identity, paid state, or import links. Add the optional calendar continuation payload through SwiftData V4 and Core Data V7 migrations, including private and shared stores. Add focused tests for detach, scope, mode availability, calendar continuation, and both migrations, then build and run the required tests.
