import SwiftUI

// MARK: - 共情卡模型 (P2.6F)
// 三类触发卡 (welcome / longCall / reconnect) + 四张手动彩蛋卡
// 自动卡一律中性/陪伴式文案, 不推断真实情绪; 手动卡用提议式表达
// randomManual() 只能由「关心我」按钮调用

struct EmpathyCard {
    enum Kind {
        case welcome, longCall, reconnect, userRequest
    }

    let kind: Kind
    let label: String       // 顶部 chip
    let title: String       // 浮层大标题
    let body: String        // 正文
    let hugLine: String     // 抱抱卡标题
    let hugDetail: String   // 抱抱卡正文

    // MARK: 触发卡 — 中性陪伴文案

    /// 通话建立后 2.8s 展示 (中性, 不随机不推断)
    static let welcome = EmpathyCard(
        kind: .welcome,
        label: "小猫在这儿",
        title: "小猫在这儿",
        body: "想说什么都可以，慢慢来。",
        hugLine: "小猫在旁边陪着你",
        hugDetail: "不用急着说话，我在就好。"
    )

    /// 真实通话满 300s 后展示
    static let longCall = EmpathyCard(
        kind: .longCall,
        label: "已经聊了一会儿",
        title: "已经聊了一会儿",
        body: "要不要先喝口水？不着急，小猫等你。",
        hugLine: "先歇一下也没关系",
        hugDetail: "把手机放一放，小猫不会走。"
    )

    /// 真实重连次数 >= 2 后展示 (首次)
    static let reconnect = EmpathyCard(
        kind: .reconnect,
        label: "刚才网络有点抖",
        title: "刚才网络有点抖",
        body: "小猫还在，不用重新解释，我们接着聊。",
        hugLine: "小猫一直没走开",
        hugDetail: "网络缓过来了，我们继续。"
    )

    // MARK: 手动彩蛋卡 — 提议式表达 (只有「关心我」可触发)

    private static let manualCards: [EmpathyCard] = [
        EmpathyCard(
            kind: .userRequest,
            label: "要不要先歇一会儿",
            title: "要不要先歇一会儿",
            body: "聊了这么久，小猫陪你喝口水。",
            hugLine: "歇一下",
            hugDetail: "你舒服最重要。"
        ),
        EmpathyCard(
            kind: .userRequest,
            label: "今天也辛苦啦",
            title: "今天也辛苦啦",
            body: "不管今天发生了什么，到这里都可以先放下。",
            hugLine: "抱抱你",
            hugDetail: "今天做得够多了。"
        ),
        EmpathyCard(
            kind: .userRequest,
            label: "想不想要个抱抱",
            title: "想不想要个抱抱",
            body: "不需要理由，小猫随时都在。",
            hugLine: "给你一个抱抱",
            hugDetail: "抱抱不是敷衍，是想告诉你——你的感受，我收到了。"
        ),
        EmpathyCard(
            kind: .userRequest,
            label: "不想说也没关系",
            title: "不想说也没关系",
            body: "有些话可以留着，小猫不会追问。",
            hugLine: "安静陪着你",
            hugDetail: "不说话也很好。"
        )
    ]

    /// 随机手动卡 — 只允许「关心我」按钮调用
    static func randomManual() -> EmpathyCard {
        manualCards.randomElement() ?? manualCards[0]
    }
}
