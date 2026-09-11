import SwiftUI
import GoogleSignIn

@main
struct FindlyApp: App {

    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var appContainer: AppContainer? = nil
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Google Sign-In Client ID
    // Replace with your actual Client ID from GoogleService-Info.plist
    // after setting up a Google Cloud project.
    private let googleClientID = "REPLACE_WITH_YOUR_CLIENT_ID"

    init() {
        AuthService.configure(clientID: googleClientID)
    }

    var body: some Scene {
        WindowGroup {
            if let appContainer {
                ContentView()
                    .environment(appContainer)
                    .environment(appContainer.experimentalFeatures)
                    .modelContainer(appContainer.persistence.container)
                    .tint(AppTheme.Colors.accent)
                    .task {
                        await appContainer.publishShareCatalog()
                        appContainer.onAppBecomeActive()
                    }
                    .onChange(of: appLockEnabled) { _, enabled in
                        UserDefaults(suiteName: ShareInbox.groupID)?.set(enabled, forKey: "appLockEnabled")
                        Task { await appContainer.publishShareCatalog() }
                    }
                    .onChange(of: hasCompletedOnboarding) { _, completed in
                        if completed { Task { await appContainer.receiveSharedFiles() } }
                    }
                    .alert("Shared File Pending", isPresented: Binding(
                        get: { appContainer.shareImportError != nil },
                        set: { if !$0 { appContainer.shareImportError = nil } }
                    )) {
                        Button("Retry") { Task { await appContainer.receiveSharedFiles() } }
                        Button("Later", role: .cancel) { appContainer.shareImportError = nil }
                    } message: {
                        Text(appContainer.shareImportError ?? "")
                    }
                    .onOpenURL { url in
                        // Required for Google Sign-In callback
                        GIDSignIn.sharedInstance.handle(url)
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: UIApplication.significantTimeChangeNotification
                    )) { _ in
                        appContainer.onSignificantTimeChange()
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: NSNotification.Name.NSSystemTimeZoneDidChange
                    )) { _ in
                        appContainer.onSignificantTimeChange()
                    }
            } else {
                Color(UIColor.systemBackground)
                    .task { appContainer = await AppContainer.makeAsync() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard let appContainer else { return }
            switch newPhase {
            case .active:
                appContainer.onAppBecomeActive()
            case .background:
                appContainer.onAppBackground()
            default:
                break
            }
        }
    }
}
