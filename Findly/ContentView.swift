import SwiftUI

/// Root view: TabView with four tabs + persistent floating action button.
struct ContentView: View {

    @Environment(AppContainer.self) private var appContainer
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var selectedTab: Tab = .home
    @State private var showAddSheet = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(Tab.home)

                KnowledgeView()
                    .tabItem { Label("Knowledge", systemImage: "tag.fill") }
                    .tag(Tab.knowledge)

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
        .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil)
    }
}

// MARK: - Tab enum

extension ContentView {
    enum Tab: Hashable {
        case home, knowledge, insights, settings
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(AppContainer())
        .modelContainer(PersistenceController.preview.container)
}
