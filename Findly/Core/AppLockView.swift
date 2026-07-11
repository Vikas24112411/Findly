import SwiftUI
import LocalAuthentication

struct AppLockView: View {

    var onUnlock: () async -> Void

    @State private var isUnlocking = false

    private var biometrySymbol: String {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return "lock.fill"
        }
        return ctx.biometryType == .faceID ? "faceid" : "touchid"
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.groupedBG.ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.xLarge) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)

                VStack(spacing: AppTheme.Spacing.small) {
                    Text("Findly is Locked")
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(AppTheme.Colors.label)
                    Text("Authenticate to access your vault.")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    guard !isUnlocking else { return }
                    isUnlocking = true
                    Task {
                        await onUnlock()
                        isUnlocking = false
                    }
                } label: {
                    Label("Unlock with \(biometrySymbol == "faceid" ? "Face ID" : biometrySymbol == "touchid" ? "Touch ID" : "Passcode")",
                          systemImage: biometrySymbol)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.medium)
                        .background(AppTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                        .font(AppTheme.Typography.headline)
                }
                .disabled(isUnlocking)
                .padding(.horizontal, AppTheme.Spacing.xLarge)
                .padding(.bottom, AppTheme.Spacing.xxxLarge)
            }
        }
    }
}
