import SwiftUI
import LocalAuthentication

/// Root view: TabView with four tabs + persistent floating action button.
struct ContentView: View {

    @Environment(AppContainer.self) private var appContainer
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .home
    @State private var showAddSheet = false
    @State private var lockManager = AppLockManager()
    @State private var showStoreRecoveryAlert = false

    var body: some View {
        ZStack {
            mainContent
            if lockManager.isLocked {
                AppLockView {
                    await lockManager.unlock()
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lockManager.isLocked)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && appLockEnabled {
                lockManager.lock()
            } else if phase == .active && lockManager.isLocked {
                Task { await lockManager.unlock() }
            }
        }
        .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil)
        .onAppear {
            showStoreRecoveryAlert = appContainer.persistence.storeWasRecovered
        }
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { _ in })) {
            OnboardingStorageView()
                .environment(appContainer)
        }
        .alert("Database Recovery", isPresented: $showStoreRecoveryAlert) {
            Button("OK") {}
        } message: {
            Text("The database couldn't be migrated to the latest format. A backup was saved to your device and your vault has been reset. Please contact support if you need help recovering your data.")
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(Tab.home)

                KnowledgeView()
                    .tabItem { Label("Tags", systemImage: "tag.fill") }
                    .tag(Tab.knowledge)

                FilesView()
                    .tabItem { Label("Files", systemImage: "doc.fill") }
                    .tag(Tab.files)

                InsightsView()
                    .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
                    .tag(Tab.insights)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(Tab.settings)
            }
            .tint(AppTheme.Colors.accent)

            // Floating action button — overlaid above the tab bar
            FABView(showSheet: $showAddSheet)
                .padding(.trailing, AppTheme.Spacing.large)
                .padding(.bottom, 90) // clear the tab bar
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemSheetView()
                .environment(appContainer)
        }
    }
}

// MARK: - Tab enum

extension ContentView {
    enum Tab: Hashable {
        case home, knowledge, files, insights, settings
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(AppContainer())
        .modelContainer(PersistenceController.preview.container)
}
