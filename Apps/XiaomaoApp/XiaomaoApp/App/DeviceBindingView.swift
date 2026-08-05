import SwiftUI

struct DeviceBindingView: View {
    @State private var token = ""
    @State private var apiBaseURL = ""
    @State private var voiceWebSocketURL = ""
    @State private var deviceIDInput = ""
    @State private var errorMessage = ""
    let deviceID: String
    let configurationReady: Bool
    let configurationMessage: String
    let tokenStore: AuthTokenStoring
    let runtimeConfigurationStore: any RuntimeConfigurationStoring
    let completed: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 52))
            Text("绑定这台设备").font(.title2.bold())
            Text(configurationReady
                 ? (deviceID.isEmpty ? "设备 ID 尚未配置" : "设备 ID 已由服务端预分配")
                 : configurationMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("Backend HTTPS URL", text: $apiBaseURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
            TextField("Voice WSS URL", text: $voiceWebSocketURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
            SecureField("设备 ID", text: $deviceIDInput)
                .textContentType(.none)
                .textFieldStyle(.roundedBorder)
            SecureField("访问 Token", text: $token)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button("保存并继续") {
                saveConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.isEmpty || apiBaseURL.isEmpty || voiceWebSocketURL.isEmpty || deviceIDInput.isEmpty)
        }
        .padding(32)
        .onAppear {
            deviceIDInput = deviceID
        }
    }

    private func saveConfiguration() {
        let trimmedAPI = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVoice = voiceWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDeviceID = deviceIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiURL = URL(string: trimmedAPI), apiURL.scheme?.lowercased() == "https",
              let voiceURL = URL(string: trimmedVoice), voiceURL.scheme?.lowercased() == "wss",
              !trimmedDeviceID.isEmpty else {
            errorMessage = "请输入有效的 HTTPS、WSS 和设备 ID。"
            return
        }
        do {
            try runtimeConfigurationStore.save(RuntimeConfiguration(
                apiBaseURL: apiURL,
                voiceWebSocketURL: voiceURL,
                deviceID: trimmedDeviceID
            ))
            try tokenStore.save(token)
            token = ""
            errorMessage = ""
            completed()
        } catch {
            errorMessage = "安全配置保存失败，请重试。"
        }
    }
}
