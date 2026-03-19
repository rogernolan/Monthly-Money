# Unshare Budget Design

## Summary
Add an owner-only `Unshare Budget` flow that uses the existing CloudKit sharing controller to stop sharing the owner's budget, then marks that budget back to local in the app. The owner budget remains in the private store throughout. No reverse store migration is needed.

## Product Behaviour
- `Local only`: show `Share Budget`
- `Shared by you`: show `Manage Share` and `Unshare Budget`
- `Shared with you`: do not show owner share controls
- When the owner unshares:
  - CloudKit sharing is stopped
  - the budget becomes local again on the owner device
  - recipients lose access when CloudKit propagates the revocation
- No recipient merge or manual cleanup is needed in v1.

## Platform Assumptions
- `UICloudSharingController` stop-sharing flow is already present and can be used as the owner-side revocation entry point.
- `cloudSharingControllerDidStopSharing` is sufficient as the completion callback for local app-state changes.
- Because the owner budget already lives in the private database, unshare only needs to change `Budget.sharingState` back to `.local` after CloudKit confirms sharing stopped.

## Architecture
- Reuse the existing share presentation path rather than adding direct CloudKit share-deletion code.
- Extend the sharing controller callback surface so app state can distinguish between:
  - share saved/dismissed
  - share stopped
  - share error
- Add an owner-only unshare action in Settings that reopens the sharing controller in management mode.
- On stop-sharing callback, update the active private budget to `.local`, refresh app state, and clear any presented share result.

## Error Handling
- If stop sharing fails, surface the localized error in Settings.
- If the budget can no longer be found when stop-sharing completes, show a clear local error instead of silently dismissing.

## Testing
- `SettingsSharingPresentation` should expose owner-only unshare affordance.
- App state should transition from `sharedByYou` to `localOnly` when share-stop callback is received.
- Participant-shared budgets must not expose unshare controls.
