import Foundation

/// A single unstable feature that users can opt into.
///
/// - `id` is the stable persistence identifier. It must never be reused for a
///   different feature: rename the display `name` freely, but treat `id` as
///   permanent. When a feature graduates, stop consulting the flag at the call
///   site (leave any persisted value untouched — it is ignored). When a
///   feature is removed, delete its catalog entry; leftover persisted values
///   for unknown IDs are ignored safely by `ExperimentalFeatureStore`.
/// - `defaultValue` is the value used when no preference exists. New
///   experiments must default to `false` (disabled).
struct ExperimentalFeature: Identifiable, Hashable, Sendable {
    /// Stable persistence identifier, e.g. `"smart-suggestions"`.
    let id: String
    /// User-facing title shown next to the toggle.
    let name: String
    /// One- or two-sentence explanation shown under the title.
    let description: String
    /// Value used when the user has never set a preference. Always `false`
    /// for new experiments.
    let defaultValue: Bool

    init(
        id: String,
        name: String,
        description: String,
        defaultValue: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.defaultValue = defaultValue
    }
}
