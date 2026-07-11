import Foundation

/// Proactively refreshes the Google access token before it expires,
/// so there is no latency penalty on the first Drive API call after a long idle period.
///
/// Start with `TokenRefresher.shared.start(authService:)` from `AppContainer`.
final class TokenRefresher: @unchecked Sendable {

    static let shared = TokenRefresher()

    private var task: Task<Void, Never>?

    private init() {}

    func start(authService: AuthService) {
        task?.cancel()
        task = Task {
            // Refresh every 45 minutes (tokens expire after 60 minutes).
            let interval: TimeInterval = 45 * 60
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                _ = try? await authService.freshAccessToken()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
