# Cloud Sync And Sharing Design

## Goal
Add real iCloud-backed persistence to MonthlyMoney in two stages:
- v1: sync a single budget across devices signed into the same Apple ID
- v2: share that budget between two different users via CloudKit sharing

## Current State
The app currently persists data locally using two SwiftData stores created in [MonthlyMoneyApp.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthlyMoneyApp.swift): `PrivateStore` and `SharedStore`.

The repository and migration structure already exists:
- [Repository.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift) routes reads and writes by `Budget.sharingState`
- [AccountSharingService.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/AccountSharingService.swift) migrates a local budget snapshot into the shared side

CloudKit is not wired today. The app is local-only on each device.

## Product Rules
- There is only one active budget.
- The user may start local-only.
- Enabling sync or accepting a share may replace local data.
- If local data will be replaced, the app must show a warning that clearly says this cannot be undone.
- Reverse migration is out of scope.
- Share UI lives in Settings.

## Approach Options

### Option 1: One active budget with one-way replacement on join
Recommended.

- v1 uses the user’s CloudKit private database for the synced budget.
- v2 uses the CloudKit shared database for a shared budget.
- If a device already has local data when it joins an existing cloud or shared budget, warn and replace local data.

Pros:
- smallest safe architecture
- no merge logic
- matches the current app model

Cons:
- destructive onboarding path when a device already contains data

### Option 2: Keep local and cloud/shared budgets side by side
- Preserve local data and let the user choose between local and cloud/shared budgets.

Pros:
- non-destructive

Cons:
- significantly more UI and state complexity
- does not fit the current app model

### Option 3: Merge local data into cloud/shared on onboarding
- Attempt to reconcile existing local data with cloud/shared data.

Pros:
- least destructive in theory

Cons:
- highest implementation risk
- unclear merge semantics
- unnecessary for v1

## Recommended Architecture
Use Option 1.

The app continues to model one logical budget. Storage location changes over time:
- local-only during pre-sync use
- CloudKit private database for same-Apple-ID sync
- CloudKit shared database for cross-user sharing

The app never attempts to merge two different budgets. When adopting an existing cloud/shared budget on a device that already contains local data, it warns the user and replaces the local copy.

## v1: Sync Across One Apple ID

### Behaviour
- A synced budget lives in the user’s CloudKit private database.
- Two devices signed into the same Apple ID should load the same budget.
- If no private-cloud budget exists, the app may upload the current local budget to become the synced budget.
- If a private-cloud budget already exists and the device has local data, the app warns and replaces local data with the cloud budget.

### UI
Settings gains a sync section with:
- current sync status
- an action to enable iCloud sync
- warning/confirmation UI when local data will be replaced

The existing Settings controls remain:
- `Use separate account for daily budget`
- `Payday`

### Storage
- Replace the current local-only private store configuration with a real SwiftData + CloudKit private database configuration.
- Keep the current local file fallback path for when CloudKit/container creation fails.
- Treat the CloudKit private database as the canonical store once sync is enabled.

### Startup / Adoption Rules
1. Start app.
2. Check CloudKit availability.
3. If unavailable, stay local-only.
4. If sync is enabled and no cloud budget exists:
   - upload local budget if present
   - otherwise create a new synced budget
5. If cloud budget exists:
   - if no local budget exists, adopt cloud budget
   - if local budget exists and differs, show destructive replacement warning

## v2: Sharing Between Two Users

### Behaviour
- Sharing is budget-level only.
- The owner creates a CloudKit share rooted at the `Budget` record.
- The recipient accepts the share.
- If the recipient already has local data, the app warns that accepting the share will delete existing local MonthlyMoney data and that this cannot be undone.
- On confirmation, recipient local/private data is deleted and replaced with the shared budget.

### UI
Settings gains sharing controls:
- `Share Budget`
- share status / participant state
- acceptance/adoption warning flow on recipient device

### Storage
- Use the CloudKit shared database for the active budget after share acceptance.
- The current `BudgetSharingService` becomes the bridge from local/private budget to shared budget.
- Real `CKShare` creation replaces the current placeholder `shareHandler` hook.

## Data Model Impact
The current model can largely stay intact.

Key persisted state remains on `Budget`:
- `sharingState`
- `usesSeparateAccountForDailyBudget`
- `dailyBudgetAmount`
- `dailyBudgetPaydayDay`

No reintroduction of per-account sharing is needed.

## Repository Impact
[Repository.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift) is already close to the right shape.

Needed evolution:
- private store becomes a real CloudKit private-db-backed store in v1
- shared store becomes a real CloudKit shared-db-backed store in v2
- startup/bootstrap logic decides which store is active and whether local data must be replaced
- migration helpers remain one-way only

## Error Handling
- If CloudKit setup fails, continue in local-only mode.
- If share/sync adoption would overwrite local data, require explicit destructive confirmation.
- If share creation or share acceptance fails, keep the existing active budget unchanged.
- Reverse migration remains unsupported.

## Testing Strategy

### v1
- creating/adopting a private-cloud budget works
- same-Apple-ID devices converge on the same budget
- local data replacement warning appears when adopting an existing cloud budget over local data
- local fallback still works when CloudKit is unavailable

### v2
- budget sharing creates a share for the budget root
- local -> shared migration preserves totals and linked records
- recipient adoption deletes local data and loads shared data
- both participants observe the same budget state

## Rollout Recommendation
Build this in two milestones:
1. v1 private-database sync across one Apple ID
2. v2 CloudKit sharing between two users

This keeps risk down and gives a usable sync story before introducing multi-user collaboration.
