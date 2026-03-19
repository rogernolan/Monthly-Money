import UniformTypeIdentifiers
import SwiftUI

private struct PendingImportedOFXFile {
    let data: Data
    let fileName: String
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var isPresentingOFXImporter = false
    @State private var pendingImportedOFXFile: PendingImportedOFXFile?
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

            Section("Import") {
                Button("Import OFX") {
                    isPresentingOFXImporter = true
                }

                Text("Import a Nationwide OFX statement into the selected account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        let data = try await AppState.loadImportedOFXFile(from: url)
                        await MainActor.run {
                            guard !state.accounts.isEmpty else {
                                importErrorMessage = "Create an account before importing an OFX file."
                                return
                            }

                            let pendingFile = PendingImportedOFXFile(
                                data: data,
                                fileName: url.lastPathComponent
                            )
                            if state.accounts.count == 1, let account = state.accounts.first {
                                importLoadedOFX(pendingFile, into: account)
                            } else {
                                pendingImportedOFXFile = pendingFile
                            }
                        }
                    } catch {
                        await MainActor.run {
                            importErrorMessage = "Failed to load OFX file: \(error.localizedDescription)"
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
            "Import OFX",
            isPresented: Binding(
                get: { pendingImportedOFXFile != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingImportedOFXFile = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            ForEach(state.accounts, id: \.id) { account in
                Button(account.name) {
                    guard let pendingImportedOFXFile else { return }
                    importLoadedOFX(pendingImportedOFXFile, into: account)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingImportedOFXFile = nil
            }
        } message: {
            Text(pendingImportedOFXFile.map { "Import \($0.fileName) into which account?" } ?? "")
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "The OFX file could not be imported.")
        }
        .alert("Import Complete", isPresented: Binding(
            get: { importSuccessMessage != nil },
            set: { if !$0 { importSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                importSuccessMessage = nil
            }
        } message: {
            Text(importSuccessMessage ?? "The OFX file was imported.")
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

    private func importLoadedOFX(_ pendingFile: PendingImportedOFXFile, into account: Account) {
        pendingImportedOFXFile = nil

        Task {
            do {
                let result = try state.importOFXData(
                    pendingFile.data,
                    fileName: pendingFile.fileName,
                    into: account.id
                )
                await MainActor.run {
                    importSuccessMessage = "Imported \(result.insertedCount) transactions and skipped \(result.skippedCount) duplicates."
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = "Failed to import OFX file: \(error.localizedDescription)"
                }
            }
        }
    }
}
