import Foundation

/// The single registration point for experimental features.
///
/// To add a new experiment, append an `ExperimentalFeature` with a stable,
/// unique `id` and `defaultValue: false`. The Settings UI, persistence, and
/// enabled-count summary pick it up automatically — no other registration
/// step is needed.
///
/// Lifecycle rules:
/// - New experiments default off and appear immediately in Settings.
/// - Graduated features stop consulting the flag at their call site instead
///   of being removed from user devices; the persisted value is then inert.
/// - Removed IDs are ignored safely (see `ExperimentalFeatureStore`).
///
/// The first release ships an empty catalog on purpose: it provides the
/// framework and empty-state UI without introducing a sample experiment.
enum ExperimentalFeatureCatalog {
    /// All experiments offered in Settings, in display order. Empty until
    /// the first real experiment lands.
    static var all: [ExperimentalFeature] { [] }
}
