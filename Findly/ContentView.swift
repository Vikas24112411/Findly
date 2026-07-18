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
    @State private var showSearch = false
    @State private var showRadialMenu = false
    @State private var fabIconRotated = false
    @State private var lockManager = AppLockManager()
    @State private var showStoreRecoveryAlert = false
    @State private var fabDragPoint: CGPoint? = nil
    @State private var fabDragEndTrigger: Int = 0

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
        .onChange(of: showRadialMenu) { _, newValue in
            if !newValue { fabIconRotated = false }
        }
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
            Text("The database couldn't be migrated. A backup was saved and your vault has been reset. Contact support to recover your data.")
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            // Radial long-press menu overlay
            if showRadialMenu {
                RadialMenuView(
                    isVisible: $showRadialMenu,
                    dragPoint: fabDragPoint,
                    dragEndTrigger: fabDragEndTrigger,
                    onOptionCommitted: {
                        withAnimation(AppTheme.Animation.snappy) {
                            fabIconRotated = false
                        }
                    }
                )
                .environment(appContainer)
                .transition(.opacity)
                .zIndex(10)
            }

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

            // Floating buttons — overlaid above the tab bar
            HStack {
                // Search FAB — left side
                Button {
                    HapticFeedback.medium()
                    showSearch = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.accent)
                            .frame(width: 56, height: 56)
                            .shadow(color: AppTheme.Shadow.fab.color,
                                    radius: AppTheme.Shadow.fab.radius,
                                    x: AppTheme.Shadow.fab.x,
                                    y: AppTheme.Shadow.fab.y)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(FABButtonStyle())
                .accessibilityLabel("Search vault")
                .padding(.leading, AppTheme.Spacing.large)

                Spacer()

                // Add FAB — right side
                FABView(
                    showSheet: $showAddSheet,
                    isRadialOpen: fabIconRotated,
                    onLongPress: {
                        withAnimation(AppTheme.Animation.fast) {
                            showRadialMenu = true
                            fabIconRotated = true
                        }
                    },
                    onDragChanged: { pt in
                        guard showRadialMenu else { return }
                        fabDragPoint = pt
                    },
                    onDragEnded: { pt in
                        guard showRadialMenu else { return }
                        fabDragPoint = pt
                        fabDragEndTrigger += 1
                    }
                )
                .padding(.trailing, AppTheme.Spacing.large)
            }
            .padding(.bottom, 90)
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemSheetView()
                .environment(appContainer)
        }
        .fullScreenCover(isPresented: $showSearch) {
            NavigationStack {
                HomeSearchView()
            }
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
