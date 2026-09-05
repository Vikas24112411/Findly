import Foundation

/// The single registration point for experimental features.
///
/// To add a new experiment, append an `ExperimentalFeature` with a stable,
/// unique `id` and `defaultValue: false`. The Settings UI, persistence, and
/// enabled-count summary pick it up automatically — no other registration
/// step is needed.
///
/// Lifecycle rules:
/// - Brand-new experiments default off and appear immediately in Settings.
/// - An existing feature moved behind a flag keeps whatever default
///   preserves its current behavior; document the choice on the entry.
/// - Graduated features stop consulting the flag at their call site instead
///   of being removed from user devices; the persisted value is then inert.
/// - Removed IDs are ignored safely (see `ExperimentalFeatureStore`).
enum ExperimentalFeatureCatalog {
    /// All experiments offered in Settings, in display order.
    static var all: [ExperimentalFeature] { [needsAttention] }

    /// The Insights "Needs Attention" hygiene to-do list (untagged,
    /// never-opened, and stale files). An existing feature moved behind a
    /// flag: it defaults off per the experiment opt-in decision, so the
    /// card is hidden until enabled under Settings → Advanced. When the
    /// flag is on, the card additionally honors the "Needs Attention"
    /// toggle in Settings → Insights, which itself is only shown while
    /// this experiment is enabled.
    static let needsAttention = ExperimentalFeature(
        id: "needs-attention",
        name: "Needs Attention",
        description: "Shows the Needs Attention card on the Insights overview, highlighting untagged files, files never opened, and files not opened in over 90 days."
    )
}
