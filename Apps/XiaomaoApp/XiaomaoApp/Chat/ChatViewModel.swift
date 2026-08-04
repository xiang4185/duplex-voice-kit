import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    static let maximumMessageLength = 200

    @Published var draft = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var sessionID: String?
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var isSending = false
    @Published private(set) var isClearing = false
    @Published private(set) var hasLoadedHistory = false
    @Published private(set) var lastReplyWasDegraded = false
    @Published var errorMessage = ""

    private let service: (any ChatServicing)?
    private let requestIDGenerator: @Sendable () -> String
    private let configurationError: String?
    private var hasAttemptedHistoryLoad = false

    init(
        service: (any ChatServicing)?,
        configurationError: String? = nil,
        requestIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.service = service
        self.configurationError = configurationError
        self.requestIDGenerator = requestIDGenerator
        if service == nil {
            errorMessage = configurationError ?? "聊天服务配置不可用。"
        }
    }

    var isBusy: Bool {
        isLoadingHistory || isSending || isClearing
    }

    var isConfigurationAvailable: Bool {
        service != nil
    }

    var canRetryHistory: Bool {
        service != nil && !isBusy && !hasLoadedHistory
    }

    var canSend: Bool {
        let text = normalizedDraft
        return hasLoadedHistory
            && sessionID != nil
            && !text.isEmpty
            && text.count <= Self.maximumMessageLength
            && !isBusy
    }

    var canClear: Bool {
        hasLoadedHistory && sessionID != nil && !messages.isEmpty && !isBusy
    }

    var draftCharacterCount: Int {
        draft.count
    }

    func loadHistoryIfNeeded() async {
        guard !hasAttemptedHistoryLoad else { return }
        hasAttemptedHistoryLoad = true
        await loadHistory()
    }

    func loadHistory() async {
        guard !isBusy else { return }
        guard let service else {
            errorMessage = configurationError ?? "聊天服务配置不可用。"
            return
        }

        isLoadingHistory = true
        errorMessage = ""
        defer { isLoadingHistory = false }

        do {
            let result = try await service.loadHistory()
            guard !result.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ChatStateError.invalidServerSession
            }
            sessionID = result.sessionID
            messages = result.messages
            hasLoadedHistory = true
            lastReplyWasDegraded = false
        } catch {
            sessionID = nil
            hasLoadedHistory = false
            errorMessage = Self.userFacingMessage(for: error, action: "加载聊天记录")
        }
    }

    func send() async {
        let text = normalizedDraft
        guard !text.isEmpty else { return }
        guard text.count <= Self.maximumMessageLength else {
            errorMessage = "单条消息最多 200 个字符。"
            return
        }
        guard hasLoadedHistory, let sessionID else {
            errorMessage = "请先加载聊天记录。"
            return
        }
        guard !isBusy, let service else { return }

        let requestID = requestIDGenerator()
        isSending = true
        errorMessage = ""
        defer { isSending = false }

        do {
            let result = try await service.send(
                message: text,
                sessionID: sessionID,
                requestID: requestID
            )
            guard result.sessionID == sessionID else {
                throw ChatStateError.sessionMismatch
            }
            guard result.persisted else {
                throw ChatStateError.notPersisted
            }
            messages.append(result.userMessage)
            messages.append(result.assistantMessage)
            draft = ""
            lastReplyWasDegraded = result.degraded
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
            }
            errorMessage = Self.userFacingMessage(for: error, action: "发送消息")
        }
    }

    func clear() async {
        guard hasLoadedHistory, let sessionID else {
            errorMessage = "请先加载聊天记录。"
            return
        }
        guard !isBusy, let service else { return }

        let requestID = requestIDGenerator()
        isClearing = true
        errorMessage = ""
        defer { isClearing = false }

        do {
            let result = try await service.clear(
                sessionID: sessionID,
                requestID: requestID
            )
            guard result.sessionID == sessionID, result.cleared else {
                throw ChatStateError.sessionMismatch
            }
            messages = []
            lastReplyWasDegraded = false
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
            }
            errorMessage = Self.userFacingMessage(for: error, action: "清空聊天记录")
        }
    }

    func clearError() {
        guard service != nil, !canRetryHistory else { return }
        errorMessage = ""
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func invalidateSession() {
        sessionID = nil
        hasLoadedHistory = false
        lastReplyWasDegraded = false
    }

    private static func isSessionInvalidatingError(_ error: Error) -> Bool {
        if let stateError = error as? ChatStateError {
            return stateError == .sessionMismatch || stateError == .invalidServerSession
        }
        guard let appError = error as? AppError,
              case let .server(code) = appError else {
            return false
        }
        return code == "session_mismatch" || code == "invalid_session_id"
    }

    private static func userFacingMessage(for error: Error, action: String) -> String {
        if let stateError = error as? ChatStateError {
            switch stateError {
            case .invalidServerSession, .sessionMismatch:
                return "聊天会话已失效，请重新加载聊天记录。"
            case .notPersisted:
                return "消息未被服务器保存，请稍后重试。"
            }
        }
        if let appError = error as? AppError {
            switch appError {
            case .unauthorized:
                return "授权已失效，请重新绑定设备。"
            case .networkUnavailable:
                return "网络不可用，请检查连接后重试。"
            case .configuration:
                return "聊天服务配置不可用。"
            case let .server(code):
                if code == "session_mismatch" || code == "invalid_session_id" {
                    return "聊天会话已失效，请重新加载聊天记录。"
                }
                return "服务暂时不可用，请稍后重试。"
            case .protocolError, .audio:
                return "\(action)失败，请稍后重试。"
            }
        }
        return "\(action)失败，请稍后重试。"
    }
}

private enum ChatStateError: Error, Equatable {
    case invalidServerSession
    case sessionMismatch
    case notPersisted
}
