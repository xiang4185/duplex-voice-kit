import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    static let maximumMessageLength = 200

    @Published var draft = ""
    @Published var xiaomaoMode: XiaomaoParticipationMode = .auto
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var sessionID: String?
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var isSending = false
    @Published private(set) var isClearing = false
    @Published private(set) var hasLoadedHistory = false
    @Published private(set) var lastReplyWasDegraded = false
    @Published private(set) var requiresReconfiguration = false
    @Published private(set) var failedXiaomaoTurns: Set<String> = []
    @Published private(set) var retryingXiaomaoTurnID: String?
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
        isLoadingHistory || isSending || isClearing || retryingXiaomaoTurnID != nil
    }

    var isConfigurationAvailable: Bool { service != nil }

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

    var draftCharacterCount: Int { draft.count }

    func canRetryXiaomao(turnID: String) -> Bool {
        failedXiaomaoTurns.contains(turnID)
            && retryingXiaomaoTurnID == nil
            && !isSending
            && !isClearing
            && hasLoadedHistory
            && sessionID != nil
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
            failedXiaomaoTurns.removeAll()
            hasLoadedHistory = true
            lastReplyWasDegraded = false
            requiresReconfiguration = false
        } catch {
            sessionID = nil
            hasLoadedHistory = false
            errorMessage = Self.userFacingMessage(for: error, action: "加载聊天记录")
            requiresReconfiguration = Self.requiresReconfiguration(for: error)
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

        isSending = true
        errorMessage = ""
        defer { isSending = false }

        do {
            let result = try await service.send(
                message: text,
                sessionID: sessionID,
                requestID: requestIDGenerator(),
                xiaomaoMode: xiaomaoMode
            )
            guard result.sessionID == sessionID else {
                throw ChatStateError.sessionMismatch
            }
            guard result.persisted else {
                throw ChatStateError.notPersisted
            }
            messages.append(contentsOf: result.messages)
            for participantResult in result.participantResults
            where participantResult.participant == .xiaomao {
                if participantResult.status == .failed && participantResult.retryable {
                    failedXiaomaoTurns.insert(participantResult.turnID)
                } else {
                    failedXiaomaoTurns.remove(participantResult.turnID)
                }
            }
            draft = ""
            lastReplyWasDegraded = result.degraded
            requiresReconfiguration = false
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
            }
            errorMessage = Self.userFacingMessage(for: error, action: "发送消息")
            requiresReconfiguration = Self.requiresReconfiguration(for: error)
        }
    }

    func retryXiaomao(turnID: String) async {
        guard canRetryXiaomao(turnID: turnID),
              let sessionID,
              let service else { return }
        retryingXiaomaoTurnID = turnID
        errorMessage = ""
        defer { retryingXiaomaoTurnID = nil }
        do {
            let result = try await service.retryXiaomao(
                turnID: turnID,
                sessionID: sessionID,
                requestID: requestIDGenerator()
            )
            guard result.sessionID == sessionID,
                  result.turnID == turnID,
                  result.participant == .xiaomao,
                  result.status == .completed,
                  result.persisted,
                  let message = result.message else {
                throw ChatStateError.sessionMismatch
            }
            messages.append(message)
            failedXiaomaoTurns.remove(turnID)
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
            }
            errorMessage = Self.userFacingMessage(for: error, action: "重试小猫回复")
            requiresReconfiguration = Self.requiresReconfiguration(for: error)
        }
    }

    func clear() async {
        guard hasLoadedHistory, let sessionID else {
            errorMessage = "请先加载聊天记录。"
            return
        }
        guard !isBusy, let service else { return }

        isClearing = true
        errorMessage = ""
        requiresReconfiguration = false
        defer { isClearing = false }

        do {
            let result = try await service.clear(
                sessionID: sessionID,
                requestID: requestIDGenerator()
            )
            guard result.sessionID == sessionID, result.cleared else {
                throw ChatStateError.sessionMismatch
            }
            messages = []
            failedXiaomaoTurns.removeAll()
            lastReplyWasDegraded = false
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
            }
            errorMessage = Self.userFacingMessage(for: error, action: "清空聊天记录")
            requiresReconfiguration = Self.requiresReconfiguration(for: error)
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
        failedXiaomaoTurns.removeAll()
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
                return "授权已失效，请重新配置连接。"
            case .networkUnavailable:
                return "网络不可用，请检查连接后重试。"
            case .configuration:
                return "聊天服务配置不可用。"
            case let .server(code):
                if code == "session_mismatch" || code == "invalid_session_id" {
                    return "聊天会话已失效，请重新加载聊天记录。"
                }
                if code == "participant_already_completed" {
                    return "小猫已经完成这一轮回复。"
                }
                if code.hasPrefix("http_") {
                    return "服务器返回异常状态（\(code.replacingOccurrences(of: "http_", with: "HTTP "))）。"
                }
                return "服务器拒绝了本次请求，请稍后重试。"
            case .protocolError, .audio:
                return "\(action)失败，请稍后重试。"
            }
        }
        return "\(action)失败，请稍后重试。"
    }

    private static func requiresReconfiguration(for error: Error) -> Bool {
        guard let appError = error as? AppError else { return false }
        switch appError {
        case .unauthorized, .configuration:
            return true
        default:
            return false
        }
    }
}

private enum ChatStateError: Error, Equatable {
    case invalidServerSession
    case sessionMismatch
    case notPersisted
}
