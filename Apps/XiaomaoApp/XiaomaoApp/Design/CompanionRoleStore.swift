import SwiftUI

// MARK: - 角色预览模型 (P2.6D)
// 严格区分「视觉预览角色」与「生产语音角色」:
// - previewRole: 用户可预览/切换的视觉角色, 仅影响 UI 展示 (名字/主题/头像/文案)
// - productionRole: 恒为 .xiaomao — 真实音色/人格/服务端配置永不随预览切换

enum CompanionPreviewRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case xiaomao
    case healingGirl
    case calmUncle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xiaomao: return "小猫"
        case .healingGirl: return "治愈少女"
        case .calmUncle: return "沉稳大叔"
        }
    }

    var chips: [String] {
        switch self {
        case .xiaomao: return ["元气", "话痨"]
        case .healingGirl: return ["温柔", "共情"]
        case .calmUncle: return ["稳重", "倾听"]
        }
    }

    var tagline: String {
        switch self {
        case .xiaomao: return "今天想说点什么？"
        case .healingGirl: return "我在听，慢慢说。"
        case .calmUncle: return "坐一会儿，不急。"
        }
    }

    var introCopy: String {
        switch self {
        case .xiaomao: return "和小猫说说话"
        case .healingGirl: return "和治愈少女说说话"
        case .calmUncle: return "和沉稳大叔说说话"
        }
    }

    var themeColor: Color {
        switch self {
        case .xiaomao: return Theme.roleGold
        case .healingGirl: return Theme.roleBlush
        case .calmUncle: return Theme.roleCaramel
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .xiaomao: return Theme.charWarmGradient
        case .healingGirl: return Theme.charSakuraGradient
        case .calmUncle: return Theme.charCaramelGradient
        }
    }

    /// 仅小猫为生产语音角色; 其他角色只允许视觉预览, 不得启动真实通话
    var isProductionVoice: Bool { self == .xiaomao }

    /// 程序化占位符号 (非小猫角色: 原创程序化形象, 不用小猫照片冒充)
    var placeholderSymbol: String? {
        switch self {
        case .xiaomao: return nil
        case .healingGirl: return "leaf.fill"
        case .calmUncle: return "sun.max.fill"
        }
    }
}

// MARK: - 全局角色预览状态
@MainActor
final class CompanionRoleStore: ObservableObject {
    static let shared = CompanionRoleStore()

    /// 视觉预览角色 (用户可切换, 仅影响 UI 展示)
    @Published var previewRole: CompanionPreviewRole = .xiaomao

    /// 生产语音角色: 恒为小猫 (真实音色/人格/服务端配置)
    let productionRole: CompanionPreviewRole = .xiaomao

    private init() {}
}
