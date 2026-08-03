#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

/// Token entry page for private live mode.
///
/// The token is written only to the injected DVKTokenStoring (Keychain on
/// Apple platforms). It is never stored in UserDefaults, Info.plist, or logs,
/// and it is never rendered back into the text field.
@MainActor
public struct DVKDeviceBindingView: View {
    public static let accessibilityID = "companion.deviceBinding"
    public static let inputAccessibilityID = "companion.deviceBinding.input"
    public static let saveAccessibilityID = "companion.deviceBinding.save"
    public static let statusAccessibilityID = "companion.deviceBinding.status"
    public static let clearAccessibilityID = "companion.deviceBinding.clear"

    public let configuration: DVKRuntimeConfiguration
    public let tokenStore: any DVKTokenStoring
    public let completed: () -> Void

    @State private var token = ""
    @State private var saved = false

    public init(
        configuration: DVKRuntimeConfiguration,
        tokenStore: any DVKTokenStoring,
        completed: @escaping () -> Void = {}
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.completed = completed
    }

    public var body: some View {
        let theme = DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile)
        VStack(spacing: 20) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 52))
                .foregroundStyle(theme.primaryAction)
            Text("Device binding")
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)
            statusText(theme: theme)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(Self.statusAccessibilityID)
            SecureField("Device token", text: $token)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .autocorrectionDisabled()
                .disabled(!configuration.isLive)
                .accessibilityIdentifier(Self.inputAccessibilityID)
            VStack(spacing: 10) {
                Button("Save and continue") {
                    guard configuration.isLive, !token.isEmpty else { return }
                    try? tokenStore.save(token)
                    token = ""
                    saved = true
                    completed()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primaryAction)
                .disabled(!configuration.isLive || token.isEmpty)
                .accessibilityIdentifier(Self.saveAccessibilityID)

                Button("Clear saved token") {
                    try? tokenStore.clear()
                    saved = false
                }
                .buttonStyle(.bordered)
                .foregroundStyle(theme.textPrimary)
                .accessibilityIdentifier(Self.clearAccessibilityID)
            }
            Text(helperText)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DVKBackgroundMeshView(mode: .call, theme: theme).ignoresSafeArea())
        .accessibilityIdentifier(Self.accessibilityID)
    }

    private var helperText: String {
        saved
            ? "Token saved to the secure store for this installation."
            : "The token stays in the secure store and is never logged or committed."
    }

    @ViewBuilder
    private func statusText(theme: DVKCompanionTheme) -> some View {
        switch configuration.mode {
        case .mock:
            Text("Public demo mode: no token is needed. Configure a live build to enable device binding.")
        case .live:
            Text(configuration.deviceID.isEmpty
                 ? "Device identifier is not configured."
                 : "Device identifier is configured. Enter the private token to connect.")
        case .misconfigured:
            Text("Partial configuration detected. Network access stays disabled until all three values are present.")
        }
    }
}
#endif
