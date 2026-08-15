import Foundation

/// 开场编排。
///
/// **从 PetHomeView.onAppear 抽出来的原因**：那里原来是 42 行混合体 ——
/// 视图配置、回调注册、业务时序（读天数 → 签到 → 结算 → 延时报账 →
/// 成就消息接续）挤在一起，还有两层嵌套的 `asyncAfter`。
/// 它是整个项目最难读的一段，而其中的时序逻辑和 SwiftUI 无关。
///
/// 抽出后 `onAppear` 只剩「装配」，时序在这里，且可以单独测。
///
/// ⚠️ **顺序有硬约束**，注释在各步骤上：
/// 读 `daysSinceLastSeen` 必须在 `markSeen()` 之前，
/// `settleRewards()` 必须在 `markSeen()` 之后。
@MainActor
struct OpeningSequence {

    /// 开场后多久开始说话。
    ///
    /// 留一点时间让场景渲染完、宠物站好，立刻弹气泡会显得突兀。
    static let greetDelay: TimeInterval = 0.9

    /// 第二条消息（成就）与第一条的间隔。
    ///
    /// 要大于台词气泡的默认停留时长，否则第一条还没消失就被顶掉。
    static let secondMessageDelay: TimeInterval = 6.5

    /// 开场要做的事，按顺序打包好。
    struct Plan {
        /// 距上次打开过了几天，用于「久别重逢」台词
        let absentDays: Int
        /// 结算结果。nil = 无收益
        let settlement: RewardSettlement?

        /// 要说的话。第一条立刻说，其余按 `secondMessageDelay` 间隔接续。
        ///
        /// 空数组表示「没有收益，该说日常问候」—— 调用方走台词系统，
        /// 因为问候语要经过 AI/预写台词的选择逻辑，不是固定文案。
        let messages: [String]

        var hasSettlementNews: Bool { !messages.isEmpty }
    }

    /// 跑一遍开场结算，产出待播报的内容。
    ///
    /// **只做数据，不碰 UI** —— 所以可以测。
    static func plan(store: PetStore) -> Plan {
        // 读 daysSinceLastSeen 必须在 markSeen 之前，否则永远是 0
        let absent = store.daysSinceLastSeen
        store.markSeen()
        // 结算要在 markSeen 之后 —— 连续天数会影响成就判定
        let settlement = store.settleRewards()

        let texts = (settlement?.messages ?? []).map {
            String(format: L($0.key), arguments: $0.args)
        }
        return Plan(absentDays: absent, settlement: settlement, messages: texts)
    }

    /// 按计划播报。
    ///
    /// - Parameters:
    ///   - plan: `plan(store:)` 的产出
    ///   - speak: 怎么说（通常是 `scene.showSpeech`）
    ///   - fallback: 没有收益时说什么（走台词系统，可能是 AI 生成）
    static func announce(_ plan: Plan,
                         speak: @escaping (String) -> Void,
                         fallback: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + greetDelay) {
            guard let first = plan.messages.first else {
                fallback()
                return
            }
            speak(first)

            // 后续消息依次接续。用 enumerated 而非嵌套 asyncAfter ——
            // 来只支持两条，第三条会被静默丢弃。
            for (i, text) in plan.messages.dropFirst().enumerated() {
                let delay = secondMessageDelay * Double(i + 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    speak(text)
                }
            }
        }
    }
}
