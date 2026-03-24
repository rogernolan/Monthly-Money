import UniformTypeIdentifiers
import SwiftUI

private struct PendingImportedStatementFile {
    let data: Data
    let fileName: String
    let format: ImportFormat
}

private enum ImportDestination {
    case monthly
    case daily
}

private enum ImportFormat {
    case ofx
    case qif
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var isPresentingOFXImporter = false
    @State private var pendingImportedStatementFile: PendingImportedStatementFile?
    @State private var pendingImportDestination: ImportDestination = .monthly
    @State private var pendingImportFormat: ImportFormat = .ofx
    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    var body: some View {
        Form {
            Section("Daily") {
                Toggle(
                    "Use separate account for daily budget",
                    isOn: Binding(
                        get: { state.usesSeparateAccountForDailyBudget },
                        set: { state.usesSeparateAccountForDailyBudget = $0 }
                    )
                )
                .disabled(!state.canEditBudgetSettings)

                Picker(
                    "Payday",
                    selection: Binding(
                        get: { state.dailyBudgetPaydayDay },
                        set: { state.dailyBudgetPaydayDay = $0 }
                    )
                ) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)")
                            .tag(day)
                    }
                }
                .disabled(!state.canEditBudgetSettings)

                if !state.canEditBudgetSettings {
                    Text("Only the budget owner can change these settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("WoM") {
                Toggle(
                    "Auto generate WoM savings every month",
                    isOn: Binding(
                        get: { state.autoGenerateWoMSavingsEveryMonth },
                        set: { state.autoGenerateWoMSavingsEveryMonth = $0 }
                    )
                )
                .disabled(!state.canEditBudgetSettings)
            }

            if state.usesSeparateAccountForDailyBudget {
                Section("Import to monthly account") {
                    Button("Import OFX") {
                        startImport(.monthly, format: .ofx)
                    }

                    Button("Import QIF") {
                        startImport(.monthly, format: .qif)
                    }

                    Text("Import a Nationwide OFX statement or Monzo-style QIF file into the selected account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Import to daily account") {
                    Button("Import OFX") {
                        startImport(.daily, format: .ofx)
                    }

                    Button("Import QIF") {
                        startImport(.daily, format: .qif)
                    }

                    Text("OFX updates the hidden daily account balance and transactions. QIF imports daily transactions only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Import") {
                    Button("Import OFX") {
                        startImport(.monthly, format: .ofx)
                    }

                    Button("Import QIF") {
                        startImport(.monthly, format: .qif)
                    }

                    Text("Import a Nationwide OFX statement or Monzo-style QIF file into the selected account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sharing") {
                Button("Share Budget") {
                    Task {
                        await state.shareBudget()
                    }
                }
                .disabled(!state.sharingPresentation.isShareButtonEnabled || state.isSharingBudget)

                if state.sharingPresentation.showsUnshareButton {
                    Button("Unshare Budget", role: .destructive) {
                        Task {
                            await state.shareBudget()
                        }
                    }
                    .disabled(state.isSharingBudget)
                }

                LabeledContent("Status", value: state.sharingPresentation.statusText)

                if let note = state.sharingPresentation.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = state.sharingErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .fileImporter(
            isPresented: $isPresentingOFXImporter,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        let data = try await AppState.loadImportedOFXFile(from: url)
                        await MainActor.run {
                            switch pendingImportDestination {
                            case .monthly:
                                guard !state.accounts.isEmpty else {
                                    importErrorMessage = "Create an account before importing a statement file."
                                    return
                                }

                                let pendingFile = PendingImportedStatementFile(
                                    data: data,
                                    fileName: url.lastPathComponent,
                                    format: pendingImportFormat
                                )
                                if state.accounts.count == 1, let account = state.accounts.first {
                                    importLoadedMonthlyStatement(pendingFile, into: account)
                                } else {
                                    pendingImportedStatementFile = pendingFile
                                }
                            case .daily:
                                importLoadedDailyStatement(
                                    PendingImportedStatementFile(
                                        data: data,
                                        fileName: url.lastPathComponent,
                                        format: pendingImportFormat
                                    )
                                )
                            }
                            pendingImportDestination = .monthly
                            pendingImportFormat = .ofx
                        }
                    } catch {
                        await MainActor.run {
                            importErrorMessage = "Failed to load import file: \(error.localizedDescription)"
                        }
                    }
                }
            case .failure(let error):
                if (error as? CocoaError)?.code == .userCancelled {
                    return
                }
                importErrorMessage = "Failed to choose OFX file: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Import",
            isPresented: Binding(
                get: { pendingImportedStatementFile != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingImportedStatementFile = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            ForEach(state.accounts, id: \.id) { account in
                Button(account.name) {
                    guard let pendingImportedStatementFile else { return }
                    importLoadedMonthlyStatement(pendingImportedStatementFile, into: account)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingImportedStatementFile = nil
            }
        } message: {
            Text(pendingImportedStatementFile.map { "Import \($0.fileName) into which account?" } ?? "")
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "The statement file could not be imported.")
        }
        .alert("Import Complete", isPresented: Binding(
            get: { importSuccessMessage != nil },
            set: { if !$0 { importSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                importSuccessMessage = nil
            }
        } message: {
            Text(importSuccessMessage ?? "The statement file was imported.")
        }
        .sheet(item: Binding(
            get: { state.pendingBudgetShareResult },
            set: { newValue in
                if newValue == nil {
                    state.clearPendingBudgetSharePresentation()
                }
            }
        )) { shareResult in
            BudgetCloudSharingController(
                shareResult: shareResult,
                onDismiss: {
                    state.clearPendingBudgetSharePresentation()
                },
                onStopSharing: {
                    Task {
                        await state.handleBudgetShareStoppedFromUI()
                    }
                },
                onError: { message in
                    state.sharingPresentationDidFail(message: message)
                }
            )
        }
    }

    private func startImport(_ destination: ImportDestination, format: ImportFormat) {
        pendingImportDestination = destination
        pendingImportFormat = format
        isPresentingOFXImporter = true
    }

    private func importLoadedMonthlyStatement(_ pendingFile: PendingImportedStatementFile, into account: Account) {
        pendingImportedStatementFile = nil

        Task {
            do {
                let result: (importResult: ImportedTransactionImportResult, reconciliationResult: ImportedTransactionReconciliationResult)
                switch pendingFile.format {
                case .ofx:
                    result = try state.importOFXData(
                        pendingFile.data,
                        fileName: pendingFile.fileName,
                        into: account.id
                    )
                case .qif:
                    result = try state.importQIFData(
                        pendingFile.data,
                        fileName: pendingFile.fileName,
                        into: account.id
                    )
                }
                await MainActor.run {
                    importSuccessMessage = "Imported \(result.importResult.insertedCount) transactions, skipped \(result.importResult.skippedCount) duplicates, matched \(result.reconciliationResult.matchedCount) planned items, created \(result.reconciliationResult.createdCount) unplanned items."
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = "Failed to import statement file: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importLoadedDailyStatement(_ pendingFile: PendingImportedStatementFile) {
        Task {
            do {
                let successMessage: String
                switch pendingFile.format {
                case .ofx:
                    let balance = try state.importDailyOFXData(
                        pendingFile.data,
                        fileName: pendingFile.fileName
                    )
                    successMessage = "Updated daily balance to \(balance)."
                case .qif:
                    let result = try state.importDailyQIFData(
                        pendingFile.data,
                        fileName: pendingFile.fileName
                    )
                    successMessage = "Imported \(result.importResult.insertedCount) daily transactions, skipped \(result.importResult.skippedCount) duplicates, ignored \(result.ignoredOutsideCurrentCycleCount) outside the current payday cycle. QIF does not include a current balance, so the daily balance was derived from the starting budget and imported transactions."
                }
                await MainActor.run {
                    importSuccessMessage = successMessage
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = "Failed to import statement file: \(error.localizedDescription)"
                }
            }
        }
    }
}
