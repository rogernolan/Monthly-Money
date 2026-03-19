# CloudKit Sharing Transport Design

## Goal
Add a real owner-to-recipient CloudKit sharing flow for MonthlyMoney so the Settings `Share Budget` button creates and presents a share invite, and a recipient who accepts that invite is routed into the existing destructive overwrite/adopt flow.

## Current State
- Budget data now lives in Core Data stores backed by `NSPersistentCloudKitContainer` for both private and shared databases.
- The app can migrate a local budget into the shared store.
- The app already has recipient-side overwrite UI, but that UI only appears if a shared budget is already visible in the repository.
- There is no actual share creation, share presentation, or share acceptance lifecycle wiring.

## Hard Platform Assumptions
- `NSPersistentCloudKitContainer` in this app can create/fetch a `CKShare` for the shared budget root object.
- The app can receive share acceptance metadata through the iOS scene lifecycle and use that to refresh the shared store.
- `UICloudSharingController` can be presented from the SwiftUI app with a thin UIKit bridge.

These assumptions must be proven early with a minimal spike before we reshape the main sharing API around them.

## Recommended Architecture
Use a thin UIKit/scene bridge around the existing SwiftUI and repository architecture.

### Owner Flow
1. User taps `Share Budget` in Settings.
2. App migrates the active local budget into the shared store if needed.
3. App resolves the shared `Budget` managed object inside the shared Core Data store.
4. App creates or fetches the `CKShare` for that budget root.
5. App presents `UICloudSharingController`.
6. Owner remains on the shared budget.

### Recipient Flow
1. Recipient accepts the iOS CloudKit share invite.
2. Scene delegate receives `CKShare.Metadata`.
3. App passes that metadata into a small share-acceptance coordinator.
4. Shared store refresh/import runs.
5. App detects the incoming shared budget.
6. If local data exists, show the existing destructive overwrite dialog.
7. Confirm deletes local budget and opens the shared budget.

## Persistence Boundary
Keep the repository as the app-facing boundary, but add a narrow Core Data sharing interface beneath it.

New responsibilities needed under the repository:
- locate the shared-budget managed object by domain budget ID
- create/fetch a CloudKit share for that object
- surface incoming accepted-share metadata to the app layer
- refresh shared-store visibility after acceptance

This keeps most of the app state and UI intact while acknowledging that share transport is a Core Data / UIKit concern.

## UI Design
Settings remains the main owner entry point.

### Settings
- Keep the current `Sharing` section.
- `Share Budget` should now:
  - disable while in progress
  - present system share UI when ready
  - show clear error text if share creation fails

### Recipient Warning
Keep the current destructive overwrite alert. It already matches the product requirement:
- recipient local data is overwritten
- action is explicit
- warning states `This cannot be undone`

## Error Handling
- If share creation fails after migration to shared store, surface an error and keep the owner on the shared budget.
  - This is acceptable in v1 because `unshare` is deferred.
- If recipient acceptance metadata arrives but shared-store import is not yet visible, keep polling/refreshing briefly before surfacing an error.
- If recipient cancels overwrite, keep local budget active and suppress repeated prompting for that accepted shared budget during the current session.

## Testing Strategy
### Test in code
- unit-test owner sharing state transitions with an injected share presenter/coordinator
- unit-test recipient acceptance state routing into the overwrite prompt
- unit-test that budget settings remain owner-only for shared budgets

### Must test on devices
- owner taps `Share Budget` and sees system sharing UI
- recipient accepts invite and app shows overwrite warning
- recipient confirms overwrite and shared budget becomes active
- owner edits propagate to recipient and vice versa

## Why This Approach
This is the smallest path that proves the actual framework edges we need without rewriting the app lifecycle or repository layer. The missing pieces are not the data model anymore; they are the two CloudKit sharing boundaries Apple routes through Core Data metadata and scene acceptance callbacks.
