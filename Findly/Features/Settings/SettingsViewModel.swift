import Foundation
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - Drive stats

    var driveUsedBytes: Int64 = 0
    var driveTotalBytes: Int64 = 0
    var isLoadingDriveStats: Bool = false

    // MARK: - Sync

    var autoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "autoSyncEnabled") }
    }

    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }

    // MARK: - Theme

    var selectedTheme: AppearanceMode {
        get {
            AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "system") ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appearanceMode")
        }
    }

    enum AppearanceMode: String, CaseIterable {
        case light  = "light"
        case dark   = "dark"
        case system = "system"

        var displayName: String {
            switch self {
            case .light:  return "Light"
            case .dark:   return "Dark"
            case .system: return "System"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .light:  return .light
            case .dark:   return .dark
            case .system: return nil
            }
        }
    }

    // MARK: - Local storage

    var localStorageSize: Int64 = 0
    var isMigratingStorage = false
    var storageMigrationError: String?

    func loadLocalStorageSize(appContainer: AppContainer) async {
        localStorageSize = await appContainer.localStorage.sizeOfLocalStorage()
    }

    /// Copies all files to the new location and updates the stored preference.
    func migrateStorage(
        to location: StorageLocationService.Location,
        customURL: URL? = nil,
        appContainer: AppContainer
    ) async {
        isMigratingStorage = true
        defer { isMigratingStorage = false }

        do {
            guard let newBaseDir = StorageLocationService.shared.baseDirectory(for: location, customURL: customURL) else {
                throw StorageLocationError.missingCustomURL
            }
            let oldDir = try await appContainer.localStorage.migrateToDirectory(newBaseDir)
            try StorageLocationService.shared.setLocation(location, customURL: customURL)
            try? FileManager.default.removeItem(at: oldDir)
            await loadLocalStorageSize(appContainer: appContainer)
        } catch {
            storageMigrationError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func loadDriveStats(appContainer: AppContainer) async {
        guard appContainer.auth.isAuthenticated else { return }
        isLoadingDriveStats = true
        defer { isLoadingDriveStats = false }
        do {
            let (used, total) = try await appContainer.drive.storageQuota()
            driveUsedBytes  = used
            driveTotalBytes = total
        } catch {
            // Non-critical — just don't show stats
        }
    }

    func manualSync(appContainer: AppContainer) async {
        await appContainer.sync.syncPendingItems()
        UserDefaults.standard.set(Date(), forKey: "lastSyncDate")
    }
}
