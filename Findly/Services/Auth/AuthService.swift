import Foundation
import GoogleSignIn
import GoogleSignInSwift

// MARK: - Errors

enum AuthError: LocalizedError {
    case notSignedIn
    case tokenUnavailable
    case signInFailed(Error)
    case noViewController

    var errorDescription: String? {
        switch self {
        case .notSignedIn:          return "You are not signed in. Please sign in with Google."
        case .tokenUnavailable:     return "Could not retrieve a valid access token."
        case .signInFailed(let e):  return "Sign-in failed: \(e.localizedDescription)"
        case .noViewController:     return "Could not find a view controller to present sign-in."
        }
    }
}

// MARK: - AuthService

/// Wraps `GIDSignIn` to provide a clean async API for the rest of the app.
///
/// **Setup:** Before calling any method, add your Google client ID:
/// ```swift
/// AuthService.configure(clientID: "YOUR_CLIENT_ID")
/// ```
/// This is called from `FindlyApp.init()` once credentials are available.
@Observable
@MainActor
final class AuthService {

    // MARK: - State

    private(set) var currentUser: GIDGoogleUser?

    var isAuthenticated: Bool { currentUser != nil }
    var userEmail: String?    { currentUser?.profile?.email }
    var userName: String?     { currentUser?.profile?.name }
    var userAvatarURL: URL?   { currentUser?.profile?.imageURL(withDimension: 96) }

    // MARK: - Configuration

    static func configure(clientID: String) {
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
    }

    // MARK: - Session restoration

    func restorePreviousSignIn() async {
        do {
            currentUser = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        } catch {
            // No previous session — not an error, just unauthenticated.
            currentUser = nil
        }
    }

    // MARK: - Sign-in

    func signIn() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.keyWindow?.rootViewController
        else {
            throw AuthError.noViewController
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: rootVC,
                hint: nil,
                additionalScopes: [
                    "https://www.googleapis.com/auth/drive.file"
                ]
            )
            currentUser = result.user
        } catch {
            throw AuthError.signInFailed(error)
        }
    }

    // MARK: - Sign-out

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
    }

    // MARK: - Token management

    /// Returns a fresh, non-expired OAuth access token.
    /// The GoogleSignIn SDK serializes concurrent refresh requests — multiple
    /// callers will share a single in-flight refresh, not trigger parallel ones.
    func freshAccessToken() async throws -> String {
        guard let user = currentUser else { throw AuthError.notSignedIn }
        try await user.refreshTokensIfNeeded()
        return user.accessToken.tokenString
    }
}
