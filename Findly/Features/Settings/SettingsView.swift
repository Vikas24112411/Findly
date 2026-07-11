import SwiftUI

struct SettingsView: View {

    @Environment(AppContainer.self) private var appContainer
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                googleDriveSection
                syncSection
                themeSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                Task { await viewModel.loadDriveStats(appContainer: appContainer) }
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
