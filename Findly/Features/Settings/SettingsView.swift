import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {

    @Environment(AppContainer.self) private var appContainer
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("showRecentItems") private var showRecentItems = true
    @AppStorage("showFrequentItems") private var showFrequentItems = true
    @AppStorage("insightsShowStorageGrowth") private var insightsShowStorageGrowth = true
    @AppStorage("insightsShowWeeklyActivity") private var insightsShowWeeklyActivity = true
    @AppStorage("insightsShowFileTypes") private var insightsShowFileTypes = true
    @AppStorage("insightsShowStorageByType") private var insightsShowStorageByType = true
    @AppStorage("insightsShowTopTags") private var insightsShowTopTags = true
    @AppStorage("insightsShowTagHeatmap") private var insightsShowTagHeatmap = true
    @AppStorage("insightsShowMostOpened") private var insightsShowMostOpened = true
    @AppStorage("insightsShowLargestFiles") private var insightsShowLargestFiles = true
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var viewModel = SettingsViewModel()
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var scrollOffset: CGFloat = 0
    @State private var showStoragePicker = false
    // Export success flow
    @State private var exportedVaultURL: URL?
    @State private var exportSuccess = false
    // Import
    @State private var showImportPicker = false
    @State private var pendingImportURL: URL?
    @State private var showImportConfirmation = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importSuccess = false
    // Delete all
    @State private var showDeleteConfirmation = false
    @State private var deleteSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                googleDriveSection
                preferencesSection
                insightsSection
                localStorageSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .trackScrollOffset($scrollOffset)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(scrollOffset > 10 ? .visible : .hidden, for: .navigationBar)
            .onAppear {
                Task {
                    await viewModel.loadDriveStats(appContainer: appContainer)
                    await viewModel.loadLocalStorageSize(appContainer: appContainer)
                }
            }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { if !$0 {
                    if let url = exportURL { try? FileManager.default.removeItem(at: url) }
                    exportURL = nil
                    exportedVaultURL = nil
                }}
            )) {
                if let url = exportURL { ShareSheet(items: [url]) }
            }
            .alert("Export Complete", isPresented: $exportSuccess) {
                Button("Share") { exportURL = exportedVaultURL }
                Button("Done", role: .cancel) {
                    if let url = exportedVaultURL { try? FileManager.default.removeItem(at: url) }
                    exportedVaultURL = nil
                }
            } message: {
                Text("Your vault has been exported successfully.")
            }
            .alert("Data Deleted", isPresented: $deleteSuccess) {
                Button("OK") {}
            } message: {
                Text("All local data has been deleted.")
            }
            .sheet(isPresented: $showStoragePicker) {
                StorageLocationPickerView(viewModel: viewModel)
                    .environment(appContainer)
            }
            .alert("Storage Move Failed", isPresented: Binding(
                get: { viewModel.storageMigrationError != nil },
                set: { if !$0 { viewModel.storageMigrationError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.storageMigrationError ?? "")
            }
            .alert("Export Failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    // Copy to temp so we can read it after security-scoped access ends.
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: tempURL)
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        pendingImportURL = tempURL
                        showImportConfirmation = true
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
            .alert("Import Vault", isPresented: $showImportConfirmation) {
                Button("Replace and Import", role: .destructive) {
                    if let url = pendingImportURL { importVault(from: url) }
                }
                Button("Cancel", role: .cancel) { pendingImportURL = nil }
            } message: {
                Text("Replaces all current data with the imported vault.")
            }
            .alert("Delete All Data", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    Task {
                        await viewModel.deleteAllData(
                            localStorage: appContainer.localStorage,
                            context: modelContext
                        )
                        if viewModel.deleteError == nil {
                            deleteSuccess = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes all local data. Synced files on Google Drive are unaffected.")
            }
            .alert("Delete Failed", isPresented: Binding(
                get: { viewModel.deleteError != nil },
                set: { if !$0 { viewModel.deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.deleteError ?? "")
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .alert("Import Complete", isPresented: $importSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your vault has been restored successfully.")
            }
        }
    }

    // MARK: - Google Drive

    private var googleDriveSection: some View {
        Section {
            if appContainer.auth.isAuthenticated {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "person.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appContainer.auth.userName ?? "Google User")
                            .font(AppTheme.Typography.headline)
                        Text(appContainer.auth.userEmail ?? "")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
                    Spacer()
                    if viewModel.driveTotalBytes > 0 {
                        Text("\(viewModel.driveUsedBytes.fileSizeString) / \(viewModel.driveTotalBytes.fileSizeString)")
                            .font(AppTheme.Typography.caption1)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
                }

                HStack {
                    Text("Status")
                    Spacer()
                    syncStatusIndicator
                }

                Toggle("Auto Sync", isOn: $viewModel.autoSyncEnabled)

                Button {
                    Task { await viewModel.manualSync(appContainer: appContainer) }
                } label: {
                    HStack {
                        if appContainer.sync.isSyncing {
                            ProgressView().scaleEffect(0.8)
                        }
                        Text("Sync Now")
                    }
                }
                .disabled(appContainer.sync.isSyncing)

                Button("Disconnect", role: .destructive) {
                    appContainer.auth.signOut()
                }
            } else {
                Button {
                    Task {
                        try? await appContainer.auth.signIn()
                        if appContainer.auth.isAuthenticated {
                            appContainer.sync.promoteLocalOnlyItems()
                            await appContainer.sync.syncPendingItems()
                            await viewModel.loadDriveStats(appContainer: appContainer)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Connect Google Drive")
                    }
                }
            }
        } header: {
            Text("Google Drive")
        } footer: {
            Text(appContainer.auth.isAuthenticated
                 ? "Backed up to your Google Drive."
                 : "Optional. Back up your files to Google Drive.")
        }
    }

    @ViewBuilder
    private var syncStatusIndicator: some View {
        let sync = appContainer.sync
        let statusText = sync.isSyncing ? "Syncing…" : (sync.pendingCount == 0 ? "Up to date" : "\(sync.pendingCount) pending")
        HStack(spacing: 6) {
            Circle()
                .fill(sync.isSyncing ? AppTheme.Colors.syncPending : (sync.pendingCount == 0 ? AppTheme.Colors.syncSynced : AppTheme.Colors.syncFailed))
                .frame(width: 8, height: 8)
            if let lastSync = viewModel.lastSyncDate {
                Text("\(statusText) · \(lastSync.shortRelativeString)")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            } else {
                Text(statusText)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section {
            Picker("Appearance", selection: $appearanceMode) {
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("System").tag("system")
            }
            .pickerStyle(.segmented)

            Toggle("Continue Where You Left Off", isOn: $showRecentItems)
            Toggle("Frequently Opened", isOn: $showFrequentItems)
            Toggle("App Lock", isOn: $appLockEnabled)
                .onChange(of: appLockEnabled) { _, enabled in
                    if enabled {
                        Task {
                            let ctx = LAContext()
                            var err: NSError?
                            guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
                                appLockEnabled = false
                                return
                            }
                            let ok = try? await ctx.evaluatePolicy(
                                .deviceOwnerAuthentication,
                                localizedReason: "Enable App Lock"
                            )
                            if ok != true { appLockEnabled = false }
                        }
                    }
                }
        } header: {
            Text("Preferences")
        } footer: {
            Text("App Lock requires Face ID, Touch ID, or passcode.")
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        Section {
            Toggle("Storage Growth", isOn: $insightsShowStorageGrowth)
            Toggle("Added This Week", isOn: $insightsShowWeeklyActivity)
            Toggle("File Types", isOn: $insightsShowFileTypes)
            Toggle("Storage by Type", isOn: $insightsShowStorageByType)
            Toggle("Top Tags", isOn: $insightsShowTopTags)
            Toggle("Tag Activity", isOn: $insightsShowTagHeatmap)
            Toggle("Most Opened", isOn: $insightsShowMostOpened)
            Toggle("Largest Files", isOn: $insightsShowLargestFiles)
        } header: {
            Text("Insights")
        } footer: {
            Text("Choose which sections appear in Insights.")
        }
    }

    // MARK: - Local Storage

    private var localStorageSection: some View {
        let storageService = StorageLocationService.shared
        let locationName: String = {
            if storageService.currentLocation == .custom,
               let folderName = storageService.customFolderDisplayName {
                return folderName
            }
            return storageService.currentLocation.displayName
        }()

        return Section {
            HStack {
                Text("Location")
                Spacer()
                if viewModel.isMigratingStorage {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text(locationName)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showStoragePicker = true }

            HStack {
                Text("Storage Used")
                Spacer()
                Text(viewModel.localStorageSize.fileSizeString)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
        } header: {
            Text("Local Storage")
        } footer: {
            Text("Changing the location will move all existing files.")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button {
                exportVault()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(isExporting ? "Exporting…" : "Export Vault")
                            .foregroundStyle(AppTheme.Colors.accent)
                        Spacer()
                        if isExporting {
                            Text("\(Int(viewModel.exportProgress * 100))%")
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                                .monospacedDigit()
                                .font(AppTheme.Typography.subheadline)
                        }
                    }
                    if isExporting {
                        ProgressView(value: viewModel.exportProgress)
                            .progressViewStyle(.linear)
                            .tint(AppTheme.Colors.accent)
                    }
                }
            }
            .disabled(isExporting || isImporting)

            Button {
                showImportPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(isImporting ? "Importing…" : "Import Vault")
                            .foregroundStyle(AppTheme.Colors.accent)
                        Spacer()
                        if isImporting {
                            Text("\(Int(viewModel.importProgress * 100))%")
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                                .monospacedDigit()
                                .font(AppTheme.Typography.subheadline)
                        }
                    }
                    if isImporting {
                        ProgressView(value: viewModel.importProgress)
                            .progressViewStyle(.linear)
                            .tint(AppTheme.Colors.accent)
                    }
                }
            }
            .disabled(isImporting || isExporting)
        } header: {
            Text("Data")
        } footer: {
            Text("Export creates a .zip backup. Import replaces all data from a backup.")
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    if viewModel.isDeletingAll {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text(viewModel.isDeletingAll ? "Deleting…" : "Delete All Data")
                }
            }
            .disabled(viewModel.isDeletingAll || isImporting)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Permanently deletes all local data. Cannot be undone.")
        }
    }

    private func exportVault() {
        isExporting = true
        viewModel.exportProgress = 0
        let vm = viewModel
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
                    onProgress: { @MainActor progress in vm.exportProgress = progress }
                )
                exportedVaultURL = url
                isExporting = false
                exportSuccess = true
                HapticFeedback.success()
            } catch {
                exportError = error.localizedDescription
                isExporting = false
                HapticFeedback.error()
            }
        }
    }

    private func importVault(from url: URL) {
        isImporting = true
        viewModel.importProgress = 0
        let vm = viewModel
        Task {
            do {
                try await appContainer.importService.importVault(
                    from: url,
                    localStorage: appContainer.localStorage,
                    context: modelContext,
                    onProgress: { @MainActor progress in vm.importProgress = progress }
                )
                try? FileManager.default.removeItem(at: url)
                isImporting = false
                pendingImportURL = nil
                importSuccess = true
                await viewModel.loadLocalStorageSize(appContainer: appContainer)
                HapticFeedback.success()
            } catch {
                try? FileManager.default.removeItem(at: url)
                importError = error.localizedDescription
                isImporting = false
                pendingImportURL = nil
                HapticFeedback.error()
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
            Link("Open Source Libraries", destination: URL(string: "https://github.com/google/GoogleSignIn-iOS")!)
        }
    }
}

// MARK: - Storage location picker sheet

private struct StorageLocationPickerView: View {

    @Environment(AppContainer.self) private var appContainer
    @Environment(\.dismiss) private var dismiss

    var viewModel: SettingsViewModel

    @State private var selectedLocation: StorageLocationService.Location =
        StorageLocationService.shared.currentLocation
    @State private var customURL: URL?
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StorageLocationService.Location.allCases, id: \.self) { location in
                        locationRow(for: location)
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
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Move Files")
                        }
                    }
                    .disabled(viewModel.isMigratingStorage || selectedLocation == StorageLocationService.shared.currentLocation)
                }
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                customURL = url
                Task { await applyChange() }
            }
        }
        .interactiveDismissDisabled(viewModel.isMigratingStorage)
    }

    private func locationRow(for location: StorageLocationService.Location) -> some View {
        let isSelected = selectedLocation == location
        let customName: String? = location == .custom ? customURL?.lastPathComponent
            ?? StorageLocationService.shared.customFolderDisplayName : nil

        return HStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: location.sfSymbol)
                .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.secondaryLabel)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(location.displayName)
                    if let name = customName {
                        Text("→ \(name)")
                            .font(AppTheme.Typography.caption1)
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
                Text(location.description)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if location == .custom {
                selectedLocation = .custom
                showFolderPicker = true
            } else {
                selectedLocation = location
                customURL = nil
            }
        }
    }

    private func applyChange() async {
        await viewModel.migrateStorage(to: selectedLocation, customURL: customURL, appContainer: appContainer)
        if viewModel.storageMigrationError == nil {
            dismiss()
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppContainer())
        .modelContainer(PersistenceController.preview.container)
}
