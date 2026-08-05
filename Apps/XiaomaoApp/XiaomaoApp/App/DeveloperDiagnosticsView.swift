#if DEBUG
import SwiftUI

struct DeveloperDiagnosticsSnapshot: Equatable, Sendable {
    let backendStatus: String
    let voiceStatus: String
    let credentialStatus: String
    let deviceStatus: String
    let mockStatus: String
    let launchRouteStatus: String
    let backendAdapterStatus: String
    let voiceAdapterStatus: String
    let environmentStatus: String
    let buildSHA: String
    let buildTime: String

    static func make(
        environment: AppEnvironment,
        hasCredentials: Bool,
        hasBoundDevice: Bool,
        launchRoute: AppCoordinator.LaunchRoute
    ) -> DeveloperDiagnosticsSnapshot {
        DeveloperDiagnosticsSnapshot(
            backendStatus: environment.isBackendConfigurationReady ? "Configured" : "Not Configured",
            voiceStatus: environment.isVoiceConfigurationReady ? "Configured" : "Not Configured",
            credentialStatus: hasCredentials ? "Valid" : "Missing",
            deviceStatus: hasBoundDevice ? "Bound" : "Unbound",
            mockStatus: environment.enableMockVoice ? "Enabled" : "Disabled",
            launchRouteStatus: launchRoute.diagnosticLabel,
            backendAdapterStatus: environment.hostAdapters.mode.diagnosticLabel,
            voiceAdapterStatus: environment.hostAdapters.mode.diagnosticLabel,
            environmentStatus: environment.appEnvironment.isEmpty ? "Unspecified" : environment.appEnvironment,
            buildSHA: environment.appBuildSHA.isEmpty ? "Unknown" : environment.appBuildSHA,
            buildTime: environment.appBuildTime.isEmpty ? "Unknown" : environment.appBuildTime
        )
    }

}

private extension AppCoordinator.LaunchRoute {
    var diagnosticLabel: String {
        switch self {
        case .configurationError: "Configuration Error"
        case .binding: "Binding"
        case .home: "Home"
        }
    }
}

struct DeveloperDiagnosticsView: View {
    let snapshot: DeveloperDiagnosticsSnapshot

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    row("Environment", snapshot.environmentStatus)
                    row("Mock", snapshot.mockStatus)
                    row("Launch Route", snapshot.launchRouteStatus)
                }
                Section("Configuration") {
                    row("Backend", snapshot.backendStatus)
                    row("Voice", snapshot.voiceStatus)
                    row("Credential", snapshot.credentialStatus)
                    row("Device", snapshot.deviceStatus)
                }
                Section("Host Adapters") {
                    row("Backend Adapter", snapshot.backendAdapterStatus)
                    row("Voice Adapter", snapshot.voiceAdapterStatus)
                }
                Section("Build") {
                    row("Git SHA", snapshot.buildSHA)
                    row("Build Time", snapshot.buildTime)
                }
                Section {
                    Text("This page never displays endpoints, tokens, full device identifiers, chat content, audio, or provider credentials.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Developer Diagnostics")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
#endif
