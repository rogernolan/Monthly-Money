# CloudKit Environments and Versioned Store Migration

## Goal

Make Production and Development CloudKit data independently inspectable on the same phone, while safely migrating existing MonthlyMoney stores from Core Data v1 through v2 to v3 without deleting user data on failure.

## Environment design

The existing production app keeps the bundle identifier `com.diffeng.MonthlyMoney` and uses the `iCloud.com.hatbat.monthlymoney` container in CloudKit Production.

A dedicated development app/scheme uses a distinct bundle identifier, `com.diffeng.MonthlyMoney.dev`, the same container identifier, and CloudKit Development. It uses a separate local store directory and store names so both apps can be installed and run simultaneously. The development App ID and container association must be present in the Apple Developer configuration before installing on a device.

The environment is explicit in build configuration and entitlements rather than inferred from whether the build is Debug or Release. The app logs its selected environment at startup to make an incorrect archive configuration obvious.

## Model and migration design

Three immutable Core Data models are retained:

- v1: original entities and attributes, without `repeatDays`, `recurrenceID`, `repeatModeRaw`, or `CDPopulatedMonth`.
- v2: adds `repeatDays` and `recurrenceID`.
- v3: adds `repeatModeRaw` and `CDPopulatedMonth`.

Startup reads store metadata before loading the current model. A v1 store is migrated to v2, then to v3. A v2 store is migrated directly to v3. A v3 store is opened without migration. The migration path must work for local, private CloudKit, and shared CloudKit stores.

Legacy floating items are normalized during the v2-to-v3 transition: they become periodic 28-day items and occurrences that represent one copied series receive one deterministic recurrence ID. Existing calendar-repeat, periodic, and one-off data retains its mode and values.

Migration is transactional and recoverable. The original store remains untouched until the migrated store has loaded, validated, and been atomically installed. If any stage fails, the original store remains available and the app reports the error. Startup must never delete stores or silently fall back to empty in-memory data for a persistent-store failure.

## Recovery and observability

The migration records its source model version, destination version, and completion state in a small local migration marker. A failed or interrupted migration can be retried without treating a partial destination as authoritative.

The app logs store URL, model version, CloudKit environment, database scope, migration start/end, and record counts. It does not log record contents or credentials. Tests verify that record counts and IDs survive each migration and that failed migrations preserve the source store.

## Testing

Unit tests cover:

- v1 → v2 migration;
- v2 → v3 migration;
- sequential v1 → v2 → v3 migration;
- legacy floating-series normalization;
- preservation of calendar, periodic, and one-off modes;
- migration failure preserving the original store;
- explicit Production versus Development store configuration;
- separate local paths for the two app targets.

Device verification installs both app variants on one phone, confirms each reaches its intended CloudKit environment, and checks the dashboard’s Production and Development private databases independently.
