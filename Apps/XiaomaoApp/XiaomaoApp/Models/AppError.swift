import Foundation

enum AppError: LocalizedError, Equatable {
    case configuration(String)
    case unauthorized
    case networkUnavailable
    case protocolError(String)
    case audio(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .configuration: return "配置不完整"
        case .unauthorized: return "设备尚未绑定或授权已失效"
        case .networkUnavailable: return "网络不可用"
        case .protocolError: return "语音协议错误"
        case .audio: return "音频设备异常"
        case .server: return "服务暂时不可用"
        }
    }
}
