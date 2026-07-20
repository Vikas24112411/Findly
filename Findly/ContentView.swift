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
    @State private var searchConfig: SearchConfig? = nil
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
            // Radial long-press menu overlay — always in the hierarchy so it is pre-warmed
            // (view constructed, layout done, anchor position captured) before the user
            // long-presses. Visibility is controlled via opacity and hit-testing.
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
            .opacity(showRadialMenu ? 1 : 0)
            .allowsHitTesting(showRadialMenu)
            .zIndex(showRadialMenu ? 10 : 0)

            TabView(selection: $selectedTab) {
                HomeView(onSearch: { fileTypes, tag in
                    searchConfig = SearchConfig(fileTypes: fileTypes, tag: tag)
                })
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
            }
            .tint(AppTheme.Colors.accent)

            // Floating buttons — search pill (Home only) + add FAB, both in thumb zone
            HStack(spacing: AppTheme.Spacing.medium) {
                if selectedTab == .home {
                    SearchPillButton {
                        HapticFeedback.light()
                        searchConfig = SearchConfig()
                    }
                } else {
                    Spacer()
                }

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
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, 90)
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemSheetView()
                .environment(appContainer)
        }
        .fullScreenCover(item: $searchConfig) { config in
            NavigationStack {
                HomeSearchView(initialFilter: config.fileTypes, initialTag: config.tag)
            }
        }
    }
}

// MARK: - Tab enum

extension ContentView {
    enum Tab: Hashable {
        case home, knowledge, files, insights
    }
}

// MARK: - Search pill button

/// Wide tappable pill styled as a search bar, sits beside the add FAB in the thumb zone.
private struct SearchPillButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                Text("Search files, tags…")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: AppTheme.Shadow.fab.color,
                    radius: AppTheme.Shadow.fab.radius,
                    x: AppTheme.Shadow.fab.x,
                    y: AppTheme.Shadow.fab.y)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search configuration passed to HomeSearchView

struct SearchConfig: Identifiable {
    let id = UUID()
    let fileTypes: Set<FileType>
    let tag: Tag?

    init(fileTypes: Set<FileType> = [], tag: Tag? = nil) {
        self.fileTypes = fileTypes
        self.tag = tag
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(AppContainer())
        .modelContainer(PersistenceController.preview.container)
}
