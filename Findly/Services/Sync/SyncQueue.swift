import Foundation

/// Actor-isolated set of item IDs currently in-flight (being uploaded).
///
/// Prevents duplicate concurrent uploads of the same item when
/// `syncPendingItems()` is called from both foreground and BGProcessingTask.
actor SyncQueue {

    private var inFlight: Set<UUID> = []

    /// Attempts to claim an item for upload.
    /// Returns `true` if the claim succeeded (item was not already in-flight).
    func claim(_ itemID: UUID) -> Bool {
        guard !inFlight.contains(itemID) else { return false }
        inFlight.insert(itemID)
        return true
    }

    /// Releases a claimed item after upload completes (success or failure).
    func release(_ itemID: UUID) {
        inFlight.remove(itemID)
    }

    var inFlightCount: Int { inFlight.count }
}
