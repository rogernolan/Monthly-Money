# V2 Sharing Settings Design

## Goal
Add the first real user-facing sharing flow to MonthlyMoney in Settings.

This phase is explicitly about budget sharing between two different users. We are no longer designing around a separate v1 same-Apple-ID sync control surface.

## Product Rules
- There is only one active budget.
- Sharing is budget-level only.
- Tapping `Share Budget` migrates the current local/private budget into the shared store immediately.
- After sharing, the owner continues using the shared budget.
- A recipient who accepts a share and already has local data must see a destructive warning.
- The warning must clearly say the overwrite cannot be undone.
- If the recipient confirms, their local budget is deleted and replaced by the shared budget.
- `Unshare` is out of scope for this phase.

## Settings UI
Settings keeps the existing daily-budget settings and adds a new `Sharing` section.

### Daily section
- `Use separate account for daily budget`
- `Payday`

### Sharing section
- Primary action button: `Share Budget`
- Status row below the button:
  - `Local only`
  - `Shared by you`
  - `Shared with you`
- If the active budget is already shared:
  - disable `Share Budget`
  - show a small explanatory note that unsharing will come later

This keeps the Settings surface minimal while still making the budget state understandable.

## Owner Flow
1. User opens Settings.
2. User taps `Share Budget`.
3. App validates the active budget is local.
4. App migrates the budget into the shared store.
5. App creates a `CKShare` rooted at the shared budget.
6. App presents the system share sheet.
7. App remains pointed at the shared budget.
8. Settings updates to `Shared by you`.

There is no option to keep a separate local copy.

## Recipient Flow
1. Recipient accepts the system share invitation.
2. MonthlyMoney detects an available shared budget.
3. If the recipient already has local budget data, the app presents a destructive dialog.
4. Dialog copy should make the consequence explicit:
   - title: `Open Shared Budget?`
   - message: `This will overwrite your existing MonthlyMoney budget on this device. This cannot be undone.`
5. Actions:
   - `Cancel`
   - `Overwrite and Open Shared Budget`
6. On confirm:
   - local/private budget data is deleted
   - the shared budget becomes the active budget
7. Settings updates to `Shared with you`.

If the recipient has no existing local data, the app can adopt the shared budget without the destructive confirmation.

## State Model
The app needs a simple user-facing sharing state derived from persistence:
- `localOnly`
- `sharedByOwner`
- `sharedWithParticipant`
- optional transient states:
  - `sharingInProgress`
  - `awaitingRecipientAdoption`
  - `shareUnavailable`

These states should be surfaced from app state into Settings, rather than inferred ad hoc in the view.

## Architecture Impact
### SettingsView
- Add a `Sharing` section.
- Render the share action, status text, and disabled state.
- Render brief explanatory text when already shared.

### AppState
- Expose a sharing status enum suitable for UI.
- Expose a `shareBudget()` async action for the owner flow.
- Expose recipient adoption state for the destructive overwrite dialog.
- Expose actions to confirm or cancel shared-budget adoption.

### Sharing Service
The existing budget migration service remains the basis of the owner path, but now needs the real share flow:
- local/private budget -> shared store migration
- `CKShare` creation for the shared budget root
- hook for presenting the system share sheet

### Startup / Scene Handling
The app needs a way to detect that a shared budget has become available after share acceptance.

When that happens:
- if local data exists, queue the destructive adoption prompt
- if not, adopt the shared budget directly

## Error Handling
- If share creation fails, keep the current active budget unchanged and show an error state.
- If recipient adoption is cancelled, keep the local budget unchanged.
- If local-data deletion fails during adoption, stop and preserve the local budget.
- If CloudKit sharing is unavailable, disable the share action and show a simple unavailable state.

## Testing
### Unit / repository tests
- budget migration preserves totals and linked records
- owner share action ends with data only in the shared store
- already-shared budgets cannot be shared again

### App tests
- Settings shows `Local only` for a local budget
- Settings disables `Share Budget` for an already shared budget
- recipient adoption state triggers the destructive warning when local data exists
- confirm replaces local budget with shared budget
- cancel leaves local budget unchanged

## Scope Boundaries
Included:
- Settings sharing section
- owner share action
- recipient destructive adoption prompt
- shared/local status display

Not included:
- unshare
- merge of local and shared data
- multiple budget switching
- participant management UI beyond the system share sheet
