import SwiftUI
import LocalAuthentication

/// Root view: TabView with five tabs + persistent floating action button.
struct ContentView: View {

    @Environment(AppContainer.self) private var appContainer
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home
    @State private var showAddSheet = false
    @State private var pendingSearchConfig: SearchConfig? = nil
    @State private var tabSearchText: String = ""
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
                Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                    HomeView(onSearch: { fileTypes, tag in
                        pendingSearchConfig = SearchConfig(fileTypes: fileTypes, tag: tag)
                        selectedTab = .search
                    })
                }

                Tab("Tags", systemImage: "tag.fill", value: AppTab.knowledge) {
                    KnowledgeView()
                }

                Tab("Files", systemImage: "doc.fill", value: AppTab.files) {
                    FilesView()
                }

                Tab("Insights", systemImage: "chart.bar.fill", value: AppTab.insights) {
                    InsightsView()
                }

                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                    NavigationStack {
                        HomeSearchView(
                            searchText: $tabSearchText,
                            pendingConfig: $pendingSearchConfig
                        )
                    }
                    .searchable(text: $tabSearchText)
                }
            }
            .tint(AppTheme.Colors.accent)
            
            LiquidTabBar(
                    selectedTab: $selectedTab,
                    isCollapsed: isScrollingDown
                )

            // Floating add FAB — hidden on Search tab
            if selectedTab != .search {
                HStack {
                    Spacer()
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
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemSheetView()
                .environment(appContainer)
        }
    }
}

// MARK: - Tab enum

extension ContentView {
    enum AppTab: Hashable {
        case home, knowledge, files, insights, search
    }
}

// MARK: - Search configuration passed to HomeSearchView

struct SearchConfig: Identifiable, Equatable {
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
