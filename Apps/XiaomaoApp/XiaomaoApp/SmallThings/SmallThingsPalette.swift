import SwiftUI

/// 小事模块只保留语义别名，所有视觉值均来自 App 的 Theme。
enum SmallThingsPalette {
    static let primary = Theme.primary
    static let primarySoft = Theme.primarySoft
    static let background = Theme.bg
    static let elevated = Theme.bgElevated
    static let warmSurface = Theme.surfaceWarm
    static let surface = Theme.surface
    static let border = Theme.border
    static let text = Theme.textPrimary
    static let secondaryText = Theme.textSecondary
    static let tertiaryText = Theme.textTertiary
    static let success = Theme.success
    static let danger = Theme.danger
}

extension View {
    @ViewBuilder
    func smallThingsSymbolTransition(reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            self.contentTransition(.symbolEffect(.replace))
        }
    }

    @ViewBuilder
    func smallThingsReactionTransition(reduceMotion: Bool, value: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            self
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: value)
        }
    }
}
