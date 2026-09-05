import Foundation
import Observation

/// App-wide observable state for experimental feature flags.
///
/// Backed by an injectable `UserDefaults` (`.standard` in production, an
/// isolated suite in tests/previews). Choices are local to this device and
/// are never synced through Google Drive. Writes apply immediately and every
/// mutation publishes through `@Observable`, so SwiftUI views gating on the
/// injected store re-render without relaunch.
///
/// The store performs no side effects: toggling a flag only persists the
/// boolean. Each consuming feature owns any cleanup required when its flag
/// is turned off (including via `disableAll()`).
///
/// Only catalog features are ever read. Persisted values for unknown or
/// removed IDs are never consulted, so deleting a catalog entry is safe.
@Observable
@MainActor
final class ExperimentalFeatureStore {

    /// Key prefix for persisted flags. The full key is
    /// `"experimentalFeatures.<feature-id>"`.
    nonisolated static let keyPrefix = "experimentalFeatures."

    private let defaults: UserDefaults
    private let features: [ExperimentalFeature]

    /// Creates a store over `features` (default: the shared catalog).
    ///
    /// - Parameters:
    ///   - defaults: persistence backing. Defaults to `.standard`.
    ///   - features: the registered experiments this instance manages.
    ///     Defaults to `ExperimentalFeatureCatalog.all`; tests pass fixtures.
    init(
        defaults: UserDefaults = .standard,
        features: [ExperimentalFeature] = ExperimentalFeatureCatalog.all
    ) {
        self.defaults = defaults
        self.features = features
    }

    // MARK: - Catalog

    /// The registered experiments, in display order.
    var allFeatures: [ExperimentalFeature] { features }

    /// Number of registered experiments currently enabled.
    var enabledCount: Int {
        features.filter { isEnabled($0) }.count
    }

    // MARK: - Flags

    /// Whether `feature` is enabled. Returns `feature.defaultValue`
    /// (normally `false`) when no preference has been stored.
    func isEnabled(_ feature: ExperimentalFeature) -> Bool {
        isEnabled(id: feature.id, defaultValue: feature.defaultValue)
    }

    /// ID-based lookup for call sites holding only a stable identifier.
    /// Unknown IDs (graduated or removed features) resolve to `defaultValue`
    /// and never crash or affect app behavior.
    func isEnabled(id: String, defaultValue: Bool = false) -> Bool {
        guard features.contains(where: { $0.id == id }) else { return defaultValue }
        return storedValue(for: id) ?? defaultValue
    }

    /// Persists `enabled` for `feature`, effective immediately.
    func setEnabled(_ enabled: Bool, for feature: ExperimentalFeature) {
        defaults.set(enabled, forKey: Self.key(for: feature.id))
    }

    /// Turns off every registered experiment that is currently on.
    /// Reversible and confirmation-free; re-enabling is a plain toggle.
    func disableAll() {
        for feature in features where isEnabled(feature) {
            defaults.set(false, forKey: Self.key(for: feature.id))
        }
    }

    // MARK: - Private

    private func storedValue(for id: String) -> Bool? {
        defaults.object(forKey: Self.key(for: id)) as? Bool
    }

    nonisolated static func key(for id: String) -> String {
        keyPrefix + id
    }
}
