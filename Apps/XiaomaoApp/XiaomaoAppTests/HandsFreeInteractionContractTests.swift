import Foundation
import XCTest
@testable import XiaomaoApp

final class HandsFreeInteractionContractTests: XCTestCase {
    func testProductionVoicePageHasNoPressToTalkOrManualCommitDependency() throws {
        let source = try voiceCallViewSource()
        XCTAssertFalse(source.contains("按住说话"))
        XCTAssertFalse(source.contains("结束本轮"))
        XCTAssertFalse(source.contains("PressToTalkControl"))
        // P2.7B: 免按键用户提示恢复为产品文案
        XCTAssertTrue(source.contains("直接说话就好，小猫在听"))
    }

    func testForegroundRouteIsFixedToBWithoutRoutePicker() throws {
        let source = try voiceCallViewSource()
        XCTAssertTrue(source.contains("SC2.0 · 路线 B"))
        XCTAssertFalse(source.contains("Picker(\"路线"))
        XCTAssertFalse(source.contains("VoiceRoute.allCases"))
    }

    private func voiceCallViewSource() throws -> String {
        try source("XiaomaoApp/Call/VoiceCallView.swift")
    }

    /// 读取指定相对路径源码 (仓库根为基准)
    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    // P2.6C-REPAIR C: 通话结束统一走 finishCall 单路径关闭 Live Activity
    func testVoiceCallTeardownEndsLiveActivityThroughSinglePath() throws {
        let source = try voiceCallViewSource()

        // 唯一 teardown 辅助方法存在
        XCTAssertTrue(source.contains("private func finishCall"))

        // 无参 finishCall() 四个合法入口 (P2.8A: 左上改为确认弹窗, 不再直接结束):
        // ① Live Activity 挂断 ② idle 预警「结束通话」 ③ idle 结束「回到首页」 ④ 挂断确认「结束通话」
        // 按可执行调用行统计 (正则整行匹配, 排除注释), 不依赖字面总数
        let finishCallLines = source.split(whereSeparator: \.isNewline)
            .filter { $0.range(of: #"^\s+finishCall\(\)$"#, options: .regularExpression) != nil }
        XCTAssertEqual(
            finishCallLines.count, 4,
            "Live Activity / idle 预警 / idle 结束 / 挂断确认四条路径必须统一调用 finishCall()"
        )

        // onDisappear 走 closePage: false (视图已消失, 不手动关闭)
        XCTAssertEqual(
            source.components(separatedBy: "finishCall(closePage: false)").count - 1, 1,
            "onDisappear 必须调用 finishCall(closePage: false)"
        )

        // Live Activity 结束恰好 2 处合法位置 (P2.7B-FINAL-IDLE):
        // ① idleTimeoutEnded onChange 空闲自动结束立即结束 ② finishCall 统一 teardown
        XCTAssertEqual(
            source.components(separatedBy: "CallLiveActivityManager.shared.end()").count - 1, 2,
            "CallLiveActivityManager.shared.end() 必须恰好 2 处: idle 结束立即结束 + finishCall 统一 teardown"
        )

        // viewModel.disappear() 只在 finishCall 内调用一次 (排除注释行)
        let disappearLines = source.split(whereSeparator: \.isNewline)
            .filter { $0.range(of: #"^\s+viewModel\.disappear\(\)$"#, options: .regularExpression) != nil }
            .count
        XCTAssertEqual(disappearLines, 1, "viewModel.disappear() 必须只在 finishCall 内调用一次")
    }

    // MARK: P2.6D 多角色预览彩蛋契约

    func testPreviewRoleConformsToIdentifiableAndProductionStaysXiaomao() throws {
        let store = try source("XiaomaoApp/Design/CompanionRoleStore.swift")
        // CompanionPreviewRole 遵循 Identifiable (sheet(item:) 要求)
        XCTAssertTrue(store.contains("enum CompanionPreviewRole"))
        XCTAssertTrue(store.contains("Identifiable"))
        XCTAssertTrue(store.contains("var id: String { rawValue }"))
        // productionRole 恒为小猫
        XCTAssertTrue(store.contains("productionRole"))
        XCTAssertTrue(store.contains("let productionRole: CompanionPreviewRole = .xiaomao"))
        // 明确区分预览与生产
        XCTAssertTrue(store.contains("isProductionVoice"))
    }

    func testHomeStartBlocksNonProductionPreview() throws {
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        // 首页 CTA 必须阻止非生产角色启动真实通话
        XCTAssertTrue(home.contains("isProductionVoice"))
        XCTAssertTrue(home.contains("先和小猫说说话吧。"))
        // CTA 文案跟随预览角色 (不写死)
        XCTAssertTrue(home.contains("introCopy"))
    }

    func testVoiceCallUsesProductionRoleAndRetainsFinishCall() throws {
        let call = try voiceCallViewSource()
        // Live Activity 使用生产角色
        XCTAssertTrue(call.contains("productionRole"))
        XCTAssertTrue(call.contains("CompanionRoleStore.shared.productionRole.displayName"))
        // 保留 P2.6B finishCall 单路径
        XCTAssertTrue(call.contains("private func finishCall"))
        XCTAssertTrue(call.contains("finishCall(closePage: false)"))
    }

    // P2.8A: 角色页 1.0 收口 — 单生产角色"小猫", 无占位/彩蛋/死按钮
    func testCharacterSelectSingleProductionRoleCard() throws {
        let select = try source("XiaomaoApp/App/CharacterSelectView.swift")
        // 页面只使用生产角色 / .xiaomao
        XCTAssertTrue(select.contains("productionRole"), "角色页必须引用 productionRole")
        XCTAssertTrue(select.contains("CompanionPreviewRole.xiaomao"), "角色页必须使用 .xiaomao")
        XCTAssertFalse(select.contains("CompanionPreviewRole.allCases"), "不得遍历 allCases")
        XCTAssertFalse(select.contains("handleRoleTap"), "不得保留三角色统一入口 handleRoleTap")
        XCTAssertFalse(select.contains("jealousTarget"), "不得触发吃醋彩蛋")
        XCTAssertFalse(select.contains("jealousTapCount"), "不得保留吃醋计数")
        XCTAssertFalse(select.contains("只是看看"), "不得有 只是看看 角色切换")
        XCTAssertFalse(select.contains("仅预览"), "不得有 仅预览 死按钮")
        // 正式角色卡: PrivacyAvatar 190 + 人物点击隐私确认 + characters.start + 开始聊天
        XCTAssertTrue(select.contains("PrivacyAvatar"), "角色页必须保留 PrivacyAvatar")
        XCTAssertTrue(select.contains("PrivacyAvatar(\n                    size: 190"), "正式角色卡人物尺寸必须为 190")
        XCTAssertTrue(select.contains("showPrivacyConfirm = true"), "人物点击必须可触发隐私确认")
        XCTAssertTrue(select.contains("characters.start"), "characters.start identifier 必须保留")
        XCTAssertTrue(select.contains("startCall()"), "开始聊天必须直接调用 startCall()")

        // P2.6D-FIX-1: 不可点击头像必须退出命中测试 (不拦截卡片手势)
        let avatar = try source("XiaomaoApp/Design/Components/PrivacyAvatar.swift")
        XCTAssertTrue(avatar.contains(".allowsHitTesting(tappable)"), "不可点击头像必须 allowsHitTesting(false)")
        XCTAssertTrue(avatar.contains("guard tappable else { return }"), "tappable=false 不得产生反馈/回调")
        // 隐私确认文案覆盖程序化预览角色 (不写死真实人像)
        XCTAssertTrue(avatar.contains("由授权素材或原创设计生成"))
        XCTAssertFalse(avatar.contains("真实人像授权生成"), "文案不得只适用于真实人像")
    }

    // MARK: P2.6E 彩蛋交互闭环契约

    func testProSheetNoCloseAndLocalEasterEggSheetsExist() throws {
        let settings = try source("XiaomaoApp/Settings/SettingsView.swift")
        // Pro action 设置 showProSheet, 不调用 close()
        XCTAssertTrue(settings.contains("showProSheet = true"), "Pro 必须展示彩蛋 Sheet")
        let closeCallLines = settings.split(whereSeparator: \.isNewline)
            .filter { $0.range(of: #"^\s+close\(\)$"#, options: .regularExpression) != nil }
            .count
        XCTAssertEqual(closeCallLines, 0, "Pro/about 入口不得再调用 close()")
        // 帮助 / 隐私政策 / 关于 均有本地 Sheet 入口
        XCTAssertTrue(settings.contains("showHelpSheet = true"))
        XCTAssertTrue(settings.contains("showPrivacySheet = true"))
        XCTAssertTrue(settings.contains("showAboutSheet = true"))
        // 彩蛋卡组件存在
        XCTAssertTrue(settings.contains("EasterEggCard("))
    }

    func testReplayDetailUsesFixedQuoteAndReducesMotion() throws {
        let cards = try source("XiaomaoApp/Design/Components/EasterEggCards.swift")
        // 详情卡禁止 body 内 randomElement
        XCTAssertFalse(cards.contains("randomElement()"), "语录必须在打开前固定")
        // 观察 reduce motion (模拟播放降级)
        XCTAssertTrue(cards.contains("accessibilityReduceMotion"), "模拟播放必须遵循 Reduce Motion")
        // 固定语录由调用方传入
        XCTAssertTrue(cards.contains("let quote: String"))
        // P2.6I: 回听列表与详情卡已从 ReviewView 移除 (改为诚实空状态),
        // 组件仍保留在 EasterEggCards 中, 待真实历史数据源接入后再挂载.
    }

    // MARK: P2.6F 安全共情彩蛋契约

    func testEmpathyCardProvidesAllKindsAndManualRandom() throws {
        let cards = try source("XiaomaoApp/Design/EmpathyCard.swift")
        // 三类触发卡 + 手动随机
        XCTAssertTrue(cards.contains("static let welcome"))
        XCTAssertTrue(cards.contains("static let longCall"))
        XCTAssertTrue(cards.contains("static let reconnect"))
        XCTAssertTrue(cards.contains("static func randomManual()"))
        // P2.6F-FIX-1: Kind 统一为 userRequest, 不存在 manual
        XCTAssertTrue(cards.contains("case welcome, longCall, reconnect, userRequest"))
        XCTAssertFalse(cards.contains("case .manual"), "Kind 不得包含 manual")
        XCTAssertFalse(cards.contains("kind: .manual"), "手动卡 kind 必须用 .userRequest")
        // 手动卡是提议式表达 (不含自动判断式)
        XCTAssertFalse(cards.contains("有点疲惫"), "手动卡不得用自动判断式表达")
    }

    func testVoiceCallEmpathyUsesSafeTriggersAndKeepsCorePaths() throws {
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        // 2.8s 路径用 .welcome (中性提示), 延时 2.8s 存在
        XCTAssertTrue(call.contains("currentEmpathyCard = .welcome"))
        XCTAssertTrue(call.contains("2_800_000_000"))
        // longCall 只在真实 300s 延时后 (2.8s welcome + 297.2s = 300s)
        XCTAssertTrue(call.contains("297_200_000_000"))
        XCTAssertTrue(call.contains("currentEmpathyCard = .longCall"))
        // reconnectAttempt >= 2 才触发, 且用 onChange 立即监听 (不等 300s, 无轮询)
        XCTAssertTrue(call.contains("onChange(of: viewModel.controller.reconnectAttempt)"))
        XCTAssertTrue(call.contains("reconnectAttempt >= 2"))
        XCTAssertTrue(call.contains("reconnectCardShown"))
        XCTAssertFalse(call.contains("while !Task.isCancelled"), "不得使用五分钟后的轮询")
        // 关心我按钮调用 randomManual() (唯一随机入口)
        XCTAssertTrue(call.contains(".randomManual()"))
        XCTAssertTrue(call.contains("empathyReason = .userRequest"))
        // 不得声称情绪识别
        XCTAssertFalse(call.contains("由情绪识别触发"))
        // 不得出现伪规则代码
        XCTAssertFalse(call.contains("callElapsed"))
        XCTAssertFalse(call.contains("EmpathyTriggerRule"))
        XCTAssertFalse(call.contains("longSilence"))
        XCTAssertFalse(call.contains("silenceSeconds"))
        // 保留 finishCall 单路径 + productionRole
        XCTAssertTrue(call.contains("private func finishCall"))
        XCTAssertTrue(call.contains("finishCall(closePage: false)"))
        XCTAssertTrue(call.contains("productionRole.displayName"))
        // 不新增 Timer
        XCTAssertFalse(call.contains("Timer.scheduledTimer"))
    }

    // MARK: P2.6H 通话页即时呈现与头像尺寸契约

    func testCallEntryShowsUIBeforeSessionStartup() throws {
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")

        // 1. 结构性断言: appeared = true 必须早于 await viewModel.appear()
        guard let appearedIdx = call.range(of: "appeared = true")?.lowerBound,
              let appearIdx = call.range(of: "await viewModel.appear()")?.lowerBound else {
            XCTFail("缺少 appeared = true 或 await viewModel.appear()")
            return
        }
        let appearedOffset = call.distance(from: call.startIndex, to: appearedIdx)
        let appearOffset = call.distance(from: call.startIndex, to: appearIdx)
        XCTAssertLessThan(appearedOffset, appearOffset,
                          "appeared = true 必须位于 await viewModel.appear() 之前 (先显示页面再建立语音会话)")
        // appeared 后让出主线程渲染首帧, 页面跳转后立即呈现背景/头像/状态/控制区
        XCTAssertTrue(call.contains("await Task.yield()"), "appeared 后应让出一次主线程渲染首帧")

        // 2. 保留真实连接流程, 不得删除 viewModel.appear()
        XCTAssertTrue(call.contains("await viewModel.appear()"), "必须保留真实连接流程")

        // 3. 保留 finishCall 单路径 + 生产角色
        XCTAssertTrue(call.contains("private func finishCall"))
        XCTAssertTrue(call.contains("finishCall(closePage: false)"))
        XCTAssertTrue(call.contains("productionRole.displayName"))

        // 4. 通话主头像不再使用 170
        XCTAssertFalse(call.contains("PrivacyAvatar(size: 170, tappable: false)"),
                       "通话主头像不得再使用 170")

        // 5. 通话主视觉使用 P2.7B portrait 完整形象 (heroSize 220 上限 + 弹性下限 + 生产角色)
        XCTAssertTrue(call.contains("private let heroSize: CGFloat = 220"),
                      "通话主视觉 heroSize 上限必须为 220")
        XCTAssertTrue(call.contains("private let heroMinSize: CGFloat = 150"),
                      "通话主视觉必须保留弹性下限 150")
        XCTAssertTrue(call.contains("size: availableSize"),
                      "通话主视觉必须使用自适应尺寸 availableSize")
        XCTAssertTrue(call.contains("variant: .xiaomao"),
                      "通话主视觉必须显式使用生产角色 .xiaomao (portrait 模式)")
        // 小头像 (共情气泡 36 / 抱抱卡 44) 不受影响
        XCTAssertTrue(call.contains("PrivacyAvatar(size: 36, tappable: false)"))
        XCTAssertTrue(call.contains("PrivacyAvatar(size: 44, tappable: false)"))

        // 6. 不新增 Task.detached / Timer.scheduledTimer (无人工延时掩盖)
        XCTAssertFalse(call.contains("Task.detached"), "不得新增 Task.detached")
        XCTAssertFalse(call.contains("Timer.scheduledTimer"), "不得新增 Timer.scheduledTimer")

        // 7. 连接仍只通过 viewModel.appear(), 未引入对 Controller/WebSocket/音频的直接调用
        let forbidden = ["controller.startNewCall(", "webSocket.connect(", "audioUpload",
                         "DVKRealtimeAudioIO", "startCapture("]
        for token in forbidden {
            XCTAssertFalse(call.contains(token), "不得引入对底层链路的直接调用: \(token)")
        }
    }

    // MARK: P2.6I 前端内容清理契约 (旧品牌 / 假数据 / 空状态 / P2.6H 未回退)

    func testFrontendContentCleanup() throws {
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let review = try source("XiaomaoApp/App/ReviewView.swift")
        let settings = try source("XiaomaoApp/Settings/SettingsView.swift")

        // 授权页面不再包含旧品牌与假数据
        let banned = ["嗨，小暖", "暖意共生", "使用统计 · 示例数据", "本次陪伴 12 分钟",
                      "3 条陪伴回顾", "今天 12:34", "昨天 19:36",
                      "疲惫 → 放松", "低落 → 平静", "焦虑 → 安稳", "65%"]
        for token in banned {
            XCTAssertFalse(home.contains(token), "CompanionHomeView 不得包含: \(token)")
            XCTAssertFalse(review.contains(token), "ReviewView 不得包含: \(token)")
            XCTAssertFalse(settings.contains(token), "SettingsView 不得包含: \(token)")
        }

        // 新文案存在 (P2.6J: 不再承诺"完成一次后会显示")
        XCTAssertTrue(settings.contains("小猫在呢"))
        XCTAssertTrue(settings.contains("随时回来和小猫说说话"))
        XCTAssertTrue(settings.contains("关于小猫"))
        XCTAssertTrue(home.contains("陪伴记录"))
        XCTAssertTrue(review.contains("陪伴记录尚未开放"))
        XCTAssertTrue(review.contains("当前版本暂不展示聊天或录音历史。"))
        XCTAssertTrue(settings.contains("使用记录尚未接入"))
        XCTAssertTrue(settings.contains("当前版本暂不展示时长、连续天数或累计统计。"))

        // 首页历史入口直接调用 openHistory()
        XCTAssertTrue(home.contains("openHistory()"))
        // 不再声明/展示静态 RecentReviewOverlay
        XCTAssertFalse(home.contains("RecentReviewOverlay"))

        // P2.6H 未回退 (VoiceCallView) (P2.7B: 头像契约更新为 portrait heroSize 220)
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        XCTAssertTrue(call.contains("private let heroSize: CGFloat = 220"), "P2.7B: heroSize 220 必须保留")
        XCTAssertTrue(call.contains("size: availableSize"), "P2.7B: portrait 自适应尺寸必须保留")
        XCTAssertTrue(call.contains("variant: .xiaomao"), "P2.7B: 通话主视觉必须使用生产角色")
        XCTAssertTrue(call.contains("await Task.yield()"))
        XCTAssertTrue(call.contains("finishCall(closePage: false)"))
        XCTAssertTrue(call.contains("productionRole.displayName"))
        guard let appearedIdx = call.range(of: "appeared = true")?.lowerBound,
              let appearIdx = call.range(of: "await viewModel.appear()")?.lowerBound else {
            XCTFail("缺少 appeared = true 或 await viewModel.appear()")
            return
        }
        XCTAssertLessThan(call.distance(from: call.startIndex, to: appearedIdx),
                          call.distance(from: call.startIndex, to: appearIdx),
                          "appeared = true 必须位于 await viewModel.appear() 之前 (P2.6H 未回退)")
    }

    // MARK: P2.6J 最终前端真实性契约

    func testFinalTruthfulnessContract() throws {
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let maintab = try source("XiaomaoApp/App/MainTabView.swift")
        let settings = try source("XiaomaoApp/Settings/SettingsView.swift")
        let review = try source("XiaomaoApp/App/ReviewView.swift")
        let characters = try source("XiaomaoApp/App/CharacterSelectView.swift")
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        let widget = try source("XiaomaoAppWidgets/CallLiveActivityView.swift")
        let widgetPlist = try source("XiaomaoAppWidgets/Info.plist")

        // 1. 首页齿轮调用 openSettings()
        XCTAssertTrue(home.contains("openSettings()"), "齿轮必须调用 openSettings()")
        // 3. 首页历史入口仍调用 openHistory()
        XCTAssertTrue(home.contains("openHistory()"), "陪伴记录入口必须调用 openHistory()")

        // 2. MainTabView 将 openSettings 映射到 .settings
        XCTAssertTrue(maintab.contains("openSettings"), "MainTabView 必须传递 openSettings")
        XCTAssertTrue(maintab.contains("selectedTab = .settings"), "openSettings 必须映射到 .settings")

        // 4/5. 普通 statusRow 隐藏内部信息; SC2.0·路线B 移到诊断 Sheet
        XCTAssertTrue(call.contains("SC2.0 · 路线 B"), "SC2.0 · 路线 B 必须保留 (诊断 Sheet 可见)")
        XCTAssertFalse(call.contains("降噪开启"), "普通界面不得显示 降噪开启")
        guard let diagIdx = call.range(of: "private var diagnosticsSheet")?.lowerBound,
              let sc20Idx = call.range(of: "SC2.0 · 路线 B")?.lowerBound else {
            XCTFail("缺少 diagnosticsSheet 或 SC2.0 · 路线 B")
            return
        }
        XCTAssertLessThan(call.distance(from: call.startIndex, to: diagIdx),
                          call.distance(from: call.startIndex, to: sc20Idx),
                          "SC2.0 · 路线 B 必须位于诊断 Sheet 中 (普通界面不可见)")

        // 6. 真实会话状态映射
        XCTAssertTrue(call.contains("callStatusText"), "必须存在真实状态文案计算属性")
        let statusCopy = ["正在连接小猫", "小猫正在听你说话", "小猫正在想", "小猫正在说话",
                          "正在重新连接", "网络状态不稳定", "正在结束", "连接失败"]
        for token in statusCopy {
            XCTAssertTrue(call.contains(token), "状态映射缺少: \(token)")
        }

        // 7. P2.6H 未回退 (P2.7B: 头像契约更新为 portrait heroSize 220)
        XCTAssertTrue(call.contains("private let heroSize: CGFloat = 220"))
        XCTAssertTrue(call.contains("size: availableSize"))
        XCTAssertTrue(call.contains("variant: .xiaomao"))
        XCTAssertTrue(call.contains("await Task.yield()"))
        XCTAssertTrue(call.contains("finishCall(closePage: false)"))
        XCTAssertTrue(call.contains("productionRole.displayName"))
        guard let aIdx = call.range(of: "appeared = true")?.lowerBound,
              let bIdx = call.range(of: "await viewModel.appear()")?.lowerBound else {
            XCTFail("缺少 appeared = true 或 await viewModel.appear()")
            return
        }
        XCTAssertLessThan(call.distance(from: call.startIndex, to: aIdx),
                          call.distance(from: call.startIndex, to: bIdx),
                          "appeared = true 必须早于 await viewModel.appear() (P2.6H 未回退)")

        // 8. 设置页不含旧品牌/无效声明
        let settingsBanned = ["暖伴", "暖意共生", "保存录音历史", "理解情绪",
                              "不在本地留存", "所有语音均加密处理", "显示真实形象"]
        for token in settingsBanned {
            XCTAssertFalse(settings.contains(token), "SettingsView 不得包含: \(token)")
        }
        // 9. 设置页包含新文案
        XCTAssertTrue(settings.contains("小猫 Pro"))
        XCTAssertTrue(settings.contains("实时语音服务"))
        XCTAssertTrue(settings.contains("显示角色形象"))

        // 10/11. Widget 品牌修复
        XCTAssertFalse(widget.contains("暖伴"), "Widget 视图不得包含 暖伴")
        XCTAssertFalse(widget.contains("降噪开启"), "Widget 视图不得包含 降噪开启")
        XCTAssertTrue(widget.contains("小猫 · 通话中"), "Widget 必须显示 小猫")
        XCTAssertFalse(widgetPlist.contains("暖伴"), "Widget Info.plist 不得包含 暖伴")
        XCTAssertTrue(widgetPlist.contains("小猫"), "Widget Info.plist 必须显示 小猫")

        // 12. ReviewView 不再承诺完成一次后自动生成
        XCTAssertFalse(review.contains("完成一次陪伴后"), "ReviewView 不得承诺完成后自动生成")

        // 13. P2.8A: 角色页 1.0 单正式角色卡 (不再有 224 多角色卡 / 旧 previewBar)
        XCTAssertFalse(characters.contains(".frame(width: 156, height: 224)"),
                       "1.0 不得保留多角色 224 小卡片")
        XCTAssertTrue(characters.contains("frame(maxWidth: 340)"),
                      "正式角色卡宽度最大约 320-340 pt")
        XCTAssertTrue(characters.contains("productionCard"), "必须存在 productionCard")
        XCTAssertFalse(characters.contains("previewBar"), "不得保留旧 previewBar")
        XCTAssertFalse(characters.contains("仅预览"), "不得有 仅预览 死按钮")

        // 14. 角色页 1.0 文案与结构
        XCTAssertTrue(characters.contains("当前陪伴角色"), "角色页标题必须为 当前陪伴角色")
        XCTAssertTrue(characters.contains("目前仅小猫支持实时语音"), "必须说明 目前仅小猫支持实时语音")
        XCTAssertTrue(characters.contains("更多角色正在准备中"), "必须说明 更多角色正在准备中")
        XCTAssertTrue(characters.contains("startBar"), "开始聊天条 startBar 必须存在")
        XCTAssertTrue(characters.contains("characters.start"), "characters.start 必须保留")
        XCTAssertTrue(characters.contains("支持实时通话"), "角色卡必须标注 支持实时通话")

        // 15. Toast 不使用固定底部定位
        XCTAssertFalse(home.contains(".padding(.bottom, 110)"), "首页 Toast 不得使用固定底部定位")
        XCTAssertFalse(home.contains(".padding(.bottom, 120)"), "首页 Toast 不得使用固定底部定位")
        XCTAssertFalse(characters.contains(".padding(.bottom, 110)"), "角色页 Toast 不得使用固定底部定位")
        XCTAssertFalse(characters.contains(".padding(.bottom, 120)"), "角色页 Toast 不得使用固定底部定位")
    }

    // MARK: P2.6J+ 补充: 头像柔边遮罩与可点击卡片按压

    func testAvatarFeatherMaskAndPressableCardStyle() throws {
        let avatar = try source("XiaomaoApp/Design/Components/PrivacyAvatar.swift")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let characters = try source("XiaomaoApp/App/CharacterSelectView.swift")
        let settings = try source("XiaomaoApp/Settings/SettingsView.swift")

        // A. 小猫头像径向柔边遮罩: 只羽化外缘, 保留清晰中心
        XCTAssertTrue(avatar.contains(".mask \u{7B}"), "PrivacyAvatar 必须使用 mask 实现柔边")
        XCTAssertTrue(avatar.contains("RadialGradient"), "柔边遮罩必须使用径向渐变")
        XCTAssertTrue(avatar.contains("location: 0.82"), "遮罩应在中心 82% 处保持清晰")

        // B. PressableCardStyle 定义: scale 0.985 + reduceMotion
        XCTAssertTrue(home.contains("struct PressableCardStyle"), "必须定义 PressableCardStyle")
        XCTAssertTrue(home.contains("0.985"), "按压 scale 必须约 0.985")
        XCTAssertTrue(home.contains("accessibilityReduceMotion"), "PressableCardStyle 必须遵循 Reduce Motion")

        // 应用位置: 首页记录入口 / 设置关于行 (通用按钮按压样式保留)
        XCTAssertTrue(home.contains("buttonStyle(PressableCardStyle())"), "首页记录入口必须使用 PressableCardStyle")
        XCTAssertTrue(settings.contains("buttonStyle(PressableCardStyle())"), "设置关于行必须使用 PressableCardStyle")
        // P2.8A: 角色页 1.0 正式角色卡 (删除旧三角色 pressedRole/0.985/handleRoleTap 断言)
        XCTAssertFalse(characters.contains("pressedRole"), "1.0 角色页不得保留多角色按压状态")
        XCTAssertFalse(characters.contains("handleRoleTap"), "1.0 角色页不得保留三角色统一入口")
        XCTAssertTrue(characters.contains("productionCard"), "必须存在 productionCard")
        XCTAssertTrue(characters.contains("PrivacyAvatar(\n                    size: 190"), "正式角色卡人物尺寸必须为 190")
        XCTAssertTrue(characters.contains("frame(maxWidth: 340)"), "正式角色卡宽度最大 340")
        XCTAssertTrue(characters.contains("cardTopHighlight()"), "正式角色卡必须保留 cardTopHighlight")
        XCTAssertTrue(characters.contains("Theme.shadowFloating"), "正式角色卡必须使用 Theme.shadowFloating")
        XCTAssertTrue(characters.contains("当前角色"), "正式角色卡必须包含 当前角色 Badge")
        XCTAssertTrue(characters.contains("支持实时通话"), "正式角色卡必须标注 支持实时通话")
    }

    // MARK: P2.6K 最终 Live Activity 状态真实性契约

    func testFinalLiveActivityStatusContract() throws {
        let widget = try source("XiaomaoAppWidgets/CallLiveActivityView.swift")
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")

        // 1. Widget 删除虚假目标与进度
        XCTAssertFalse(widget.contains("goalMinutes"), "Widget 普通 UI 不得引用 goalMinutes")
        XCTAssertFalse(widget.contains("Text(\"目标"), "Widget 不得显示用户可见目标文案")
        XCTAssertFalse(widget.contains("ProgressView(value: context.state.progress)"),
                       "Widget 不得包含基于假目标的进度条")

        // 2. Widget 保留真实数据
        XCTAssertTrue(widget.contains("timeString"), "Widget 必须保留真实计时")
        XCTAssertTrue(widget.contains("characterName"), "Widget 必须保留真实角色名")
        XCTAssertTrue(widget.contains("isMuted"), "Widget 必须保留静音状态")
        XCTAssertTrue(widget.contains("isSpeaking"), "Widget 必须保留真实说话状态")

        // 3. MiniIslandWave Timer 生命周期
        XCTAssertTrue(widget.contains("waveTimer"), "MiniIslandWave 必须持有 waveTimer")
        XCTAssertTrue(widget.contains("waveTimer?.invalidate()"), "Timer 必须显式清理")
        XCTAssertTrue(widget.contains(".onDisappear"), "视图消失必须释放 Timer")
        XCTAssertTrue(widget.contains("waveTimer = nil"), "Timer 必须置空")

        // 4. VoiceCall 状态点颜色映射
        XCTAssertTrue(call.contains("callStatusColor"), "必须存在状态点颜色计算属性")
        XCTAssertTrue(call.contains(".fill(callStatusColor)"), "状态点必须使用 callStatusColor")
        for token in ["Theme.textTertiary", "Theme.online", "Theme.warning", "Theme.danger"] {
            XCTAssertTrue(call.contains(token), "状态颜色映射缺少: \(token)")
        }

        // 5. 既有契约锚点保留 (P2.6H/J/J+ 未回退) (P2.7B: 头像契约更新为 portrait heroSize 220)
        XCTAssertTrue(call.contains("callStatusText"))
        XCTAssertTrue(call.contains("private let heroSize: CGFloat = 220"), "P2.7B: heroSize 220 必须保留")
        XCTAssertTrue(call.contains("variant: .xiaomao"), "P2.7B: 通话主视觉必须使用生产角色")
        XCTAssertTrue(call.contains("finishCall(closePage: false)"))
        XCTAssertTrue(call.contains("productionRole.displayName"))
        XCTAssertTrue(call.contains("SC2.0 · 路线 B"))
        XCTAssertTrue(call.contains("await Task.yield()"))
        guard let aIdx = call.range(of: "appeared = true")?.lowerBound,
              let bIdx = call.range(of: "await viewModel.appear()")?.lowerBound else {
            XCTFail("缺少 appeared = true 或 await viewModel.appear()")
            return
        }
        XCTAssertLessThan(call.distance(from: call.startIndex, to: aIdx),
                          call.distance(from: call.startIndex, to: bIdx))
    }

    // MARK: P2.6K-FIX-1 Widget 波形随状态启停契约

    func testWidgetWaveTimerStateDriven() throws {
        let widget = try source("XiaomaoAppWidgets/CallLiveActivityView.swift")

        // 状态驱动入口
        XCTAssertTrue(widget.contains("onChange(of: active)"), "必须监听 active 变化")
        XCTAssertTrue(widget.contains("onChange(of: reduceMotion)"), "必须监听 reduceMotion 变化")

        // 统一 Timer 生命周期方法
        XCTAssertTrue(widget.contains("private func updateWaveTimer(isActive: Bool)"),
                      "必须存在 updateWaveTimer")
        // 非活跃分支: 无条件先清理, 非活跃/Reduce Motion 时置空并复位 phase
        XCTAssertTrue(widget.contains("waveTimer?.invalidate()"), "Timer 必须显式清理")
        XCTAssertTrue(widget.contains("waveTimer = nil"), "非活跃分支必须将 waveTimer 置空")
        XCTAssertTrue(widget.contains("phase = false"), "非活跃分支必须将 phase 复位")
        XCTAssertTrue(widget.contains("guard isActive, !reduceMotion"), "非活跃/Reduce Motion 必须立即停止")

        // Timer 只创建一次 (统一在 updateWaveTimer 中)
        XCTAssertEqual(widget.components(separatedBy: "Timer.scheduledTimer").count - 1, 1,
                       "Timer.scheduledTimer 只能出现一次")

        // onDisappear 最终释放
        XCTAssertTrue(widget.contains(".onDisappear"), "onDisappear 仍负责最终释放")

        // 继续确认无假目标/假进度
        XCTAssertFalse(widget.contains("goalMinutes"), "Widget 不得引用 goalMinutes")
        XCTAssertFalse(widget.contains("ProgressView(value: context.state.progress)"),
                       "Widget 不得包含假进度条")
    }

    // MARK: P2.7A iOS 26 原生玻璃契约

    func testIOS26NativeGlassContract() throws {
        let project = try source("project.yml")
        let ci = try source(".github/workflows/ios-ci.yml")
        let ipa = try source(".github/workflows/ios-unsigned-ipa.yml")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let characters = try source("XiaomaoApp/App/CharacterSelectView.swift")
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        let avatar = try source("XiaomaoApp/Design/Components/PrivacyAvatar.swift")
        let tabs = try source("XiaomaoApp/App/MainTabView.swift")

        // 1. deployment target 26.0
        XCTAssertTrue(project.contains("iOS: \"26.0\""), "project.yml 必须部署 iOS 26.0")

        // 2. 两个 workflow 都选择 Xcode 26 + 写入 DEVELOPER_DIR + 验证 Xcode/SDK
        for wf in [ci, ipa] {
            XCTAssertTrue(wf.contains("Xcode_26*.app"), "workflow 必须发现 Xcode_26.app")
            XCTAssertTrue(wf.contains("DEVELOPER_DIR"), "workflow 必须写入 DEVELOPER_DIR")
            XCTAssertTrue(wf.contains("$GITHUB_ENV"), "DEVELOPER_DIR 必须写入 GITHUB_ENV")
            XCTAssertTrue(wf.contains("\"Xcode 26\"*)"), "必须验证 xcodebuild 以 Xcode 26 开头")
            XCTAssertTrue(wf.contains("show-sdk-version"), "必须验证 iphoneos SDK 版本")
        }

        // 3. 无第三方 setup-xcode Action
        XCTAssertFalse(ci.lowercased().contains("setup-xcode"), "不得引入第三方 setup-xcode Action")
        XCTAssertFalse(ipa.lowercased().contains("setup-xcode"), "不得引入第三方 setup-xcode Action")

        // 4. 原生 TabView 保留
        XCTAssertTrue(tabs.contains("TabView(selection:"), "必须保留原生 TabView(selection:)")
        XCTAssertTrue(tabs.contains(".tabItem"), "必须保留 .tabItem")
        XCTAssertTrue(tabs.contains(".tint(Theme.primary)"), "必须保留 .tint(Theme.primary)")

        // 5. 首页主 CTA 玻璃
        XCTAssertTrue(home.contains(".glassEffect("), "首页 CTA 必须使用 glassEffect")
        XCTAssertTrue(home.contains(".interactive()"), "首页 CTA 必须交互玻璃")
        XCTAssertTrue(home.contains(".tint(Theme.primary)"), "首页 CTA 必须主色 tint")
        XCTAssertFalse(home.contains(".background(Theme.primary, in: Capsule())"), "首页 CTA 不得叠加实体胶囊背景")
        XCTAssertFalse(home.contains("1.015"), "不得保留 1.015 强缩放")

        // 6. 首页 Toast 玻璃 + allowsHitTesting(false) 保留 (P2.8A: 角色页 1.0 只保留 startBar 一处 Glass)
        XCTAssertTrue(home.contains("allowsHitTesting(false)"), "首页 Toast 必须保留 allowsHitTesting(false)")
        XCTAssertEqual(home.components(separatedBy: ".glassEffect(").count - 1, 2, "首页应有 CTA + Toast 两处玻璃")

        // 7. P2.8A: 角色页 startBar 原生 Glass (不再要求 Toast / 旧预览条 + Toast 两处 Glass)
        XCTAssertTrue(characters.contains("startBar"), "角色页必须有 startBar")
        XCTAssertTrue(characters.contains(".glassEffect("), "startBar 必须使用原生 Glass")
        XCTAssertTrue(characters.contains("in: .rect(cornerRadius: Theme.Radius.card)"), "startBar 必须使用圆角玻璃")

        // 8. 角色卡保持实体表面
        XCTAssertTrue(characters.contains(".background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.characterCard"),
                      "角色卡必须保持实体 Theme.surface")

        // 9. 通话控制区 GlassEffectContainer + glassEffect
        XCTAssertTrue(call.contains("GlassEffectContainer"), "通话控制区必须使用 GlassEffectContainer")
        XCTAssertTrue(call.contains(".glassEffect(glassEffect(style), in: .circle)"), "控制按钮必须为圆形玻璃")

        // 10. 静音图标 Symbol 替换过渡
        XCTAssertTrue(call.contains(".contentTransition(.symbolEffect(.replace))"), "静音图标必须使用 Symbol replace 过渡")

        // 11. 聆听麦克风状态驱动 pulse
        XCTAssertTrue(call.contains(".symbolEffect(.pulse"), "麦克风必须使用 symbolEffect pulse")
        XCTAssertTrue(call.contains("isActive: micPulse"), "pulse 必须状态驱动")

        // 12. PrivacyAvatar 解锁图标
        XCTAssertTrue(avatar.contains("lock.fill"), "锁定状态必须使用 lock.fill")
        XCTAssertTrue(avatar.contains("lock.open.fill"), "解锁必须展示 lock.open.fill")
        XCTAssertTrue(avatar.contains(".symbolEffect(.replace)"), "解锁必须使用 symbolEffect")

        // 13. Reduce Motion 对 Symbol 动效生效 (P2.8A: 静音状态改为 controller 单一来源)
        XCTAssertTrue(call.contains("guard !viewModel.controller.isMuted, !reduceMotion"),
                      "麦克风 pulse 必须受 Reduce Motion 与 controller 静音状态控制")
        XCTAssertTrue(avatar.contains("reduceMotion"), "头像解锁动效必须遵循 Reduce Motion")

        // 14. 本轮禁止新增的模式
        for token in ["MeshGradient", "KeyframeAnimator", "TimelineView", "CADisplayLink"] {
            XCTAssertFalse(home.contains(token), "首页不得新增 \(token)")
            XCTAssertFalse(characters.contains(token), "角色页不得新增 \(token)")
            XCTAssertFalse(call.contains(token), "通话页不得新增 \(token)")
            XCTAssertFalse(avatar.contains(token), "头像组件不得新增 \(token)")
        }

        // 15. Widget / Live Activity 契约保留 (P2.6K-FIX-1)
        let widget = try source("XiaomaoAppWidgets/CallLiveActivityView.swift")
        XCTAssertTrue(widget.contains("updateWaveTimer(isActive: Bool)"), "Widget 波形契约必须保留")

        // 16. P2.6H-K 契约全部保留 (P2.7B: 头像契约更新为 portrait heroSize 220)
        XCTAssertTrue(call.contains("appeared = true"), "P2.6H: appeared = true 必须保留")
        XCTAssertTrue(call.contains("await Task.yield()"), "P2.6H: await Task.yield() 必须保留")
        XCTAssertTrue(call.contains("private let heroSize: CGFloat = 220"), "P2.7B: heroSize 220 必须保留")
        XCTAssertTrue(call.contains("variant: .xiaomao"), "P2.7B: 通话主视觉必须使用生产角色")
        XCTAssertTrue(call.contains("finishCall(closePage:"), "P2.6B: finishCall(closePage:) 必须保留")
        XCTAssertTrue(call.contains("productionRole.displayName"), "P2.6D: productionRole.displayName 必须保留")
        XCTAssertTrue(call.contains("callStatusText"), "P2.6J: callStatusText 必须保留")
        XCTAssertTrue(call.contains("callStatusColor"), "P2.6K: callStatusColor 必须保留")
        XCTAssertTrue(home.contains("overlay(alignment: .top)"), "Toast 必须锚定 CTA 上方")
        // P2.8A: 角色页 1.0 单正式卡 (大尺寸人物), 不再要求多角色 224 小卡
        XCTAssertTrue(characters.contains("PrivacyAvatar("), "角色卡必须保留 PrivacyAvatar 人物")
    }

    // MARK: P2.7A-FIX-1 头像解锁作用域与 iOS 26 Simulator 契约

    func testP27AUnlockAndSimulatorFixContract() throws {
        let avatar = try source("XiaomaoApp/Design/Components/PrivacyAvatar.swift")
        let ci = try source(".github/workflows/ios-ci.yml")

        // 头像解锁必须绑定到刚点击的本地实例
        XCTAssertTrue(avatar.contains("@State private var requestedUnlock = false"))
        XCTAssertTrue(avatar.contains("if !revealed || requestedUnlock || unlockFlash"))
        XCTAssertTrue(avatar.contains("guard newValue, requestedUnlock, tappable else"),
                      "动画必须同时要求全局解锁、本地请求和可点击")

        let requestRange = try XCTUnwrap(avatar.range(of: "requestedUnlock = true"))
        let tapRange = try XCTUnwrap(avatar.range(of: "onTap?()", range: requestRange.lowerBound..<avatar.endIndex))
        XCTAssertLessThan(requestRange.lowerBound, tapRange.lowerBound,
                          "点击时必须先标记本头像，再通知父视图")

        // Reduce Motion 必须立即移除遮罩，只有普通分支创建短暂 Task
        let openingBrace = String(UnicodeScalar(123)!)
        let reduceStart = try XCTUnwrap(avatar.range(of: "if reduceMotion " + openingBrace))
        let taskStart = try XCTUnwrap(avatar.range(of: "unlockTask = Task", range: reduceStart.lowerBound..<avatar.endIndex))
        let reduceBranch = String(avatar[reduceStart.lowerBound..<taskStart.lowerBound])
        XCTAssertFalse(reduceBranch.contains("Task.sleep"), "Reduce Motion 分支不得等待")
        XCTAssertTrue(reduceBranch.contains("unlockFlash = false"))
        XCTAssertTrue(reduceBranch.contains("requestedUnlock = false"))
        XCTAssertEqual(avatar.components(separatedBy: "unlockTask = Task").count - 1, 1,
                       "只有非 Reduce Motion 分支可以创建短暂 Task")
        XCTAssertTrue(avatar.contains("Task.sleep(for: .milliseconds(450))"))

        // Task 与本地请求必须在离场时清理
        XCTAssertTrue(avatar.contains(".onDisappear " + openingBrace + "\n            unlockTask?.cancel()\n            unlockTask = nil\n            requestedUnlock = false"))

        // 已解锁时临时图标不再朗读锁定提示；既有图标、过渡、命中和 identifier 保留
        XCTAssertTrue(avatar.contains(".accessibilityHidden(revealed)"))
        XCTAssertTrue(avatar.contains("lock.fill"))
        XCTAssertTrue(avatar.contains("lock.open.fill"))
        XCTAssertTrue(avatar.contains(".contentTransition(.symbolEffect(.replace))"))
        XCTAssertTrue(avatar.contains(".allowsHitTesting(tappable)"))
        XCTAssertTrue(avatar.contains("avatar.locked"))
        XCTAssertTrue(avatar.contains("avatar.revealed"))

        // Simulator 只从最高可用 iOS 26.x runtime 中选择可用 iPhone
        XCTAssertTrue(ci.contains("version[0] != 26"))
        XCTAssertTrue(ci.contains("device.get(\"isAvailable\") is True"))
        XCTAssertTrue(ci.contains("name.startswith(\"iPhone\")"))
        XCTAssertTrue(ci.contains("max(candidates, key=lambda item: item[0])"))
        XCTAssertTrue(ci.contains("echo \"udid=${DEVICE_UDID}\" >> \"$GITHUB_OUTPUT\""))
        XCTAssertTrue(ci.contains("xcrun simctl bootstatus \"$DEVICE_UDID\" -b"))
        XCTAssertTrue(ci.contains("steps.simulator.outputs.udid"))
        XCTAssertTrue(ci.contains("-destination 'platform=iOS Simulator,id=${{ steps.simulator.outputs.udid }}'"))
        XCTAssertFalse(ci.contains("platform=iOS Simulator,OS=26.0"))
        XCTAssertNil(ci.range(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
                                  options: .regularExpression),
                     "workflow 不得硬编码具体 Simulator UDID")

        // Xcode 26 与 SDK 26 门禁保持不变
        XCTAssertTrue(ci.contains("Xcode_26*.app"))
        XCTAssertTrue(ci.contains("\"Xcode 26\"*)"))
        XCTAssertTrue(ci.contains("show-sdk-version"))
        XCTAssertTrue(ci.contains("26*)"))
    }

    // MARK: P2.7B-FINAL-MESH 有机渐变背景契约

    func testP27BOrganicMeshBackgroundContract() throws {
        let component = try source("XiaomaoApp/Design/Components/OrganicMeshBackground.swift")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        let theme = try source("XiaomaoApp/Design/Theme.swift")
        let avatar = try source("XiaomaoApp/Design/Components/PrivacyAvatar.swift")

        // ===== 公共组件 =====
        XCTAssertTrue(component.contains("struct OrganicMeshBackground"), "必须存在 OrganicMeshBackground 组件")
        XCTAssertTrue(component.contains("case home"), "必须提供 .home 模式")
        XCTAssertTrue(component.contains("case call"), "必须提供 .call 模式")
        XCTAssertTrue(component.contains("MeshGradient"), "必须使用 MeshGradient")
        XCTAssertTrue(component.contains("KeyframeAnimator"), "必须使用 KeyframeAnimator")
        XCTAssertTrue(component.contains("width: 3"), "必须使用 3×3 网格")
        XCTAssertTrue(component.contains("height: 3"), "必须使用 3×3 网格")
        XCTAssertTrue(component.contains("accessibilityReduceMotion"), "必须观察 Reduce Motion")
        XCTAssertTrue(component.contains("staticMesh"), "Reduce Motion 必须有独立静态分支")
        XCTAssertTrue(component.contains("animatedMesh"), "必须存在动画分支")

        // 禁止实现
        for token in ["Timer", "TimelineView", "Canvas", "CADisplayLink", "random", "DispatchSourceTimer"] {
            XCTAssertFalse(component.contains(token), "OrganicMeshBackground 不得包含: \(token)")
        }

        // ===== 主题令牌 (≤4 个 mesh 令牌) =====
        for token in ["meshWarmWhite", "meshPeach", "meshRose", "meshCoolAccent"] {
            XCTAssertTrue(theme.contains(token), "Theme 必须包含 mesh 令牌: \(token)")
        }

        // ===== 首页 =====
        XCTAssertTrue(home.contains("OrganicMeshBackground(mode: .home)"), "首页必须使用 .home Mesh 背景")
        // 删除旧循环光效
        for token in ["bgLightPulse", "sweepAngle", "ctaPulse"] {
            XCTAssertFalse(home.contains(token), "首页不得保留: \(token)")
        }
        // CTA 继续保留
        XCTAssertTrue(home.contains(".glassEffect("), "首页 CTA 必须使用 glassEffect")
        XCTAssertTrue(home.contains(".interactive()"), "首页 CTA 必须交互玻璃")
        XCTAssertTrue(home.contains("PressableButtonStyle"), "首页 CTA 必须保留按压样式")
        XCTAssertTrue(home.contains("home.start"), "首页 CTA identifier 必须保留")
        // 行为保留
        XCTAssertTrue(home.contains("openSettings()"), "设置入口必须保留")
        XCTAssertTrue(home.contains("openHistory()"), "回顾入口必须保留")
        XCTAssertTrue(home.contains("isProductionVoice"), "非生产角色门禁必须保留")
        XCTAssertTrue(home.contains("当前版本暂不展示聊天或录音历史"), "诚实空状态文案必须保留")
        XCTAssertTrue(home.contains("AvatarPrivacyConfirmView"), "隐私确认 Sheet 必须保留")

        // ===== 通话页 =====
        XCTAssertTrue(call.contains("OrganicMeshBackground(mode: .call)"), "通话页必须使用 .call Mesh 背景")
        XCTAssertFalse(call.contains("breathingGradientGlow"), "通话页不得保留背景循环呼吸")
        XCTAssertTrue(call.contains("直接说话就好，小猫在听"), "免按键提示必须保留")
        XCTAssertTrue(call.contains("callStatusText"), "状态文案必须保留")
        XCTAssertTrue(call.contains("callStatusColor"), "状态颜色必须保留")
        XCTAssertTrue(call.contains("GlassEffectContainer"), "玻璃控制区必须保留")
        XCTAssertTrue(call.contains(".symbolEffect(.pulse"), "麦克风 pulse 必须保留")
        XCTAssertTrue(call.contains("finishCall(closePage: false)"), "统一结束路径必须保留")
        XCTAssertTrue(call.contains("await Task.yield()"), "P2.6H 渲染让步必须保留")
        XCTAssertTrue(call.contains("await viewModel.appear()"), "真实连接流程必须保留")
        XCTAssertTrue(call.contains("productionRole.displayName"), "生产角色 Live Activity 必须保留")
        XCTAssertTrue(call.contains("showDiagnostics"), "诊断能力必须保留")
        XCTAssertTrue(call.contains("onLongPressGesture"), "长按诊断入口必须保留")
        XCTAssertTrue(call.contains("heroSize: CGFloat = 220"), "通话主视觉 heroSize 220 必须保留")

        // ===== 边界 =====
        // PrivacyAvatar 本轮未修改 (git 层面验证在 diff 检查; 这里验证其仍为 P2.7B 结构)
        XCTAssertTrue(avatar.contains("AvatarStyle"), "PrivacyAvatar 结构必须保持 P2.7B 状态")
    }

    // MARK: P2.7B-FINAL-IDLE 空闲弹窗 UI 契约

    func testP27BIdleNoticesContract() throws {
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        let controller = try source("XiaomaoApp/Voice/VoiceSessionController.swift")

        // ===== 控制器产品状态 =====
        XCTAssertTrue(controller.contains("idleWarningRemainingSeconds"), "控制器必须暴露空闲预警剩余秒数")
        XCTAssertTrue(controller.contains("idleTimeoutEnded"), "控制器必须暴露空闲结束状态")
        XCTAssertTrue(controller.contains("idleWarningRemainingSeconds = nil"), "新通话必须重置空闲预警")
        XCTAssertTrue(controller.contains("idleTimeoutEnded = false"), "新通话必须重置空闲结束状态")
        XCTAssertTrue(controller.contains("vad_state"), "必须保留 VAD 活动上报")

        // ===== 预警弹窗文案 =====
        XCTAssertTrue(call.contains("小猫还在等你"), "预警弹窗标题必须存在")
        XCTAssertTrue(call.contains("再说句话就能继续"), "预警弹窗正文必须存在")
        XCTAssertTrue(call.contains("继续聊"), "预警主按钮必须存在")
        XCTAssertTrue(call.contains("结束通话"), "预警次按钮必须存在")
        XCTAssertTrue(call.contains("idleWarningRemainingSeconds ?? 30"), "剩余秒数必须来自服务端状态")

        // ===== 自动结束弹窗 =====
        XCTAssertTrue(call.contains("通话已暂时结束"), "自动结束弹窗标题必须存在")
        XCTAssertTrue(call.contains("一段时间没有听到你的声音"), "自动结束正文必须存在")
        XCTAssertTrue(call.contains("回到首页"), "自动结束按钮必须存在")

        // ===== 五个 accessibility identifiers =====
        for ident in ["idle.warning.overlay", "idle.warning.continue", "idle.warning.end",
                      "idle.ended.overlay", "idle.ended.home"] {
            XCTAssertTrue(call.contains(ident), "缺少 accessibility identifier: \(ident)")
        }

        // ===== 交互与视觉约束 =====
        // 预警不使用危险红色 (主按钮为西柚玫瑰, 非 danger)
        XCTAssertFalse(call.contains("Theme.danger, in: Capsule()\n                        .frame(maxWidth: .infinity)\n                            .frame(height: 48)\n                            .background(Theme.danger"),
                       "预警弹窗不得使用危险红色样式")
        // 最终按钮调用 finishCall()
        XCTAssertTrue(call.contains("finishCall()"), "弹窗按钮必须调用 finishCall()")
        // 结束 Live Activity + 恢复屏幕常亮
        XCTAssertTrue(call.contains("CallLiveActivityManager.shared.end()"), "空闲结束必须结束 Live Activity")
        XCTAssertTrue(call.contains("UIApplication.shared.isIdleTimerDisabled = false"), "空闲结束必须恢复屏幕常亮")
        // 不新增 Timer / 本地倒计时 (isIdleTimerDisabled 是系统常亮调用, 不在此列)
        XCTAssertFalse(call.contains("Timer.scheduledTimer"), "弹窗不得新增 Timer.scheduledTimer")
        XCTAssertFalse(call.contains("countdown"), "弹窗不得新增本地倒计时")
        XCTAssertFalse(call.contains("startIdleCountdown"), "不得新增本地 idle 秒数计时")
        // 不提供同页重新开始按钮
        XCTAssertFalse(call.contains("重新开始"), "空闲结束弹窗不得提供同页重新开始按钮")

        // ===== 既有通话核心契约保留 =====
        XCTAssertTrue(call.contains("OrganicMeshBackground(mode: .call)"), "Mesh 背景必须保留")
        XCTAssertTrue(call.contains("直接说话就好，小猫在听"), "免按键提示必须保留")
        XCTAssertTrue(call.contains("finishCall(closePage: false)"), "统一结束路径必须保留")
        XCTAssertTrue(call.contains("await Task.yield()"), "P2.6H 渲染让步必须保留")
        XCTAssertTrue(call.contains("await viewModel.appear()"), "真实连接流程必须保留")
        XCTAssertTrue(call.contains("GlassEffectContainer"), "玻璃控制区必须保留")
        XCTAssertTrue(call.contains(".symbolEffect(.pulse"), "麦克风 pulse 必须保留")
        XCTAssertTrue(call.contains("showDiagnostics"), "诊断能力必须保留")
        XCTAssertTrue(call.contains("onLongPressGesture"), "长按诊断入口必须保留")
    }

    // MARK: P2.7B-FINAL-IDLE-FIX overlay 优先级与浮层清理契约

    func testP27BIdleOverlayPriorityAndCleanupContract() throws {
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")

        // ===== 单一 overlay 优先级链: 空闲结束 > 空闲预警 > 挂断确认 > 共情卡 =====
        // (定位首处 .overlay 修饰符; 字符串不携带花括号以避免静态 brace 计数误报)
        guard let overlayStart = call.range(of: ".overlay")?.lowerBound else {
            XCTFail("必须存在 overlay 块")
            return
        }
        let overlayBody = String(call[overlayStart..<call.endIndex])

        // 四个分支按优先级互斥排列 (if / else if 链)
        let orderTokens = [
            ("idleTimeoutEnded", "空闲结束"),
            ("idleWarningRemainingSeconds != nil", "空闲预警"),
            ("showHangupConfirm", "挂断确认"),
            ("showEmpathy", "共情卡"),
        ]
        var lastIndex: String.Index = overlayBody.startIndex
        for (token, label) in orderTokens {
            guard let idx = overlayBody.range(of: token)?.lowerBound else {
                XCTFail("overlay 链缺少分支: \(label) (\(token))")
                return
            }
            XCTAssertGreaterThan(idx, lastIndex, "overlay 链顺序错误: \(label) 必须位于前面分支之后")
            lastIndex = idx
        }

        // ===== 恒真 onChange 已修正 =====
        XCTAssertFalse(call.contains("newValue == nil || newValue != nil"),
                       "不得保留恒真条件 newValue == nil || newValue != nil")
        XCTAssertTrue(call.contains("if newValue != nil"),
                      "onChange 必须仅在非 nil (新一轮预警) 时复位本地抑制")

        // ===== 预警背景不响应点击关闭 =====
        guard let warningStart = call.range(of: "private var idleWarningOverlay")?.lowerBound,
              let warningEnd = call.range(of: "private var idleEndedOverlay")?.lowerBound else {
            XCTFail("缺少 idleWarningOverlay / idleEndedOverlay")
            return
        }
        let warningBody = String(call[warningStart..<warningEnd])
        XCTAssertTrue(warningBody.contains("Color.black.opacity(0.12)"), "预警半透明背景必须存在")
        XCTAssertFalse(warningBody.contains(".onTapGesture"),
                       "预警背景不得响应点击关闭 (只能通过按钮或真实语音恢复关闭)")

        // ===== 空闲结束时清理其他通话浮层 =====
        guard let endedStart = call.range(of: "onChange(of: viewModel.controller.idleTimeoutEnded)")?.lowerBound,
              let endedEnd = call.range(of: ".task", options: [], range: endedStart..<call.endIndex)?.lowerBound else {
            XCTFail("缺少 idleTimeoutEnded onChange")
            return
        }
        let endedBody = String(call[endedStart..<endedEnd])
        XCTAssertTrue(endedBody.contains("showHangupConfirm = false"), "空闲结束必须清理挂断确认")
        XCTAssertTrue(endedBody.contains("showEmpathy = false"), "空闲结束必须清理共情卡")
        XCTAssertTrue(endedBody.contains("emotionBubbleVisible = false"), "空闲结束必须清理情绪气泡")
        XCTAssertTrue(endedBody.contains("idleWarningDismissed = false"), "空闲结束必须复位本地抑制")
        XCTAssertTrue(endedBody.contains("CallLiveActivityManager.shared.end()"), "空闲结束必须结束 Live Activity")
        XCTAssertTrue(endedBody.contains("UIApplication.shared.isIdleTimerDisabled = false"), "空闲结束必须恢复屏幕常亮")
    }

    // MARK: P2.7B-FINAL-VISUAL-FIX 人物/Mesh/首页/通话/FINAL-IDLE 契约

    func testP27BFinalVisualFixContract() throws {
        let avatar = try source("XiaomaoApp/Design/Components/PrivacyAvatar.swift")
        let mesh = try source("XiaomaoApp/Design/Components/OrganicMeshBackground.swift")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        let controller = try source("XiaomaoApp/Voice/VoiceSessionController.swift")

        // ===== 1. 人物 (限定 portraitCharacter 范围) =====
        guard let pStart = avatar.range(of: "private func portraitCharacter")?.lowerBound,
              let pEnd = avatar.range(of: "// MARK: - Thumbnail")?.lowerBound else {
            XCTFail("缺少 portraitCharacter 或 Thumbnail 范围")
            return
        }
        let portrait = String(avatar[pStart..<pEnd])
        XCTAssertTrue(portrait.contains("Image(\"Character\")"), "portraitCharacter 必须保留 Image(\"Character\")")
        XCTAssertTrue(portrait.contains("LinearGradient"), "portraitCharacter 必须保留底部渐隐 LinearGradient mask")
        XCTAssertTrue(portrait.contains(".blur(radius: revealed"), "portraitCharacter 必须保留 reveal blur")
        XCTAssertTrue(portrait.contains(".opacity(revealed"), "portraitCharacter 必须保留 reveal opacity")
        XCTAssertTrue(portrait.contains(".mask"), "portraitCharacter 必须保留 mask")
        XCTAssertTrue(portrait.contains(".animation(.easeInOut(duration: 0.35), value: revealed)"),
                      "portraitCharacter 必须保留 reveal 动画")
        // portraitCharacter 范围内不得含 plus-lighter blend (全尺寸叠光已删)
        XCTAssertFalse(portrait.contains(".blendMode(.plusLighter)"),
                       "portraitCharacter 不得含 blendMode(.plusLighter) (全尺寸叠光已删除)")
        // avatar.locked / avatar.revealed 仍存在
        XCTAssertTrue(avatar.contains("avatar.locked"), "PrivacyAvatar 必须保留 avatar.locked identifier")
        XCTAssertTrue(avatar.contains("avatar.revealed"), "PrivacyAvatar 必须保留 avatar.revealed identifier")

        // ===== 2. Mesh 组件 =====
        XCTAssertTrue(mesh.contains("MeshGradient"), "Mesh 组件必须保留 MeshGradient")
        XCTAssertTrue(mesh.contains("KeyframeAnimator"), "Mesh 组件必须保留 KeyframeAnimator")
        XCTAssertTrue(mesh.contains("width: 3"), "Mesh 组件必须保留 3×3 网格 width: 3")
        XCTAssertTrue(mesh.contains("height: 3"), "Mesh 组件必须保留 3×3 网格 height: 3")
        XCTAssertTrue(mesh.contains("staticMesh"), "Reduce Motion 静态分支必须保留")
        XCTAssertTrue(mesh.contains("Color.white.opacity(0.14)"), "浅色 veil 必须为 0.14 (淡化色块边界)")
        // MeshMotion 实际属性: 不含 glowOpacity (范围化, 不搜索普通注释)
        guard let mmStart = mesh.range(of: "private struct MeshMotion")?.lowerBound,
              let mmEnd = mesh.range(of: "var body: some View")?.lowerBound else {
            XCTFail("缺少 MeshMotion 结构体范围")
            return
        }
        let meshMotionBody = String(mesh[mmStart..<mmEnd])
        XCTAssertFalse(meshMotionBody.contains("glowOpacity"),
                       "MeshMotion 结构体不得含 glowOpacity 属性 (已删除, 无渲染意义)")
        // KeyframeAnimator 实际 KeyframeTrack: 不含 glowOpacity track (范围化)
        guard let animStart = mesh.range(of: "KeyframeAnimator(initialValue:")?.lowerBound else {
            XCTFail("缺少 KeyframeAnimator 范围")
            return
        }
        let animatorBlock = String(mesh[animStart..<mesh.endIndex])
        XCTAssertFalse(animatorBlock.contains("glowOpacity"),
                       "KeyframeAnimator 不得含 glowOpacity KeyframeTrack (已删除, 无渲染意义)")
        // 禁止实现扫描
        for token in ["Timer", "TimelineView", "Canvas", "CADisplayLink",
                      "DispatchSourceTimer", "random"] {
            XCTAssertFalse(mesh.contains(token), "OrganicMeshBackground 不得包含: \(token)")
        }

        // ===== 2b. 颜色数组 (分别截取 .home / .call 范围) =====
        guard let homeStart = mesh.range(of: "case .home:")?.lowerBound,
              let homeEnd = mesh.range(of: "case .call:")?.lowerBound else {
            XCTFail("缺少 .home / .case 范围")
            return
        }
        let homeColors = String(mesh[homeStart..<homeEnd])
        let callColors = String(mesh[homeEnd..<mesh.endIndex])
        // Rose 恰好 1 次, CoolAccent 恰好 1 次
        XCTAssertEqual(homeColors.components(separatedBy: "meshRose").count - 1, 1, "Home 颜色数组 meshRose 必须恰好 1 次")
        XCTAssertEqual(homeColors.components(separatedBy: "meshCoolAccent").count - 1, 1, "Home 颜色数组 meshCoolAccent 必须恰好 1 次")
        XCTAssertEqual(callColors.components(separatedBy: "meshRose").count - 1, 1, "Call 颜色数组 meshRose 必须恰好 1 次")
        XCTAssertEqual(callColors.components(separatedBy: "meshCoolAccent").count - 1, 1, "Call 颜色数组 meshCoolAccent 必须恰好 1 次")

        // ===== 3. 首页 topBar (限定 topBar 范围) =====
        guard let tbStart = home.range(of: "private var topBar")?.lowerBound,
              let tbEnd = home.range(of: "// MARK: 本地轻提示")?.lowerBound else {
            XCTFail("缺少 topBar / 本地轻提示 范围")
            return
        }
        let topBar = String(home[tbStart..<tbEnd])
        // 顶栏内部不得含固定 Text(\"在呢\")
        XCTAssertFalse(topBar.contains("Text(\"在呢\")"), "topBar 不得含固定 Text(\"在呢\") 胶囊")
        // 顶栏内部不得含透明 Color.clear 占位
        XCTAssertFalse(topBar.contains("Color.clear"), "topBar 不得含 Color.clear 占位")
        // 顶栏必须保留设置入口与 home.settings identifier
        XCTAssertTrue(topBar.contains("openSettings()"), "topBar 必须保留 openSettings()")
        XCTAssertTrue(topBar.contains("home.settings"), "topBar 必须保留 home.settings identifier")
        // 顶栏必须保留齿轮 40×40 触控区域
        XCTAssertTrue(topBar.contains("width: 40, height: 40"), "topBar 必须保留 40×40 触控区域")

        // ===== 3b. 首页主体层级 (全文件) =====
        XCTAssertTrue(home.contains("正在陪你"), "首页主体必须保留\"正在陪你\"")
        XCTAssertTrue(home.contains("greetings"), "问候数组必须保留")
        XCTAssertTrue(home.contains("OrganicMeshBackground(mode: .home)"), "首页必须使用 OrganicMeshBackground(mode: .home)")
        // CTA / 历史入口 / 隐私确认
        XCTAssertTrue(home.contains(".glassEffect("), "首页 CTA 必须保留 glassEffect")
        XCTAssertTrue(home.contains("interactive()"), "首页 CTA 必须保留 interactive")
        XCTAssertTrue(home.contains("home.start"), "首页 CTA identifier 必须保留")
        XCTAssertTrue(home.contains("openHistory()"), "首页历史入口必须保留")
        XCTAssertTrue(home.contains("AvatarPrivacyConfirmView"), "隐私确认流程必须保留")

        // ===== 4. 通话文本 (displayConversationText) =====
        XCTAssertTrue(call.contains("private var displayConversationText: String?"),
                      "通话页必须存在 displayConversationText 计算属性")
        XCTAssertTrue(call.contains("responseText.isEmpty"),
                      "displayConversationText 必须在 responseText 空时使用 transcript")
        XCTAssertTrue(call.contains("trimmingCharacters(in: .whitespacesAndNewlines)"),
                      "displayConversationText 必须使用 trimmingCharacters")
        XCTAssertTrue(call.contains("CharacterSet.letters"),
                      "displayConversationText 必须判断字母")
        XCTAssertTrue(call.contains("CharacterSet.decimalDigits"),
                      "displayConversationText 必须判断数字")
        XCTAssertTrue(call.contains("isEmoji") || call.contains("isEmojiPresentation"),
                      "displayConversationText 必须支持 Emoji")
        // 控制器字段保持原始, UI 不直接渲染 responseText/transcript 文本块
        XCTAssertTrue(controller.contains("responseText"), "控制器 responseText 字段保留")
        XCTAssertTrue(controller.contains("transcript"), "控制器 transcript 字段保留")
        XCTAssertFalse(call.contains("if !viewModel.controller.responseText.isEmpty"),
                       "通话页不再直接 if/else responseText/transcript, 统一走 displayConversationText")
        XCTAssertTrue(call.contains("displayConversationText"), "UI 必须通过 displayConversationText 展示会话文字")
        XCTAssertTrue(call.contains(".lineLimit(2)"), "lineLimit 2 必须保留")

        // ===== 5. FINAL-IDLE 契约不退回 (来自上一轮) =====
        XCTAssertTrue(call.contains("idleTimeoutEnded"), "idleTimeoutEnded 契约必须保留")
        XCTAssertTrue(call.contains("idleWarningRemainingSeconds"), "idleWarningRemainingSeconds 契约必须保留")
        XCTAssertTrue(call.contains("idleEndedOverlay"), "idleEndedOverlay 必须保留")
        XCTAssertTrue(call.contains("idleWarningOverlay"), "idleWarningOverlay 必须保留")
        XCTAssertTrue(call.contains("idle.warning.overlay"), "idle.warning.overlay identifier 必须保留")
        XCTAssertTrue(call.contains("idle.ended.overlay"), "idle.ended.overlay identifier 必须保留")
        // 单一 overlay 优先级链
        XCTAssertTrue(call.contains("if viewModel.controller.idleTimeoutEnded"),
                      "Overlay 优先级链: idle 结束必须在前")
        XCTAssertTrue(call.contains("if viewModel.controller.idleWarningRemainingSeconds != nil"),
                      "Overlay 优先级链: idle 预警必须第二")
        XCTAssertTrue(call.contains("showHangupConfirm = false"), "空闲结束必须清理挂断确认")
        XCTAssertTrue(call.contains("showEmpathy = false"), "空闲结束必须清理共情卡")
        XCTAssertTrue(call.contains("emotionBubbleVisible = false"), "空闲结束必须清理情绪气泡")
        XCTAssertTrue(call.contains("CallLiveActivityManager.shared.end()"), "空闲结束必须结束 Live Activity")
        // 控制器 idle 字段 + 重置
        XCTAssertTrue(controller.contains("idleWarningRemainingSeconds = nil"),
                      "新通话必须重置 idleWarningRemainingSeconds")
        XCTAssertTrue(controller.contains("idleTimeoutEnded = false"),
                      "新通话必须重置 idleTimeoutEnded")
    }

    // MARK: P2.8A V1 稳定化契约

    func testV10CallStabilizationContract() throws {
        let app = try source("XiaomaoApp/App/XiaomaoApp.swift")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")
        let controller = try source("XiaomaoApp/Voice/VoiceSessionController.swift")
        let character = try source("XiaomaoApp/App/CharacterSelectView.swift")

        // ===== 1. 通话启动: 单次门禁 + 无人工延迟 =====
        XCTAssertTrue(app.contains("private func requestCall"), "必须存在单次启动门禁 requestCall()")
        XCTAssertTrue(app.contains("guard !activeCall else { return }"),
                      "activeCall 已为 true 时直接返回, 不得重复创建 VoiceCallView")
        XCTAssertFalse(app.contains("asyncAfter"), "不得使用人工启动延迟")
        XCTAssertFalse(app.contains("DispatchQueue.asyncAfter"), "不得使用 asyncAfter 延迟")
        // ViewModel 启动幂等
        XCTAssertTrue(app.contains("startCall: { requestCall() }"), "首页与角色页共用 requestCall 门禁")
        XCTAssertTrue(call.contains("private func finishCall"), "finishCall 单一 teardown 保留")
        XCTAssertTrue(controller.contains("state == .ready || state == .listening || state == .speaking"),
                      ".listening 必须被允许恢复采集")

        // ===== 2. 首次连接加载反馈 =====
        XCTAssertTrue(call.contains("call.connecting"), "必须存在 call.connecting identifier")
        XCTAssertTrue(call.contains("ProgressView"), "连接卡必须包含 ProgressView")
        XCTAssertTrue(call.contains("正在连接小猫"), "必须存在首次连接文案 正在连接小猫")
        XCTAssertTrue(call.contains("通常只需要几秒"), "必须存在首次连接说明文案")
        XCTAssertFalse(call.contains("DispatchSourceTimer"), "连接反馈不得使用定时器")

        // ===== 3. 静音: 单一来源 =====
        XCTAssertFalse(call.contains("@State private var muted"), "VoiceCallView 不得再声明本地 muted")
        XCTAssertTrue(call.contains("viewModel.controller.isMuted"), "UI 必须统一读取 controller.isMuted")

        // ===== 4. 波形: 真实 level 驱动 (限定 VoiceWaveform 范围, 避免命中共情卡 randomManual) =====
        XCTAssertTrue(call.contains("level: viewModel.controller.vadNormalizedRMS"),
                      "波形必须接收真实 vadNormalizedRMS")
        XCTAssertTrue(call.contains("let level: Double"), "VoiceWaveform 必须声明真实 level")
        XCTAssertTrue(call.contains("min(max(level"), "波形柱高必须钳制上下限")
        guard let waveStart = call.range(of: "struct VoiceWaveform: View")?.lowerBound else {
            XCTFail("缺少 VoiceWaveform 范围")
            return
        }
        let waveformBlock = String(call[waveStart..<call.endIndex])
        XCTAssertFalse(waveformBlock.contains("TimelineView"), "波形不得使用 TimelineView")
        XCTAssertFalse(waveformBlock.contains("CADisplayLink"), "波形不得使用 CADisplayLink")
        XCTAssertFalse(waveformBlock.contains("random"), "波形不得使用随机数")
        XCTAssertFalse(waveformBlock.contains("Timer"), "波形不得使用 Timer")

        // ===== 5. 退出: 左上结束确认 (P2.8A-CI-FIX: 从 topStart 之后找明确边界, 避免命中文件头 MARK) =====
        guard let topStart = call.range(of: "private var topBar")?.lowerBound,
              let topEnd = call.range(of: "// MARK: 状态行", range: topStart..<call.endIndex)?.lowerBound,
              topEnd > topStart else {
            XCTFail("缺少 topBar 范围")
            return
        }
        let topBar = String(call[topStart..<topEnd])
        XCTAssertTrue(topBar.contains("xmark"), "左上按钮必须使用 xmark 图标")
        XCTAssertTrue(topBar.contains("showHangupConfirm = true"), "左上点击必须显示挂断确认")
        XCTAssertFalse(topBar.contains("finishCall()"), "左上按钮不得直接调用 finishCall()")
        XCTAssertTrue(topBar.contains("call.close"), "call.close identifier 必须保留")
        XCTAssertTrue(topBar.contains("结束通话"), "左上 accessibility label 必须为 结束通话")

        // ===== 6. 聊天提示 (换话题降级, 限定控制区范围避免命中历史注释) =====
        guard let ctlStart = call.range(of: "private var controlArea")?.lowerBound else {
            XCTFail("缺少 controlArea 范围")
            return
        }
        let controlBlock = String(call[ctlStart..<call.endIndex])
        XCTAssertTrue(controlBlock.contains("聊天提示"), "页面必须包含 聊天提示 标签")
        XCTAssertTrue(controlBlock.contains("换个提示"), "按钮标题必须为 换个提示")
        XCTAssertFalse(controlBlock.contains("换话题"), "控制区不得再显示 换话题")
        XCTAssertTrue(controlBlock.contains("更换一个聊天提示"), "必须提供 accessibility hint 更换一个聊天提示")
        XCTAssertTrue(controlBlock.contains("call.topic"), "call.topic identifier 保留")

        // ===== 7. 角色页 1.0 收口 =====
        XCTAssertFalse(character.contains("CompanionPreviewRole.allCases"), "角色页不得遍历 allCases")
        XCTAssertFalse(character.contains("jealousTarget"), "角色页不得触发吃醋彩蛋")
        XCTAssertFalse(character.contains("jealousTapCount"), "角色页不得保留吃醋计数")
        XCTAssertFalse(character.contains("仅预览"), "角色页不得有 仅预览 死按钮")
        XCTAssertTrue(character.contains("当前陪伴角色"), "角色页标题必须为 当前陪伴角色")
        XCTAssertTrue(character.contains("更多角色正在准备中"), "角色页必须说明 更多角色正在准备中")
        XCTAssertTrue(character.contains("PrivacyAvatar"), "角色页必须保留 PrivacyAvatar")
        XCTAssertTrue(character.contains("characters.start"), "characters.start 必须保留")
        XCTAssertTrue(character.contains("AvatarPrivacyConfirmView"), "隐私确认 Sheet 必须保留")
        XCTAssertTrue(character.contains("开始聊天"), "角色页底部按钮必须为 开始聊天")
        XCTAssertTrue(character.contains("roleStore.previewRole = .xiaomao"),
                      "进入角色页必须回到小猫预览角色")
    }

}
