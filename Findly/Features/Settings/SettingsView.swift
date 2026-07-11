import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {

    @Environment(AppContainer.self) private var appContainer
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var viewModel = SettingsViewModel()
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                googleDriveSection
                syncSection
                themeSection
                securitySection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                Task { await viewModel.loadDriveStats(appContainer: appContainer) }
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
                // User info
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appContainer.auth.userName ?? "Google User")
                            .font(AppTheme.Typography.headline)
                        Text(appContainer.auth.userEmail ?? "")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
                    Spacer()
                    // Connection indicator
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                }

                // Storage gauge
                if viewModel.driveTotalBytes > 0 {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                        HStack {
                            Text("Drive Storage")
                                .font(AppTheme.Typography.subheadline)
                            Spacer()
                            Text("\(viewModel.driveUsedBytes.fileSizeString) / \(viewModel.driveTotalBytes.fileSizeString)")
                                .font(AppTheme.Typography.caption1)
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        }
                        ProgressView(value: Double(viewModel.driveUsedBytes),
                                     total: Double(viewModel.driveTotalBytes))
                            .tint(AppTheme.Colors.accent)
                    }
                }

                Button(role: .destructive) {
                    appContainer.auth.signOut()
                } label: {
                    Text("Disconnect Google Drive")
                }
            } else {
                // Sign in button
                Button {
                    Task {
                        try? await appContainer.auth.signIn()
                        if appContainer.auth.isAuthenticated {
                            // Promote all local-only items and kick off sync
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
            Label("Google Drive (Optional)", systemImage: "externaldrive.connected.to.line.below.fill")
        } footer: {
            Text(appContainer.auth.isAuthenticated
                 ? "Files are backed up to the Findly folder in your Google Drive."
                 : "Google Drive is optional. Your files are stored safely on this device. Connect Drive anytime to enable cloud backup and sync.")
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section {
            if appContainer.auth.isAuthenticated {
                // Sync status row
                HStack {
                    Label("Status", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    syncStatusIndicator
                }

                if let lastSync = viewModel.lastSyncDate {
                    HStack {
                        Label("Last Synced", systemImage: "clock")
                        Spacer()
                        Text(lastSync.relativeString)
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
                }

                Toggle(isOn: $viewModel.autoSyncEnabled) {
                    Label("Auto Sync", systemImage: "bolt.fill")
                }

                Button {
                    Task { await viewModel.manualSync(appContainer: appContainer) }
                } label: {
                    HStack {
                        if appContainer.sync.isSyncing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Sync Now")
                    }
                }
                .disabled(appContainer.sync.isSyncing)
            } else {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "iphone")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    Text("Files are stored on this device only")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .font(AppTheme.Typography.subheadline)
                }
            }
        } header: {
            Text("Synchronization")
        } footer: {
            if !appContainer.auth.isAuthenticated {
                Text("Connect Google Drive above to enable automatic cloud backup.")
            }
        }
    }

    @ViewBuilder
    private var syncStatusIndicator: some View {
        let sync = appContainer.sync
        HStack(spacing: 6) {
            Circle()
                .fill(sync.isSyncing ? Color.yellow : (sync.pendingCount == 0 ? Color.green : Color.orange))
                .frame(width: 8, height: 8)
            Text(sync.isSyncing ? "Syncing…" : (sync.pendingCount == 0 ? "Up to date" : "\(sync.pendingCount) pending"))
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        Section {
            Toggle(isOn: $appLockEnabled) {
                Label("App Lock", systemImage: "lock.fill")
            }
            .onChange(of: appLockEnabled) { _, enabled in
                if enabled {
                    // Immediately verify the user can authenticate before enabling
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
            Text("Security")
        } footer: {
            Text("Requires Face ID, Touch ID, or passcode to open Findly.")
        }
    }

    // MARK: - Theme

    private var themeSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceMode) {
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("System").tag("system")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button {
                exportVault()
            } label: {
                HStack {
                    Label("Export Vault", systemImage: "archivebox.circle.fill")
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
            Link(destination: URL(string: "https://github.com/google/GoogleSignIn-iOS")!) {
                Label("Open Source Libraries", systemImage: "heart.fill")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppContainer())
        .modelContainer(PersistenceController.preview.container)
}
