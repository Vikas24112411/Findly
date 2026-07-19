import SwiftUI
import GoogleSignIn

@main
struct FindlyApp: App {

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
                    .modelContainer(appContainer.persistence.container)
                    .tint(AppTheme.Colors.accent)
                    .onOpenURL { url in
                        // Required for Google Sign-In callback
                        GIDSignIn.sharedInstance.handle(url)
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
