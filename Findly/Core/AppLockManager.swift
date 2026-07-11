import Foundation
import LocalAuthentication

@Observable
@MainActor
final class AppLockManager {

    var isLocked: Bool = false

    func lock() {
        isLocked = true
    }

    /// Prompts the user for biometrics or passcode.
    /// Returns `true` on success (also sets `isLocked = false`).
    @discardableResult
    func unlock() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics or passcode configured — just unlock.
            isLocked = false
            return true
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Findly"
            )
            if success { isLocked = false }
            return success
        } catch {
            return false
        }
    }
}
