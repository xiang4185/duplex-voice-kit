import Foundation

enum VoiceWebSocketState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case failed
}

struct VoiceWebSocketDisconnectInfo: Error, Equatable, Sendable {
    let closeCode: Int?
    let recoverable: Bool
    let errorCategory: String
    let reasonCategory: String
}

enum VoiceWebSocketLifecycleEvent: Equatable, Sendable {
    case connecting
    case connected
    case disconnected(VoiceWebSocketDisconnectInfo)
    case failed(VoiceWebSocketDisconnectInfo)
}

enum VoiceWebSocketErrorClassifier {
    static func classify(
        error: Error?,
        closeCode: Int?,
        httpStatus: Int? = nil,
        intentional: Bool = false
    ) -> VoiceWebSocketDisconnectInfo {
        if intentional {
            return VoiceWebSocketDisconnectInfo(
                closeCode: closeCode,
                recoverable: false,
                errorCategory: "cancelled",
                reasonCategory: "client_closed"
            )
        }
        if httpStatus == 401 || httpStatus == 403 {
            return VoiceWebSocketDisconnectInfo(
                closeCode: closeCode,
                recoverable: false,
                errorCategory: "unauthorized",
                reasonCategory: "http_unauthorized"
            )
        }
        if closeCode == 1006 {
            return VoiceWebSocketDisconnectInfo(
                closeCode: closeCode,
                recoverable: true,
                errorCategory: "connection_lost",
                reasonCategory: "abnormal_close"
            )
        }
        if let closeCode, closeCode == 1000 || closeCode == 1001 {
            return VoiceWebSocketDisconnectInfo(
                closeCode: closeCode,
                recoverable: false,
                errorCategory: "server_closed",
                reasonCategory: "normal_close"
            )
        }
        guard let error else {
            return VoiceWebSocketDisconnectInfo(
                closeCode: closeCode,
                recoverable: true,
                errorCategory: "connection_lost",
                reasonCategory: "transport_closed"
            )
        }
        if error is DecodingError {
            return VoiceWebSocketDisconnectInfo(
                closeCode: closeCode,
                recoverable: false,
                errorCategory: "protocol_error",
                reasonCategory: "invalid_server_event"
            )
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorUserAuthenticationRequired:
                return info(closeCode, false, "unauthorized", "authentication_required")
            case NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorSecureConnectionFailed,
                 NSURLErrorClientCertificateRejected:
                return info(closeCode, false, "tls_failed", "certificate_or_tls")
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return info(closeCode, true, "network_unavailable", "network_transport")
            case NSURLErrorTimedOut:
                return info(closeCode, true, "timed_out", "transport_timeout")
            case NSURLErrorCancelled:
                return info(closeCode, false, "cancelled", "request_cancelled")
            case NSURLErrorBadServerResponse:
                return info(closeCode, httpStatus == nil, httpStatus == nil ? "protocol_error" : "server_closed", "bad_server_response")
            default:
                break
            }
        }
        return info(closeCode, true, "unknown", "unclassified_transport_error")
    }

    private static func info(
        _ closeCode: Int?,
        _ recoverable: Bool,
        _ errorCategory: String,
        _ reasonCategory: String
    ) -> VoiceWebSocketDisconnectInfo {
        VoiceWebSocketDisconnectInfo(
            closeCode: closeCode,
            recoverable: recoverable,
            errorCategory: errorCategory,
            reasonCategory: reasonCategory
        )
    }
}
