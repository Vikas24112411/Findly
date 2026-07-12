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

    var body: some View {
        NavigationStack {
            Form {
                googleDriveSection
                syncSection
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
                }}
            )) {
                if let url = exportURL { ShareSheet(items: [url]) }
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

                Button(role: .destructive) {
                    appContainer.auth.signOut()
                } label: {
                    Text("Disconnect")
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
                 : "Optional. Connect to back up your files to Google Drive.")
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section("Sync") {
            if appContainer.auth.isAuthenticated {
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
            } else {
                Text("Stored on this device")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var syncStatusIndicator: some View {
        let sync = appContainer.sync
        let statusText = sync.isSyncing ? "Syncing…" : (sync.pendingCount == 0 ? "Up to date" : "\(sync.pendingCount) pending")
        HStack(spacing: 6) {
            Circle()
                .fill(sync.isSyncing ? Color.yellow : (sync.pendingCount == 0 ? Color.green : Color.orange))
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
            Text("Choose which sections appear on the Insights page.")
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
            Text("Files are stored on this device. Changing the location will move all existing files.")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button {
                exportVault()
            } label: {
                HStack {
                    Text("Export Vault")
                        .foregroundStyle(AppTheme.Colors.accent)
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)
        } header: {
            Text("Data")
        } footer: {
            Text("Exports all locally stored files as a .zip archive.")
        }
    }

    private func exportVault() {
        isExporting = true
        Task {
            do {
                let items = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
                let url = try await appContainer.export.exportVault(
                    items: items,
                    localStorage: appContainer.localStorage
                )
                await MainActor.run {
                    exportURL = url
                    isExporting = false
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                    HapticFeedback.error()
                }
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
                    Text("Moving files may take a moment depending on how many files you have.")
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
