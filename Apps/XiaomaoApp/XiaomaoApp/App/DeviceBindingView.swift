import SwiftUI

struct DeviceBindingView: View {
    @State private var connectionBundle = ""
    @State private var token = ""
    @State private var apiBaseURL = ""
    @State private var voiceWebSocketURL = ""
    @State private var deviceIDInput = ""
    @State private var errorMessage = ""
    @State private var hasStoredToken = false
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
            SecureField("一键配置串（XM1…）", text: $connectionBundle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
            Button("导入并继续") {
                WarmHaptics.action()
                importBundleAndSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(connectionBundle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("一次粘贴即可导入 Backend、Voice、设备 ID 和 Token。配置串按密钥处理，不会显示其中内容。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider()
            Text("或手动填写")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
            SecureField(hasStoredToken ? "访问 Token（留空则保留现有）" : "访问 Token", text: $token)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button("保存并继续") {
                WarmHaptics.action()
                saveConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .disabled((token.isEmpty && !hasStoredToken) || apiBaseURL.isEmpty || voiceWebSocketURL.isEmpty || deviceIDInput.isEmpty)
        }
        .padding(32)
        .onAppear {
            if let existing = runtimeConfigurationStore.load() {
                apiBaseURL = existing.apiBaseURL.absoluteString
                voiceWebSocketURL = existing.voiceWebSocketURL.absoluteString
                deviceIDInput = existing.deviceID
            } else {
                deviceIDInput = deviceID
            }
            hasStoredToken = !RuntimeCredentialNormalizer
                .token(tokenStore.load() ?? "")
                .isEmpty
        }
    }

    private func importBundleAndSave() {
        do {
            let bundle = try RuntimeConnectionBundle.decode(connectionBundle)
            apiBaseURL = bundle.configuration.apiBaseURL.absoluteString
            voiceWebSocketURL = bundle.configuration.voiceWebSocketURL.absoluteString
            deviceIDInput = bundle.configuration.deviceID
            token = bundle.token
            errorMessage = ""
            saveConfiguration()
            connectionBundle = ""
        } catch {
            token = ""
            errorMessage = "配置串无效，请重新复制完整的 XM1 配置串。"
        }
    }

    private func saveConfiguration() {
        let trimmedAPI = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVoice = voiceWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDeviceID = RuntimeCredentialNormalizer.deviceID(deviceIDInput)
        guard let apiURL = URL(string: trimmedAPI), apiURL.scheme?.lowercased() == "https",
              let voiceURL = URL(string: trimmedVoice), voiceURL.scheme?.lowercased() == "wss",
              !trimmedDeviceID.isEmpty else {
            errorMessage = "请输入有效的 HTTPS、WSS 和设备 ID。"
            return
        }
        let normalizedToken = RuntimeCredentialNormalizer.token(token)
        guard hasStoredToken || !normalizedToken.isEmpty else {
            errorMessage = "请输入有效的访问 Token。"
            return
        }
        do {
            try runtimeConfigurationStore.save(RuntimeConfiguration(
                apiBaseURL: apiURL,
                voiceWebSocketURL: voiceURL,
                deviceID: trimmedDeviceID
            ))
            if !normalizedToken.isEmpty {
                try tokenStore.save(normalizedToken)
            }
            token = ""
            errorMessage = ""
            completed()
        } catch {
            errorMessage = "安全配置保存失败，请重试。"
        }
    }

}
