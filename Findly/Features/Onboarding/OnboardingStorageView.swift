import SwiftUI
import UniformTypeIdentifiers

/// First-launch screen that lets the user choose where Findly stores files.
/// Shown as a `.fullScreenCover` until `hasCompletedOnboarding` is set to `true`.
struct OnboardingStorageView: View {

    @Environment(AppContainer.self) private var appContainer
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var selectedLocation: StorageLocationService.Location = .appPrivate
    @State private var customURL: URL?
    @State private var showFolderPicker = false
    @State private var isSettingUp = false
    @State private var setupError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                    .padding(.top, AppTheme.Spacing.xxLarge)

                Spacer().frame(height: AppTheme.Spacing.xxLarge)

                optionCards
                    .padding(.horizontal, AppTheme.Spacing.large)

                Spacer()

                getStartedButton
                    .padding(.horizontal, AppTheme.Spacing.large)
                    .padding(.bottom, AppTheme.Spacing.xxLarge)
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderPicked(result)
        }
        .alert("Setup Failed", isPresented: Binding(
            get: { setupError != nil },
            set: { if !$0 { setupError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(setupError ?? "")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.Colors.accent)

            Text("Where should Findly\nstore your files?")
                .font(AppTheme.Typography.largeTitle)
                .multilineTextAlignment(.center)

            Text("You can change this anytime in Settings.")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.Spacing.large)
    }

    // MARK: - Option cards

    private var optionCards: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ForEach(StorageLocationService.Location.allCases, id: \.self) { location in
                locationCard(for: location)
            }
        }
    }

    private func locationCard(for location: StorageLocationService.Location) -> some View {
        let isSelected = selectedLocation == location
        let isCustomWithURL = location == .custom && customURL != nil

        return Button {
            if location == .custom {
                selectedLocation = .custom
                showFolderPicker = true
            } else {
                selectedLocation = location
                customURL = nil
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: location.sfSymbol)
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.secondaryLabel)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(location.displayName)
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(AppTheme.Colors.label)
                        if isCustomWithURL, let name = customURL?.lastPathComponent {
                            Text("→ \(name)")
                                .font(AppTheme.Typography.caption1)
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                    Text(location.description)
                        .font(AppTheme.Typography.caption1)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.secondaryLabel)
            }
            .padding(AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                    .fill(isSelected
                          ? AppTheme.Colors.accent.opacity(0.08)
                          : Color(.secondarySystemBackground))
                    .strokeBorder(
                        isSelected ? AppTheme.Colors.accent : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Get Started button

    private var getStartedButton: some View {
        Button {
            if selectedLocation == .custom && customURL == nil {
                showFolderPicker = true
            } else {
                Task { await completeOnboarding() }
            }
        } label: {
            ZStack {
                Text("Get Started")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.white)
                    .opacity(isSettingUp ? 0 : 1)

                if isSettingUp {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.medium)
            .background(AppTheme.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        }
        .disabled(isSettingUp)
    }

    // MARK: - Actions

    private func handleFolderPicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            customURL = url
        case .failure(let error):
            setupError = error.localizedDescription
            selectedLocation = .appPrivate
        }
    }

    private func completeOnboarding() async {
        isSettingUp = true
        defer { isSettingUp = false }

        do {
            if selectedLocation == .appPrivate {
                // Default — no action needed; AppContainer already initialized to appPrivate.
                StorageLocationService.shared.currentLocation = .appPrivate
            } else if selectedLocation == .custom, let url = customURL {
                try StorageLocationService.shared.setLocation(.custom, customURL: url)
                let newDir = url
                try await appContainer.localStorage.updateBaseDirectory(newDir)
            }
            hasCompletedOnboarding = true
            HapticFeedback.success()
        } catch {
            setupError = error.localizedDescription
            HapticFeedback.error()
        }
    }
}

#Preview {
    OnboardingStorageView()
        .environment(AppContainer())
}
