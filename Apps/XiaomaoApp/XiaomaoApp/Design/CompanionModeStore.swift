import Combine
import Foundation

enum AppVisualMode: String, Codable, Equatable, Sendable {
    case warm
    case mystery
}

enum CompanionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case warm
    case assertive
    case romantic
    case mystery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warm: return "温柔陪伴"
        case .assertive: return "强势偏爱"
        case .romantic: return "黏人浪漫"
        case .mystery: return "未知"
        }
    }

    var summary: String {
        switch self {
        case .warm: return "耐心、自然、会接住情绪"
        case .assertive: return "果断、有主见、偏爱感强"
        case .romantic: return "主动、会撒娇、互动感强"
        case .mystery: return "尚未被定义"
        }
    }

    var visualMode: AppVisualMode {
        self == .mystery ? .mystery : .warm
    }
}

@MainActor
final class CompanionModeStore: ObservableObject {
    static let persistenceKey = "xiaomao.companion.type.v1"

    @Published private(set) var current: CompanionType

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.persistenceKey)
        current = CompanionType(rawValue: stored ?? "") ?? .warm
    }

    var visualMode: AppVisualMode { current.visualMode }

    func select(_ type: CompanionType) {
        guard current != type else { return }
        current = type
        defaults.set(type.rawValue, forKey: Self.persistenceKey)
    }
}
