import SwiftUI

/// Settings summary text for the Experimental Features row.
///
/// - `0` enabled → `"Off"`, otherwise `"1 enabled"` / `"N enabled"`.
enum ExperimentalFeaturesSummary {
    static func text(enabledCount: Int) -> String {
        enabledCount == 0 ? "Off" : "\(enabledCount) enabled"
    }
}

/// Destination for the Settings → Advanced → Experimental Features row.
///
/// A native `Form` with one descriptive toggle per registered experiment.
/// Shows a `ContentUnavailableView` while the catalog is empty so the
/// capability stays discoverable before the first experiment lands.
/// Toggles are reversible and confirmation-free; the store performs no side
/// effects, and each consuming feature owns its own disable-time cleanup.
struct ExperimentalFeaturesView: View {
    @Environment(ExperimentalFeatureStore.self) private var store

    var body: some View {
        Group {
            if store.allFeatures.isEmpty {
                ContentUnavailableView {
                    Label("No Experimental Features", systemImage: "flask")
                } description: {
                    Text("There are no experiments available right now. Check back in a future update.")
                }
            } else {
                Form {
                    Section {
                        ForEach(store.allFeatures) { feature in
                            Toggle(isOn: Binding(
                                get: { store.isEnabled(feature) },
                                set: { store.setEnabled($0, for: feature) }
                            )) {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                                    Text(feature.name)
                                        .foregroundStyle(AppTheme.Colors.label)
                                    Text(feature.description)
                                        .font(AppTheme.Typography.subheadline)
                                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, AppTheme.Spacing.xxSmall)
                            }
                        }
                    } footer: {
                        Text("Experimental features may change, malfunction, or disappear without notice.")
                    }

                    if store.enabledCount > 0 {
                        Section {
                            Button("Turn Off All Experimental Features", role: .destructive) {
                                store.disableAll()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Experimental Features")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Experimental - Empty") {
    NavigationStack {
        ExperimentalFeaturesView()
    }
    .environment(ExperimentalFeatureStore())
}

#Preview("Experimental - Empty, Dark, Large Text") {
    NavigationStack {
        ExperimentalFeaturesView()
    }
    .environment(ExperimentalFeatureStore())
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}
