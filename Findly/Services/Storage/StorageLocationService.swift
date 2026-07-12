import Foundation

/// Manages where Findly stores its files on device.
///
/// Two options:
/// - `.appPrivate` (default) — `ApplicationSupport/Findly/files/`, hidden from Files app.
/// - `.custom` — any folder the user picked via a document picker, persisted as a
///   security-scoped bookmark in UserDefaults.
final class StorageLocationService {

    static let shared = StorageLocationService()

    // MARK: - Location type

    enum Location: String, CaseIterable {
        case appPrivate = "appPrivate"
        case custom     = "custom"

        var displayName: String {
            switch self {
            case .appPrivate: return "App Private"
            case .custom:     return "Custom Folder"
            }
        }

        var sfSymbol: String {
            switch self {
            case .appPrivate: return "lock.shield.fill"
            case .custom:     return "folder.fill"
            }
        }

        var description: String {
            switch self {
            case .appPrivate:
                return "Stored securely in the app's private container. Not accessible from the Files app."
            case .custom:
                return "You choose the folder. Accessible from any app that can see that location."
            }
        }
    }

    // MARK: - UserDefaults keys

    private enum Keys {
        static let location       = "storageLocation"
        static let customBookmark = "storageCustomBookmark"
    }

    // MARK: - Current location

    var currentLocation: Location {
        get {
            Location(rawValue: UserDefaults.standard.string(forKey: Keys.location) ?? "") ?? .appPrivate
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.location)
        }
    }

    // MARK: - Resolved base directory

    /// Returns the base directory URL for the current preference.
    /// Falls back to `.appPrivate` if the custom bookmark is stale or missing.
    var resolvedBaseDirectory: URL {
        switch currentLocation {
        case .appPrivate:
            return appPrivateBaseURL
        case .custom:
            guard let url = resolvedCustomURL else {
                // Bookmark gone — silently fall back
                currentLocation = .appPrivate
                return appPrivateBaseURL
            }
            return url
        }
    }

    // MARK: - Set location (commits to UserDefaults)

    /// Saves the new location preference.
    /// For `.custom`, creates a security-scoped bookmark from `customURL` and saves it.
    /// The caller must have already called `url.startAccessingSecurityScopedResource()`.
    func setLocation(_ location: Location, customURL: URL? = nil) throws {
        if location == .custom {
            guard let url = customURL else {
                throw StorageLocationError.missingCustomURL
            }
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Keys.customBookmark)
        } else {
            // Stop security-scoped access when switching away from custom storage.
            activeCustomURL?.stopAccessingSecurityScopedResource()
            activeCustomURL = nil
        }
        currentLocation = location
    }

    /// Computes the base directory for a given location + optional custom URL
    /// without committing anything to UserDefaults. Used by migration preview.
    func baseDirectory(for location: Location, customURL: URL? = nil) -> URL? {
        switch location {
        case .appPrivate:
            return appPrivateBaseURL
        case .custom:
            return customURL
        }
    }

    // MARK: - Custom folder display name

    /// Short folder name for display in Settings (e.g. "Photos" or the last path component).
    var customFolderDisplayName: String? {
        resolvedCustomURL?.lastPathComponent
    }

    // MARK: - Private helpers

    private var appPrivateBaseURL: URL {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            fatalError("Cannot resolve ApplicationSupportDirectory — OS-level failure")
        }
        return support.appending(components: "Findly", "files")
    }

    // Tracks the currently security-scoped URL so access can be stopped when switching locations.
    private var activeCustomURL: URL?

    private var resolvedCustomURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: Keys.customBookmark) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        // Start security-scoped access if not already active for this path.
        if activeCustomURL?.path != url.path {
            activeCustomURL?.stopAccessingSecurityScopedResource()
            _ = url.startAccessingSecurityScopedResource()
            activeCustomURL = url
        }

        if stale {
            let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(fresh, forKey: Keys.customBookmark)
        }
        return url
    }
}

// MARK: - Errors

enum StorageLocationError: LocalizedError {
    case missingCustomURL

    var errorDescription: String? {
        switch self {
        case .missingCustomURL:
            return "No folder was provided for the custom storage location."
        }
    }
}
