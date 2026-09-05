import SwiftUI
import SwiftData
import LocalAuthentication
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("showRecentItems") private var showRecentItems = true
    @AppStorage("showFrequentItems") private var showFrequentItems = true
    @AppStorage("showPinnedItems") private var showPinnedItems = true
    @AppStorage("showFavoriteItems") private var showFavoriteItems = false
    @AppStorage("insightsShowStorageGrowth") private var insightsShowStorageGrowth = true
    @AppStorage("insightsShowWeeklyActivity") private var insightsShowWeeklyActivity = true
    @AppStorage("insightsShowBreakdownByType") private var insightsShowBreakdownByType = true
    @AppStorage("insightsShowHygiene") private var insightsShowHygiene = true
    @AppStorage("insightsShowTopTags") private var insightsShowTopTags = true
    @AppStorage("insightsShowMostOpened") private var insightsShowMostOpened = true
    @AppStorage("insightsShowLargestFiles") private var insightsShowLargestFiles = true

    @State private var viewModel = SettingsViewModel()
    @State private var dataOperation: DataOperation = .idle
    @State private var isAuthenticatingForAppLock = false
    @State private var showStoragePicker = false
    @State private var showBackupFolderPicker = false
    @State private var enableAfterBackupFolderSelection = false
    @State private var periodicBackupToggleState = false
    @State private var backupConfigurationError: String?
    @State private var exportURL: URL?
    @State private var exportedVaultURL: URL?
    @State private var exportError: String?
    @State private var exportSuccess = false
    @State private var showImportPicker = false
    @State private var pendingImportURL: URL?
    @State private var showImportConfirmation = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var showDeleteConfirmation = false
    @State private var deleteSuccess = false

    var body: some View {
        NavigationStack {
            SettingsOverviewView(
                viewModel: viewModel,
                appearanceMode: appearanceMode,
                appLockEnabled: Binding(get: { appLockEnabled }, set: updateAppLock),
                appLockIsAuthenticating: isAuthenticatingForAppLock,
                enabledHomeShelves: enabledHomeShelves,
                enabledInsightSections: enabledInsightSections,
                storageLocationName: storageLocationName,
                periodicBackupEnabled: periodicBackupToggleState
            )
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(dataOperation.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(dataOperation.isBusy)
        .task {
            periodicBackupToggleState = appContainer.periodicBackup.isEnabled
            await viewModel.loadDriveStats(appContainer: appContainer)
            await viewModel.loadLocalStorageSize(appContainer: appContainer)
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { presented in
                if !presented {
                    removeTemporaryFile(at: exportURL)
                    exportURL = nil
                    exportedVaultURL = nil
                }
            }
        )) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .sheet(isPresented: $showStoragePicker) {
            StorageLocationPickerView(viewModel: viewModel)
                .environment(appContainer)
        }
        .sheet(isPresented: $showBackupFolderPicker) {
            BackupFolderPickerView(
                isPresented: $showBackupFolderPicker,
                onSelection: { handleBackupFolderSelection(.success($0)) },
                onCancellation: handleBackupFolderPickerCancellation
            )
            .interactiveDismissDisabled()
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .alert("Export Complete", isPresented: $exportSuccess) {
            Button("Share") { exportURL = exportedVaultURL }
            Button("Done", role: .cancel) {
                removeTemporaryFile(at: exportedVaultURL)
                exportedVaultURL = nil
            }
        } message: { Text("Your vault has been exported successfully.") }
        .alert("Import Vault", isPresented: $showImportConfirmation) {
            Button("Replace and Import", role: .destructive) {
                guard let pendingImportURL else { return }
                importVault(from: pendingImportURL)
            }
            Button("Cancel", role: .cancel) {
                removeTemporaryFile(at: pendingImportURL)
                pendingImportURL = nil
            }
        } message: { Text("This replaces all current data with the imported vault.") }
        .alert("Delete All Data", isPresented: $showDeleteConfirmation) {
            Button("Delete Everything", role: .destructive, action: deleteAllData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all local data and cannot be undone. Files already synced to Google Drive are unaffected.")
        }
        .alert("Data Deleted", isPresented: $deleteSuccess) {
            Button("OK") {}
        } message: { Text("All local data has been deleted.") }
        .alert("Import Complete", isPresented: $importSuccess) {
            Button("OK", role: .cancel) {}
        } message: { Text("Your vault has been restored successfully.") }
        .alert("Backup Configuration Failed", isPresented: errorBinding($backupConfigurationError)) {
            Button("OK", role: .cancel) {}
        } message: { Text(backupConfigurationError ?? "") }
        .alert("Export Failed", isPresented: errorBinding($exportError)) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .alert("Import Failed", isPresented: errorBinding($importError)) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
        .alert("Delete Failed", isPresented: errorBinding($viewModel.deleteError)) {
            Button("OK", role: .cancel) {}
        } message: { Text(viewModel.deleteError ?? "") }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .cloudSync:
            CloudSyncSettingsView(
                viewModel: viewModel,
                autoSyncEnabled: Binding(
                    get: { viewModel.autoSyncEnabled },
                    set: { viewModel.autoSyncEnabled = $0 }
                )
            )
        case .appearance:
            AppearanceSettingsView(appearanceMode: $appearanceMode)
        case .home:
            HomeCustomizationView(
                showRecentItems: $showRecentItems,
                showFrequentItems: $showFrequentItems,
                showPinnedItems: $showPinnedItems,
                showFavoriteItems: $showFavoriteItems
            )
        case .insights:
            InsightsCustomizationView(
                showStorageGrowth: $insightsShowStorageGrowth,
                showWeeklyActivity: $insightsShowWeeklyActivity,
                showBreakdownByType: $insightsShowBreakdownByType,
                showHygiene: $insightsShowHygiene,
                showTopTags: $insightsShowTopTags,
                showMostOpened: $insightsShowMostOpened,
                showLargestFiles: $insightsShowLargestFiles
            )
        case .storage:
            StorageSettingsView(
                viewModel: viewModel,
                locationName: storageLocationName,
                showLocationPicker: { showStoragePicker = true }
            )
        case .backups:
            BackupSettingsView(
                isEnabled: Binding(
                    get: { periodicBackupToggleState },
                    set: setPeriodicBackupEnabled
                ),
                operationsBusy: dataOperation.isBusy,
                chooseFolder: {
                    enableAfterBackupFolderSelection = false
                    showBackupFolderPicker = true
                }
            )
        case .dataManagement:
            DataManagementView(
                operation: dataOperation,
                exportProgress: viewModel.exportProgress,
                importProgress: viewModel.importProgress,
                backupIsRunning: appContainer.periodicBackup.isRunning
                    || appContainer.periodicBackup.pendingImmediateBackup,
                exportVault: exportVault,
                chooseImport: { showImportPicker = true },
                confirmDelete: { showDeleteConfirmation = true }
            )
        case .about:
            AboutFindlyView()
        }
    }

    private var enabledHomeShelves: Int {
        [showRecentItems, showFrequentItems, showPinnedItems, showFavoriteItems]
            .filter { $0 }.count
    }

    private var enabledInsightSections: Int {
        [
            insightsShowStorageGrowth, insightsShowWeeklyActivity,
            insightsShowBreakdownByType, insightsShowHygiene,
            insightsShowTopTags,
            insightsShowMostOpened, insightsShowLargestFiles
        ]
        .filter { $0 }.count
    }

    private var storageLocationName: String {
        let storage = StorageLocationService.shared
        if storage.currentLocation == .custom, let folder = storage.customFolderDisplayName {
            return folder
        }
        return storage.currentLocation.displayName
    }

    private func updateAppLock(_ enabled: Bool) {
        guard enabled else {
            appLockEnabled = false
            return
        }
        guard !isAuthenticatingForAppLock else { return }
        isAuthenticatingForAppLock = true
        Task {
            defer { isAuthenticatingForAppLock = false }
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                appLockEnabled = false
                announce("App Lock could not be enabled on this device.")
                return
            }
            let authenticated = try? await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Enable App Lock"
            )
            appLockEnabled = authenticated == true
            announce(appLockEnabled ? "App Lock enabled." : "App Lock was not enabled.")
        }
    }

    private func setPeriodicBackupEnabled(_ enabled: Bool) {
        let backup = appContainer.periodicBackup
        guard !backup.isRunning, !dataOperation.isBusy else { return }
        if !enabled {
            periodicBackupToggleState = false
            try? backup.setEnabled(false)
            return
        }
        guard backup.hasDestination else {
            periodicBackupToggleState = true
            enableAfterBackupFolderSelection = true
            presentBackupFolderPicker()
            return
        }
        do {
            try backup.setEnabled(true)
            periodicBackupToggleState = backup.isEnabled
        } catch {
            periodicBackupToggleState = true
            enableAfterBackupFolderSelection = true
            presentBackupFolderPicker()
        }
    }

    private func presentBackupFolderPicker() {
        Task { @MainActor in
            await Task.yield()
            showBackupFolderPicker = true
        }
    }

    private func handleBackupFolderSelection(_ result: Result<[URL], Error>) {
        let shouldEnable = enableAfterBackupFolderSelection
        enableAfterBackupFolderSelection = false
        guard case .success(let urls) = result, let url = urls.first else {
            if shouldEnable { periodicBackupToggleState = false }
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try appContainer.periodicBackup.setDestination(url)
            if shouldEnable { try appContainer.periodicBackup.setEnabled(true) }
            periodicBackupToggleState = appContainer.periodicBackup.isEnabled
            announce("Backup location updated.")
        } catch {
            if shouldEnable { periodicBackupToggleState = false }
            backupConfigurationError = error.localizedDescription
            HapticFeedback.error()
            announce("Backup location could not be updated.")
        }
    }

    private func handleBackupFolderPickerCancellation() {
        let shouldDisable = enableAfterBackupFolderSelection
        enableAfterBackupFolderSelection = false
        if shouldDisable { periodicBackupToggleState = false }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            removeTemporaryFile(at: temporaryURL)
            do {
                try FileManager.default.copyItem(at: url, to: temporaryURL)
                pendingImportURL = temporaryURL
                showImportConfirmation = true
            } catch {
                importError = error.localizedDescription
                announce("The vault could not be prepared for import.")
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func exportVault() {
        guard dataOperation == .idle else { return }
        dataOperation = .exporting
        exportError = nil
        viewModel.exportProgress = 0
        let settingsViewModel = viewModel
        Task {
            do {
                let items = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
                let tags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
                let history = (try? modelContext.fetch(FetchDescriptor<SearchHistoryEntry>())) ?? []
                let url = try await appContainer.export.exportVault(
                    items: items,
                    tags: tags,
                    searchHistory: history,
                    localStorage: appContainer.localStorage,
                    onProgress: { @MainActor progress in settingsViewModel.exportProgress = progress }
                )
                exportedVaultURL = url
                dataOperation = .idle
                exportSuccess = true
                HapticFeedback.success()
                announce("Export complete.")
            } catch {
                exportError = error.localizedDescription
                dataOperation = .idle
                HapticFeedback.error()
                announce("Export failed.")
            }
        }
    }

    private func importVault(from url: URL) {
        guard dataOperation == .idle else { return }
        dataOperation = .importing
        importError = nil
        viewModel.importProgress = 0
        let settingsViewModel = viewModel
        Task {
            do {
                try await appContainer.importService.importVault(
                    from: url,
                    localStorage: appContainer.localStorage,
                    context: modelContext,
                    onProgress: { @MainActor progress in settingsViewModel.importProgress = progress }
                )
                removeTemporaryFile(at: url)
                pendingImportURL = nil
                dataOperation = .idle
                importSuccess = true
                await viewModel.loadLocalStorageSize(appContainer: appContainer)
                HapticFeedback.success()
                announce("Import complete.")
            } catch {
                removeTemporaryFile(at: url)
                pendingImportURL = nil
                importError = error.localizedDescription
                dataOperation = .idle
                HapticFeedback.error()
                announce("Import failed.")
            }
        }
    }

    private func deleteAllData() {
        guard dataOperation == .idle else { return }
        dataOperation = .deleting
        viewModel.deleteError = nil
        Task {
            await viewModel.deleteAllData(
                localStorage: appContainer.localStorage,
                context: modelContext
            )
            dataOperation = .idle
            if viewModel.deleteError == nil {
                deleteSuccess = true
                HapticFeedback.success()
                announce("All local data deleted.")
            } else {
                HapticFeedback.error()
                announce("Local data could not be deleted.")
            }
        }
    }

    private func errorBinding(_ error: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )
    }

    private func removeTemporaryFile(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

private enum SettingsRoute: Hashable {
    case cloudSync, appearance, home, insights, storage, backups, dataManagement, about
}

private enum DataOperation: Equatable {
    case idle, exporting, importing, deleting
    var isBusy: Bool { self != .idle }
}

private struct SettingsOverviewView: View {
    @Environment(AppContainer.self) private var appContainer
    let viewModel: SettingsViewModel
    let appearanceMode: String
    @Binding var appLockEnabled: Bool
    let appLockIsAuthenticating: Bool
    let enabledHomeShelves: Int
    let enabledInsightSections: Int
    let storageLocationName: String
    let periodicBackupEnabled: Bool

    var body: some View {
        List {
            Section {
                NavigationLink(value: SettingsRoute.cloudSync) {
                    SettingsSummaryRow(
                        title: "Cloud & Sync",
                        subtitle: cloudSyncSummary,
                        symbol: cloudSyncSymbol
                    )
                }
            }
            Section("Personalize") {
                NavigationLink(value: SettingsRoute.appearance) {
                    SettingsSummaryRow(
                        title: "Appearance", subtitle: appearanceName,
                        symbol: "circle.lefthalf.filled"
                    )
                }
                NavigationLink(value: SettingsRoute.home) {
                    SettingsSummaryRow(
                        title: "Home", subtitle: "\(enabledHomeShelves) of 4 shelves shown",
                        symbol: "house"
                    )
                }
                NavigationLink(value: SettingsRoute.insights) {
                    SettingsSummaryRow(
                        title: "Insights", subtitle: "\(enabledInsightSections) of 7 sections shown",
                        symbol: "chart.bar"
                    )
                }
            }
            Section("Privacy") {
                Toggle(isOn: $appLockEnabled) {
                    SettingsSummaryRow(
                        title: "App Lock",
                        subtitle: appLockIsAuthenticating
                            ? "Authenticating…"
                            : "Require device authentication",
                        symbol: "lock"
                    )
                }
                .disabled(appLockIsAuthenticating)
                .accessibilityHint("Requires Face ID, Touch ID, or your device passcode.")
            }
            Section("Storage & Protection") {
                NavigationLink(value: SettingsRoute.storage) {
                    SettingsSummaryRow(
                        title: "Storage",
                        subtitle: "\(storageLocationName) · \(viewModel.localStorageSize.fileSizeString)",
                        symbol: "internaldrive"
                    )
                }
                NavigationLink(value: SettingsRoute.backups) {
                    SettingsSummaryRow(
                        title: "Backups", subtitle: backupSummary,
                        symbol: periodicBackupEnabled ? "clock.arrow.circlepath" : "clock"
                    )
                }
            }
            Section {
                NavigationLink(value: SettingsRoute.dataManagement) {
                    SettingsSummaryRow(
                        title: "Data Management",
                        subtitle: "Import, export, or delete your vault",
                        symbol: "externaldrive"
                    )
                }
                NavigationLink(value: SettingsRoute.about) {
                    SettingsSummaryRow(
                        title: "About Findly", subtitle: "Version \(appVersion)",
                        symbol: "info.circle"
                    )
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var cloudSyncSummary: String {
        guard appContainer.auth.isAuthenticated else { return "Not connected" }
        if appContainer.sync.isSyncing { return "Syncing now" }
        if appContainer.sync.pendingCount > 0 {
            return "\(appContainer.sync.pendingCount) items waiting to sync"
        }
        if let lastSync = viewModel.lastSyncDate {
            return "Up to date · \(lastSync.shortRelativeString)"
        }
        return "Up to date"
    }

    private var cloudSyncSymbol: String {
        guard appContainer.auth.isAuthenticated else { return "icloud.slash" }
        if appContainer.sync.isSyncing { return "arrow.triangle.2.circlepath" }
        if appContainer.sync.pendingCount > 0 { return "clock.arrow.circlepath" }
        return "checkmark.icloud"
    }

    private var appearanceName: String {
        SettingsViewModel.AppearanceMode(rawValue: appearanceMode)?.displayName ?? "System"
    }

    private var backupSummary: String {
        periodicBackupEnabled ? appContainer.periodicBackup.schedule.description() : "Off"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

private struct SettingsSummaryRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                Text(title)
                    .foregroundStyle(AppTheme.Colors.label)
                Text(subtitle)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, AppTheme.Spacing.xxSmall)
        } icon: {
            Image(systemName: symbol)
                .font(.title3.weight(.regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .imageScale(.large)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Cloud & Sync

private struct CloudSyncSettingsView: View {
    @Environment(AppContainer.self) private var appContainer
    let viewModel: SettingsViewModel
    @Binding var autoSyncEnabled: Bool
    @State private var isStartingOperation = false
    @State private var connectionError: String?

    var body: some View {
        Form {
            if appContainer.auth.isAuthenticated {
                Section {
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: AppTheme.Spacing.xxSmall) {
                            Text(appContainer.auth.userName ?? "Google User")
                            if let email = appContainer.auth.userEmail, !email.isEmpty {
                                Text(email)
                                    .font(AppTheme.Typography.subheadline)
                                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            }
                        }
                    } label: {
                        Label("Google Drive", systemImage: "person.crop.circle.fill")
                    }
                    LabeledContent("Status") {
                        SyncStatusLabel(viewModel: viewModel)
                    }
                    if viewModel.driveTotalBytes > 0 {
                        LabeledContent(
                            "Drive Storage",
                            value: "\(viewModel.driveUsedBytes.fileSizeString) of \(viewModel.driveTotalBytes.fileSizeString)"
                        )
                    }
                }

                Section {
                    Toggle("Auto Sync", isOn: $autoSyncEnabled)
                    Button {
                        guard !isStartingOperation else { return }
                        isStartingOperation = true
                        Task {
                            await viewModel.manualSync(appContainer: appContainer)
                            isStartingOperation = false
                        }
                    } label: {
                        HStack {
                            Label(
                                appContainer.sync.isSyncing || isStartingOperation ? "Syncing…" : "Sync Now",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            Spacer()
                            if appContainer.sync.isSyncing || isStartingOperation { ProgressView() }
                        }
                    }
                    .disabled(appContainer.sync.isSyncing || isStartingOperation)
                } footer: {
                    Text("Auto Sync uploads pending items when a connection is available.")
                }

                Section {
                    Button("Disconnect Google Drive", role: .destructive) {
                        appContainer.auth.signOut()
                    }
                } footer: {
                    Text("Disconnecting does not delete files already stored in Google Drive.")
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Google Drive Not Connected", systemImage: "icloud.slash")
                    } description: {
                        Text("Connect your account to sync and back up files to Google Drive.")
                    } actions: {
                        Button(action: connectGoogleDrive) {
                            HStack(spacing: AppTheme.Spacing.small) {
                                if isStartingOperation { ProgressView() }
                                Text(isStartingOperation ? "Connecting…" : "Connect Google Drive")
                            }
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(isStartingOperation)
                    }
                }
            }
        }
        .navigationTitle("Cloud & Sync")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could Not Connect", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionError ?? "")
        }
    }

    private func connectGoogleDrive() {
        guard !isStartingOperation else { return }
        isStartingOperation = true
        Task {
            defer { isStartingOperation = false }
            do {
                try await appContainer.auth.signIn()
                guard appContainer.auth.isAuthenticated else { return }
                appContainer.sync.promoteLocalOnlyItems()
                await appContainer.sync.syncPendingItems()
                await viewModel.loadDriveStats(appContainer: appContainer)
            } catch {
                connectionError = error.localizedDescription
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Google Drive could not be connected."
                )
            }
        }
    }
}

private struct SyncStatusLabel: View {
    @Environment(AppContainer.self) private var appContainer
    let viewModel: SettingsViewModel

    var body: some View {
        Label(statusText, systemImage: statusSymbol)
            .foregroundStyle(statusTint)
            .font(AppTheme.Typography.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusText: String {
        let sync = appContainer.sync
        let status = sync.isSyncing
            ? "Syncing"
            : (sync.pendingCount == 0 ? "Up to date" : "\(sync.pendingCount) pending")
        if let lastSync = viewModel.lastSyncDate {
            return "\(status) · \(lastSync.shortRelativeString)"
        }
        return status
    }

    private var statusSymbol: String {
        if appContainer.sync.isSyncing { return "arrow.triangle.2.circlepath" }
        return appContainer.sync.pendingCount == 0
            ? "checkmark.circle.fill"
            : "clock.fill"
    }

    private var statusTint: Color {
        if appContainer.sync.isSyncing { return AppTheme.Colors.syncPending }
        return appContainer.sync.pendingCount == 0
            ? AppTheme.Colors.syncSynced
            : AppTheme.Colors.syncFailed
    }
}

// MARK: - Personalization

private struct AppearanceSettingsView: View {
    @Binding var appearanceMode: String

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(SettingsViewModel.AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("System follows your device's current appearance.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HomeCustomizationView: View {
    @Binding var showRecentItems: Bool
    @Binding var showFrequentItems: Bool
    @Binding var showPinnedItems: Bool
    @Binding var showFavoriteItems: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Recent", isOn: $showRecentItems)
                Toggle("Most Used", isOn: $showFrequentItems)
                Toggle("Pinned", isOn: $showPinnedItems)
                Toggle("Favorites", isOn: $showFavoriteItems)
            } footer: {
                Text("Choose which shelves appear on Home. Recently Added remains visible when new items are available.")
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InsightsCustomizationView: View {
    @Binding var showStorageGrowth: Bool
    @Binding var showWeeklyActivity: Bool
    @Binding var showBreakdownByType: Bool
    @Binding var showHygiene: Bool
    @Binding var showTopTags: Bool
    @Binding var showMostOpened: Bool
    @Binding var showLargestFiles: Bool

    var body: some View {
        Form {
            Section("Storage") {
                Toggle("Storage Growth", isOn: $showStorageGrowth)
                Toggle("Activity Trend", isOn: $showWeeklyActivity)
                Toggle("Breakdown by Type", isOn: $showBreakdownByType)
            }
            Section("Organize") {
                Toggle("Needs Attention", isOn: $showHygiene)
                Toggle("Top Tags", isOn: $showTopTags)
            }
            Section("Files") {
                Toggle("Most Opened", isOn: $showMostOpened)
                Toggle("Largest Files", isOn: $showLargestFiles)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Storage

private struct StorageSettingsView: View {
    let viewModel: SettingsViewModel
    let locationName: String
    let showLocationPicker: () -> Void

    var body: some View {
        Form {
            Section {
                Button(action: showLocationPicker) {
                    LabeledContent("Location") {
                        HStack(spacing: AppTheme.Spacing.small) {
                            if viewModel.isMigratingStorage { ProgressView() }
                            Text(locationName)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .foregroundStyle(AppTheme.Colors.label)
                .disabled(viewModel.isMigratingStorage)

                LabeledContent("Storage Used", value: viewModel.localStorageSize.fileSizeString)
            } footer: {
                Text("Changing the location moves all existing files. Keep Findly open until the move finishes.")
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StorageLocationPickerView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.dismiss) private var dismiss

    let viewModel: SettingsViewModel
    @State private var selectedLocation: StorageLocationService.Location =
        StorageLocationService.shared.currentLocation
    @State private var customURL: URL?
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StorageLocationService.Location.allCases, id: \.self) { location in
                        Button {
                            select(location)
                        } label: {
                            locationRow(for: location)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Moving files may take a moment.")
                }
            }
            .navigationTitle("Storage Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if selectedLocation == .custom && customURL == nil {
                            showFolderPicker = true
                        } else {
                            Task { await applyChange() }
                        }
                    } label: {
                        if viewModel.isMigratingStorage {
                            ProgressView()
                        } else {
                            Text("Move Files")
                        }
                    }
                    .disabled(
                        viewModel.isMigratingStorage
                            || !hasLocationChange
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                customURL = url
                Task {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    await applyChange()
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isMigratingStorage)
        .alert("Storage Move Failed", isPresented: Binding(
            get: { viewModel.storageMigrationError != nil },
            set: { if !$0 { viewModel.storageMigrationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.storageMigrationError ?? "")
        }
    }

    private func locationRow(for location: StorageLocationService.Location) -> some View {
        let isSelected = selectedLocation == location
        let customName = location == .custom
            ? customURL?.lastPathComponent ?? StorageLocationService.shared.customFolderDisplayName
            : nil

        return HStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: location.sfSymbol)
                .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.secondaryLabel)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                Text(location.displayName)
                if let customName {
                    Text(customName)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
                Text(location.description)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ location: StorageLocationService.Location) {
        selectedLocation = location
        if location == .custom {
            showFolderPicker = true
        } else {
            customURL = nil
        }
    }

    private var hasLocationChange: Bool {
        if selectedLocation == .custom, customURL != nil { return true }
        return selectedLocation != StorageLocationService.shared.currentLocation
    }

    private func applyChange() async {
        await viewModel.migrateStorage(
            to: selectedLocation,
            customURL: customURL,
            appContainer: appContainer
        )
        if viewModel.storageMigrationError == nil { dismiss() }
    }
}

// MARK: - Backups

private struct BackupSettingsView: View {
    @Environment(AppContainer.self) private var appContainer
    @Binding var isEnabled: Bool
    let operationsBusy: Bool
    let chooseFolder: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Periodic Backup", isOn: $isEnabled)
                    .disabled(backup.isRunning || operationsBusy)
            } footer: {
                Text("Automatically keeps one restorable vault backup in a folder you choose.")
            }

            if isEnabled {
                Section {
                    Picker("Frequency", selection: Binding(
                        get: { backup.schedule.frequency },
                        set: { backup.updateFrequency($0) }
                    )) {
                        ForEach(BackupFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .pickerStyle(.segmented)

                    if backup.schedule.frequency == .weekly {
                        Picker("Day", selection: Binding(
                            get: { backup.schedule.weekday },
                            set: { backup.updateWeekday($0) }
                        )) {
                            ForEach(
                                Array(Calendar.autoupdatingCurrent.weekdaySymbols.enumerated()),
                                id: \.offset
                            ) { index, name in
                                Text(name).tag(index + 1)
                            }
                        }
                    }

                    DatePicker(
                        "Time",
                        selection: backupTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("iOS may run a missed backup later when background time becomes available.")
                }
                .disabled(backup.isRunning || operationsBusy)

                Section {
                    Button(action: chooseFolder) {
                        LabeledContent(
                            "Backup Location",
                            value: backup.folderDisplayName ?? "Choose Folder"
                        )
                    }
                    .foregroundStyle(AppTheme.Colors.label)
                    .disabled(backup.isRunning || operationsBusy)

                    Button {
                        Task {
                            let succeeded = await backup.backupNow()
                            if succeeded {
                                HapticFeedback.success()
                                UIAccessibility.post(
                                    notification: .announcement,
                                    argument: "Backup complete."
                                )
                            } else {
                                HapticFeedback.error()
                                UIAccessibility.post(
                                    notification: .announcement,
                                    argument: "Backup failed."
                                )
                            }
                        }
                    } label: {
                        ProgressActionLabel(
                            title: backup.isRunning ? "Backing Up…" : "Back Up Now",
                            progress: backup.isRunning ? backup.progress : nil,
                            symbol: "arrow.clockwise"
                        )
                    }
                    .disabled(!backup.hasDestination || backup.isRunning || operationsBusy)
                }

                if backup.lastSuccess != nil || backup.nextScheduledDate != nil || backup.latestError != nil {
                    Section("Status") {
                        if let lastSuccess = backup.lastSuccess {
                            LabeledContent(
                                "Last Backup",
                                value: lastSuccess.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                        if let next = backup.nextScheduledDate {
                            LabeledContent(
                                "Next Backup",
                                value: next.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                        if let error = backup.latestError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .accessibilityLabel("Backup error: \(error)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var backup: PeriodicBackupService {
        appContainer.periodicBackup
    }

    private var backupTimeBinding: Binding<Date> {
        let calendar = Calendar.autoupdatingCurrent
        let value = calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: 2001,
                month: 1,
                day: 1,
                hour: backup.schedule.hour,
                minute: backup.schedule.minute
            )
        ) ?? Date()

        return Binding(
            get: { value },
            set: { newValue in
                let components = calendar.dateComponents([.hour, .minute], from: newValue)
                backup.updateTime(
                    hour: components.hour ?? 21,
                    minute: components.minute ?? 0
                )
            }
        )
    }
}

// MARK: - Data Management

private struct DataManagementView: View {
    let operation: DataOperation
    let exportProgress: Double
    let importProgress: Double
    let backupIsRunning: Bool
    let exportVault: () -> Void
    let chooseImport: () -> Void
    let confirmDelete: () -> Void

    var body: some View {
        Form {
            Section {
                Button(action: exportVault) {
                    ProgressActionLabel(
                        title: operation == .exporting ? "Exporting…" : "Export Vault",
                        progress: operation == .exporting ? exportProgress : nil,
                        symbol: "square.and.arrow.up"
                    )
                }
                .disabled(operation.isBusy || backupIsRunning)

                Button(action: chooseImport) {
                    ProgressActionLabel(
                        title: operation == .importing ? "Importing…" : "Import Vault",
                        progress: operation == .importing ? importProgress : nil,
                        symbol: "square.and.arrow.down"
                    )
                }
                .disabled(operation.isBusy || backupIsRunning)
            } header: {
                Text("Transfer")
            } footer: {
                Text("Export creates a ZIP backup. Import replaces the current vault with a compatible backup.")
            }

            Section {
                Button(role: .destructive, action: confirmDelete) {
                    HStack {
                        Label(
                            operation == .deleting ? "Deleting…" : "Delete All Data",
                            systemImage: "trash"
                        )
                        Spacer()
                        if operation == .deleting { ProgressView() }
                    }
                }
                .disabled(operation.isBusy || backupIsRunning)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Deletes local items, tags, history, and files. This cannot be undone.")
            }
        }
        .navigationTitle("Data Management")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProgressActionLabel: View {
    let title: String
    let progress: Double?
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if let progress {
                    Text("\(Int(progress * 100))%")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .monospacedDigit()
                }
            }
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel(title)
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }
        }
    }
}

private struct AboutFindlyView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersion)
                Link(destination: URL(string: "https://github.com/google/GoogleSignIn-iOS")!) {
                    Label("Open Source Libraries", systemImage: "curlybraces")
                }
            }
        }
        .navigationTitle("About Findly")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Folder Picker

private struct BackupFolderPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onSelection: ([URL]) -> Void
    let onCancellation: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPresented: $isPresented,
            onSelection: onSelection,
            onCancellation: onCancellation
        )
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let isPresented: Binding<Bool>
        let onSelection: ([URL]) -> Void
        let onCancellation: () -> Void

        init(
            isPresented: Binding<Bool>,
            onSelection: @escaping ([URL]) -> Void,
            onCancellation: @escaping () -> Void
        ) {
            self.isPresented = isPresented
            self.onSelection = onSelection
            self.onCancellation = onCancellation
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            isPresented.wrappedValue = false
            onSelection(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented.wrappedValue = false
            onCancellation()
        }
    }
}

#Preview("Settings - Disconnected") {
    SettingsView()
        .environment(AppContainer())
        .modelContainer(PersistenceController.preview.container)
}

#Preview("Settings - Dark, Large Text") {
    SettingsView()
        .environment(AppContainer())
        .modelContainer(PersistenceController.preview.container)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Data Management - Exporting") {
    NavigationStack {
        DataManagementView(
            operation: .exporting,
            exportProgress: 0.46,
            importProgress: 0,
            backupIsRunning: false,
            exportVault: {},
            chooseImport: {},
            confirmDelete: {}
        )
    }
}
