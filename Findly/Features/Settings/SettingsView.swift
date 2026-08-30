import SwiftUI
import SwiftData
import LocalAuthentication
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {

    @Environment(AppContainer.self) private var appContainer
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("showRecentItems")   private var showRecentItems   = true
    @AppStorage("showFrequentItems") private var showFrequentItems = true
    @AppStorage("showPinnedItems")   private var showPinnedItems   = true
    @AppStorage("showFavoriteItems") private var showFavoriteItems = false
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
    // Periodic backup
    @State private var showBackupFolderPicker = false
    @State private var enableAfterBackupFolderSelection = false
    @State private var periodicBackupToggleState = false
    @State private var backupConfigurationError: String?
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
                periodicBackupSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .trackScrollOffset($scrollOffset)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                Task {
                    await viewModel.loadDriveStats(appContainer: appContainer)
                    await viewModel.loadLocalStorageSize(appContainer: appContainer)
                }
                periodicBackupToggleState = appContainer.periodicBackup.isEnabled
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
            .sheet(isPresented: $showBackupFolderPicker) {
                BackupFolderPickerView(
                    isPresented: $showBackupFolderPicker,
                    onSelection: { urls in
                        handleBackupFolderSelection(.success(urls))
                    },
                    onCancellation: {
                        handleBackupFolderPickerCancellation()
                    }
                )
                .ignoresSafeArea()
                .interactiveDismissDisabled()
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

    @ViewBuilder private var preferencesSection: some View {
        Section {
            Picker("Appearance", selection: $appearanceMode) {
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("System").tag("system")
            }
            .pickerStyle(.segmented)

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

        Section {
            Toggle("Recent", isOn: $showRecentItems)
            Toggle("Most Used", isOn: $showFrequentItems)
            Toggle("Pinned", isOn: $showPinnedItems)
            Toggle("Favorites", isOn: $showFavoriteItems)
        } header: {
            Text("Home Shelves")
        } footer: {
            Text("Choose which shelves appear on the Home page.")
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        Section {
            NavigationLink {
                InsightsCustomizationView(
                    showStorageGrowth: $insightsShowStorageGrowth,
                    showWeeklyActivity: $insightsShowWeeklyActivity,
                    showFileTypes: $insightsShowFileTypes,
                    showStorageByType: $insightsShowStorageByType,
                    showTopTags: $insightsShowTopTags,
                    showTagHeatmap: $insightsShowTagHeatmap,
                    showMostOpened: $insightsShowMostOpened,
                    showLargestFiles: $insightsShowLargestFiles
                )
            } label: {
                let activeCount = [insightsShowStorageGrowth, insightsShowWeeklyActivity,
                                   insightsShowFileTypes, insightsShowStorageByType,
                                   insightsShowTopTags, insightsShowTagHeatmap,
                                   insightsShowMostOpened, insightsShowLargestFiles].filter { $0 }.count
                HStack {
                    Text("Customize Insights")
                    Spacer()
                    Text("\(activeCount) of 8")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
        } header: {
            Text("Insights")
        } footer: {
            Text("Choose which sections appear in the Insights tab.")
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

    // MARK: - Periodic Backup

    private var periodicBackupSection: some View {
        let backup = appContainer.periodicBackup
        let operationsBusy = isExporting || isImporting || viewModel.isDeletingAll

        return Section {
            Toggle("Periodic Backup", isOn: Binding(
                get: { periodicBackupToggleState },
                set: { setPeriodicBackupEnabled($0) }
            ))
            .disabled(backup.isRunning || operationsBusy)

            if periodicBackupToggleState {
                Picker("Frequency", selection: Binding(
                    get: { backup.schedule.frequency },
                    set: { backup.updateFrequency($0) }
                )) {
                    ForEach(BackupFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(backup.isRunning || operationsBusy)

                HStack {
                    Text("Schedule")
                    Spacer()

                    if backup.schedule.frequency == .weekly {
                        Picker("Day", selection: Binding(
                            get: { backup.schedule.weekday },
                            set: { backup.updateWeekday($0) }
                        )) {
                            ForEach(Array(Calendar.autoupdatingCurrent.weekdaySymbols.enumerated()), id: \.offset) { index, name in
                                Text(name).tag(index + 1)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    DatePicker(
                        "Time",
                        selection: backupTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
                .disabled(backup.isRunning || operationsBusy)

                Button {
                    enableAfterBackupFolderSelection = false
                    showBackupFolderPicker = true
                } label: {
                    HStack {
                        Text("Backup Location")
                        Spacer()
                        Text(backup.folderDisplayName ?? "Choose Folder")
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    }
                }
                .disabled(backup.isRunning || operationsBusy)

                Button {
                    Task {
                        let succeeded = await backup.backupNow()
                        if succeeded { HapticFeedback.success() } else { HapticFeedback.error() }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(backup.isRunning ? "Backing Up…" : "Back Up Now")
                                .foregroundStyle(AppTheme.Colors.accent)
                            Spacer()
                            if backup.isRunning {
                                Text("\(Int(backup.progress * 100))%")
                                    .font(AppTheme.Typography.subheadline)
                                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                                    .monospacedDigit()
                            }
                        }
                        if backup.isRunning {
                            ProgressView(value: backup.progress)
                                .progressViewStyle(.linear)
                                .tint(AppTheme.Colors.accent)
                        }
                    }
                }
                .disabled(!backup.hasDestination || backup.isRunning || operationsBusy)

                if backup.lastSuccess != nil || backup.nextScheduledDate != nil {
                    VStack(alignment: .leading, spacing: 3) {
                        if let lastSuccess = backup.lastSuccess {
                            Text("Last: \(lastSuccess.formatted(date: .abbreviated, time: .shortened))")
                        }
                        if let next = backup.nextScheduledDate {
                            Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }

                if let error = backup.latestError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTheme.Typography.caption1)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Periodic Backup")
        } footer: {
            if periodicBackupToggleState {
                Text("\(backup.schedule.description()). iOS may run a missed backup later when background time is available.")
            } else {
                Text("Automatically keep one restorable vault backup in a folder you choose.")
            }
        }
        .alert("Periodic Backup", isPresented: Binding(
            get: { backupConfigurationError != nil },
            set: { if !$0 { backupConfigurationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupConfigurationError ?? "")
        }
    }

    private func setPeriodicBackupEnabled(_ enabled: Bool) {
        let backup = appContainer.periodicBackup

        if !enabled {
            periodicBackupToggleState = false
            try? backup.setEnabled(false)
            return
        }

        guard backup.hasDestination else {
            // Reflect the user's intent immediately. The service itself remains
            // disabled until a destination is successfully selected.
            periodicBackupToggleState = true
            enableAfterBackupFolderSelection = true
            presentBackupFolderPicker()
            return
        }

        do {
            try backup.setEnabled(true)
            periodicBackupToggleState = backup.isEnabled
        } catch {
            // The stored bookmark is missing or no longer usable. Let the user
            // replace it immediately instead of leaving an unexplained off switch.
            periodicBackupToggleState = true
            enableAfterBackupFolderSelection = true
            presentBackupFolderPicker()
        }
    }

    private func presentBackupFolderPicker() {
        Task { @MainActor in
            // Present after the Toggle's binding transaction completes. Presenting
            // synchronously from its setter can be ignored by SwiftUI.
            await Task.yield()
            showBackupFolderPicker = true
        }
    }

    private func handleBackupFolderSelection(_ result: Result<[URL], Error>) {
        let shouldEnable = enableAfterBackupFolderSelection
        enableAfterBackupFolderSelection = false

        guard case .success(let urls) = result, let url = urls.first else {
            if shouldEnable {
                periodicBackupToggleState = false
            }
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            try appContainer.periodicBackup.setDestination(url)
            if shouldEnable {
                try appContainer.periodicBackup.setEnabled(true)
            }
            periodicBackupToggleState = appContainer.periodicBackup.isEnabled
        } catch {
            if shouldEnable {
                periodicBackupToggleState = false
            }
            backupConfigurationError = error.localizedDescription
            HapticFeedback.error()
        }
    }

    private func handleBackupFolderPickerCancellation() {
        let shouldDisable = enableAfterBackupFolderSelection
        enableAfterBackupFolderSelection = false
        if shouldDisable {
            periodicBackupToggleState = false
        }
    }

    private var backupTimeBinding: Binding<Date> {
        let calendar = Calendar.autoupdatingCurrent
        let backup = appContainer.periodicBackup
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
            .disabled(isExporting || isImporting || appContainer.periodicBackup.isRunning)

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
            .disabled(isImporting || isExporting || appContainer.periodicBackup.isRunning)

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
            .disabled(viewModel.isDeletingAll || isImporting || appContainer.periodicBackup.isRunning)
        } header: {
            Text("Data")
        } footer: {
            Text("Export creates a .zip backup. Import replaces all data from a backup. Deleting local data cannot be undone.")
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

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

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

// MARK: - Insights customization sub-view

private struct InsightsCustomizationView: View {

    @Binding var showStorageGrowth: Bool
    @Binding var showWeeklyActivity: Bool
    @Binding var showFileTypes: Bool
    @Binding var showStorageByType: Bool
    @Binding var showTopTags: Bool
    @Binding var showTagHeatmap: Bool
    @Binding var showMostOpened: Bool
    @Binding var showLargestFiles: Bool

    var body: some View {
        Form {
            Section("Storage") {
                Toggle("Storage Growth",  isOn: $showStorageGrowth)
                Toggle("Added This Week", isOn: $showWeeklyActivity)
                Toggle("File Types",      isOn: $showFileTypes)
                Toggle("Storage by Type", isOn: $showStorageByType)
            }
            Section("Tags") {
                Toggle("Top Tags",     isOn: $showTopTags)
                Toggle("Tag Activity", isOn: $showTagHeatmap)
            }
            Section("Files") {
                Toggle("Most Opened",   isOn: $showMostOpened)
                Toggle("Largest Files", isOn: $showLargestFiles)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environment(AppContainer())
        .modelContainer(PersistenceController.preview.container)
}
