import SwiftUI

struct DeviceBindingView: View {
    @State private var token = ""
    let deviceID: String
    let configurationReady: Bool
    let configurationMessage: String
    let tokenStore: AuthTokenStoring
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
            SecureField("开发 Token", text: $token)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .disabled(!configurationReady)
            Button("保存并继续") {
                guard configurationReady, !token.isEmpty else { return }
                try? tokenStore.save(token)
                token = ""
                completed()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!configurationReady || token.isEmpty)
        }
        .padding(32)
    }
}
