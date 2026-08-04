import Combine
import Foundation

// MARK: - 头像隐私状态 (AvatarPrivacyStore)
// v6.1 隐私优先: 头像默认高斯模糊, 轻触解锁需显式同意「建立陪伴关系」,
// 屏7 提供「显示真实形象」总开关; 关闭后所有头像保持模糊.
// 状态持久化到 UserDefaults.

@MainActor
final class AvatarPrivacyStore: ObservableObject {
    @Published var showRealAvatar: Bool {
        didSet {
            UserDefaults.standard.set(showRealAvatar, forKey: Self.avatarKey)
        }
    }

    /// 已同意建立陪伴关系的角色 (解锁后 true)
    @Published private(set) var unlockedCharacter: Bool {
        didSet {
            UserDefaults.standard.set(unlockedCharacter, forKey: Self.unlockKey)
        }
    }

    private static let avatarKey = "privacy.showRealAvatar.v61"
    private static let unlockKey = "privacy.unlockedCharacter.v61"

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.avatarKey) as? Bool
        showRealAvatar = stored ?? true   // 默认开启 (未设置过则为首次, 走解锁仪式)
        unlockedCharacter = UserDefaults.standard.bool(forKey: Self.unlockKey)
    }

    /// 轻触头像时: 已解锁或总开关关闭 → 直接显示; 否则需同意
    func effectiveReveal() -> Bool {
        showRealAvatar && unlockedCharacter
    }

    /// 同意建立陪伴关系并解锁
    func unlock() {
        unlockedCharacter = true
    }

    /// 暂不同意 (保持模糊)
    func keepLocked() {
        unlockedCharacter = false
    }

    /// 重置 (调试/测试用)
    func reset() {
        unlockedCharacter = false
        showRealAvatar = true
    }
}

// MARK: - 全局单例 (简单共享, 不引入环境注入复杂度)
@MainActor
enum AvatarPrivacy {
    static let shared = AvatarPrivacyStore()
}
