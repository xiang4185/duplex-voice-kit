import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    static let maximumMessageLength = 200
    private static let xiaomaoModePreferenceKey = "chat.xiaomaoParticipationMode"

    @Published var draft = ""
    @Published var xiaomaoMode: XiaomaoParticipationMode {
        didSet {
            preferences.set(xiaomaoMode.rawValue, forKey: Self.xiaomaoModePreferenceKey)
        }
    }
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
    private let preferences: UserDefaults
    private var hasAttemptedHistoryLoad = false
    private var pendingSend: (fingerprint: String, requestID: String)?
    private var pendingRetryRequestIDs: [String: String] = [:]
    private var pendingClear: (fingerprint: String, requestID: String)?

    init(
        service: (any ChatServicing)?,
        configurationError: String? = nil,
        requestIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        preferences: UserDefaults = .standard
    ) {
        self.service = service
        self.configurationError = configurationError
        self.requestIDGenerator = requestIDGenerator
        self.preferences = preferences
        if let stored = preferences.string(forKey: Self.xiaomaoModePreferenceKey),
           let mode = XiaomaoParticipationMode(rawValue: stored) {
            self.xiaomaoMode = mode
        } else {
            // 首次使用默认每轮都有小猫；之后严格恢复用户上一次选择。
            self.xiaomaoMode = .always
        }
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
            clearPendingRequestIDs()
            hasLoadedHistory = true
            lastReplyWasDegraded = false
            requiresReconfiguration = false
        } catch {
            sessionID = nil
            hasLoadedHistory = false
            errorMessage = Self.userFacingMessage(for: error, action: "加载聊天记录")
            requiresReconfiguration = requiresReconfigurationAndNotify(for: error)
        }
    }

    func refreshHistorySilently() async {
        guard hasLoadedHistory,
              !isBusy,
              let currentSessionID = sessionID,
              let service else { return }
        do {
            let result = try await service.loadHistory()
            guard result.sessionID == currentSessionID else {
                throw ChatStateError.sessionMismatch
            }
            clearPendingRequestIDs()
            guard result.messages != messages else { return }
            messages = result.messages
            let completedXiaomaoTurns = Set(
                result.messages
                    .filter { $0.participant == .xiaomao && $0.status == .completed }
                    .map(\.turnID)
            )
            failedXiaomaoTurns.subtract(completedXiaomaoTurns)
            requiresReconfiguration = false
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
                errorMessage = Self.userFacingMessage(for: error, action: "刷新聊天记录")
                requiresReconfiguration = requiresReconfigurationAndNotify(for: error)
            }
        }
    }

    func send(companionTypeID: String = CompanionType.warm.rawValue) async {
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
            let fingerprint = [sessionID, text, xiaomaoMode.rawValue, companionTypeID]
                .joined(separator: "\u{1F}")
            let requestID: String
            if let pendingSend, pendingSend.fingerprint == fingerprint {
                requestID = pendingSend.requestID
            } else {
                requestID = requestIDGenerator()
                pendingSend = (fingerprint, requestID)
            }
            let result = try await service.send(
                message: text,
                sessionID: sessionID,
                requestID: requestID,
                xiaomaoMode: xiaomaoMode,
                companionTypeID: companionTypeID
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
            pendingSend = nil
            lastReplyWasDegraded = result.degraded
            requiresReconfiguration = false
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
            }
            errorMessage = Self.userFacingMessage(for: error, action: "发送消息")
            requiresReconfiguration = requiresReconfigurationAndNotify(for: error)
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
            let requestID = pendingRetryRequestIDs[turnID] ?? requestIDGenerator()
            pendingRetryRequestIDs[turnID] = requestID
            let result = try await service.retryXiaomao(
                turnID: turnID,
                sessionID: sessionID,
                requestID: requestID
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
            pendingRetryRequestIDs.removeValue(forKey: turnID)
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
            }
            errorMessage = Self.userFacingMessage(for: error, action: "重试小猫回复")
            requiresReconfiguration = requiresReconfigurationAndNotify(for: error)
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
            let fingerprint = sessionID
            let requestID: String
            if let pendingClear, pendingClear.fingerprint == fingerprint {
                requestID = pendingClear.requestID
            } else {
                requestID = requestIDGenerator()
                pendingClear = (fingerprint, requestID)
            }
            let result = try await service.clear(
                sessionID: sessionID,
                requestID: requestID
            )
            guard result.sessionID == sessionID, result.cleared else {
                throw ChatStateError.sessionMismatch
            }
            messages = []
            pendingClear = nil
            failedXiaomaoTurns.removeAll()
            lastReplyWasDegraded = false
        } catch {
            if Self.isSessionInvalidatingError(error) {
                invalidateSession()
            }
            errorMessage = Self.userFacingMessage(for: error, action: "清空聊天记录")
            requiresReconfiguration = requiresReconfigurationAndNotify(for: error)
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
        clearPendingRequestIDs()
    }

    private func clearPendingRequestIDs() {
        pendingSend = nil
        pendingRetryRequestIDs.removeAll()
        pendingClear = nil
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

    private func requiresReconfigurationAndNotify(for error: Error) -> Bool {
        let required = Self.requiresReconfiguration(for: error)
        if let appError = error as? AppError,
           case .unauthorized = appError {
            NotificationCenter.default.post(name: .credentialsExpired, object: nil)
        }
        return required
    }
}

private enum ChatStateError: Error, Equatable {
    case invalidServerSession
    case sessionMismatch
    case notPersisted
}
