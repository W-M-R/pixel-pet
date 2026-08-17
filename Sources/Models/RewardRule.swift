import Foundation

/// 结算时的上下文快照。
struct RewardContext {
    let pet: PetState
    let wallet: PetWallet
    let now: Date

    /// 距上次结算的小时数
    let offlineHours: Double

    /// 离线期间的平均饱食与心情（各 0...1）。
    ///
    /// 分开传而不是先合成一个数 —— 合成规则属于奖励规则自己的职责，
    /// 不同规则可能想用不同权重（比如将来加「只看心情的奖励」）。
    ///
    /// **清洁不在这里**：72h 周期让它长期接近 1.0，放进收益公式只会
    /// 稀释另两维（离线 24h 时清洁还有 0.83，饱食只剩 0.17）。
    /// 它仍是照料内容 —— 状态条、台词、洗澡成就都保留，只是不折算成钱。
    let avgSatiety: Double
    let avgMood: Double

    /// 今日剩余收益额度。额度制的核心约束，由 `makeContext` 从钱包算出。
    let remainingCap: Int

    var claimed: Set<String> { wallet.claimedRewards }
}

/// 一次奖励的产出。
struct RewardOutcome {
    let coins: Int
    /// 宠物说什么（走台词气泡）
    let messageKey: String
    /// 消息的格式化参数
    let messageArgs: [CVarArg]

    init(coins: Int, messageKey: String, messageArgs: [CVarArg] = []) {
        self.coins = coins
        self.messageKey = messageKey
        self.messageArgs = messageArgs
    }
}

/// 一条奖励规则。
///
/// 设计目标：**加新奖励不改核心逻辑**。
/// 以后想加节日奖励、喂食连击、集齐毛色之类，只需实现这个协议并注册。
protocol RewardRule {
    /// 存档去重用的稳定 ID。
    /// ⚠️ **改了会导致一次性奖励重复发放**，定下来就不要动。
    var id: String { get }
    var nameKey: String { get }
    /// 一次性（成就）发过就不再发；周期性（上线/看家）每次都算
    var isOneTime: Bool { get }

    /// 是否计入每日额度。只有看家收益算，上线奖励和成就不算。
    var countsTowardDailyCap: Bool { get }

    /// 这条规则发钱时记什么原因。
    ///
    /// 由规则自己声明，而不是让 `PetStore` 按「占不占额度」反推 ——
    /// 之前上线奖励和成就被合并成一次 `recordBonus`，
    /// 账本里分不清那笔钱是签到还是成就。
    var coinReason: CoinReason { get }

    /// 返回 nil = 本次不触发
    func evaluate(_ ctx: RewardContext) -> RewardOutcome?
}

extension RewardRule {
    /// 默认不占额度 —— 只有 `OfflineCareReward` 覆写成 true。
    var countsTowardDailyCap: Bool { false }

    /// 默认按成就记账 —— 规则表里绝大多数是成就。
    var coinReason: CoinReason { .achievement }
}

/// 一次结算的结果。
struct RewardSettlement {
    let totalCoins: Int
    /// 其中计入每日额度的部分（看家收益）。
    /// 上线奖励与成就**不占额度** —— 它们是一次性/低频的，
    /// 让它们吃额度会挤掉当天的看家收入，玩家会觉得「领了成就反而少赚」。
    let cappedCoins: Int
    /// 新解锁的一次性奖励 ID，调用方要写进存档
    let newlyClaimed: [String]
    /// 要展示的消息（通常只展示第一条）
    let messages: [(key: String, args: [CVarArg])]

    /// 分项收入：`(原因, 金额, 规则 id)`。
    ///
    /// 让 `PetStore` 能逐笔入账，账本里就能区分签到 / 成就 / 看家。
    /// `totalCoins` 与 `cappedCoins` 保留 —— UI 只关心总数。
    let payouts: [(reason: CoinReason, coins: Int, ruleID: String)]

    var isEmpty: Bool { totalCoins == 0 && messages.isEmpty }
}

/// 奖励引擎。
///
/// 只做三件事：遍历规则、跳过已领的一次性奖励、汇总结果。
/// **不包含任何具体奖励的逻辑。**
struct RewardEngine {

    let rules: [RewardRule]

    static let `default` = RewardEngine(rules:
        [CheckInReward(), OfflineCareReward()] + AchievementRule.all)

    func settle(_ ctx: RewardContext) -> RewardSettlement {
        var total = 0
        var capped = 0
        var claimed: [String] = []
        var messages: [(key: String, args: [CVarArg])] = []
        var payouts: [(reason: CoinReason, coins: Int, ruleID: String)] = []

        for rule in rules {
            // 一次性奖励已领过就跳过
            if rule.isOneTime, ctx.claimed.contains(rule.id) { continue }
            guard let out = rule.evaluate(ctx) else { continue }

            total += out.coins
            if rule.countsTowardDailyCap { capped += out.coins }
            if out.coins > 0 {
                payouts.append((rule.coinReason, out.coins, rule.id))
            }
            if rule.isOneTime { claimed.append(rule.id) }
            if !out.messageKey.isEmpty {
                messages.append((out.messageKey, out.messageArgs))
            }
        }

        return RewardSettlement(totalCoins: total,
                                cappedCoins: capped,
                                newlyClaimed: claimed,
                                messages: messages,
                                payouts: payouts)
    }

    /// 计算状态在离线期间的平均值。
    ///
    /// 衰减是线性的，所以梯形法就是精确解：
    /// - 离线 ≤ 周期：`1 - 离线/(2×周期)`
    /// - 离线 > 周期：衰减到 0 后一直是 0，平均 = `(周期×0.5)/离线`
    static func averageLevel(offlineHours: Double, cycleHours: Double) -> Double {
        guard offlineHours > 0, cycleHours > 0 else { return 1.0 }
        if offlineHours <= cycleHours {
            return 1.0 - offlineHours / (2 * cycleHours)
        }
        return (cycleHours * 0.5) / offlineHours
    }

    /// 从宠物状态与离线时长构造上下文。
    ///
    /// 注意平均值是从**离开那一刻的状态**往前推算的，
    /// 而不是简单用「现在的状态」—— 后者会低估（现在已经衰减完了）。
    static func makeContext(pet: PetState,
                            wallet: PetWallet,
                            now: Date = Date()) -> RewardContext {
        let hours = max(0, now.timeIntervalSince(wallet.lastCollectedAt) / 3600)
        // 饱食周期随生命阶段变化（幼年 12h → 成年 8h）
        let hungerCycle = pet.stage.hungerCycleHours
        return RewardContext(
            pet: pet,
            wallet: wallet,
            now: now,
            offlineHours: hours,
            avgSatiety: averageLevel(offlineHours: hours, cycleHours: hungerCycle),
            avgMood: averageLevel(offlineHours: hours,
                                  cycleHours: pet.breed.moodCycleHours),
            // 额度按宠物分开 —— 每只各有一份（养两只收入翻倍，粮钱也翻倍）
            remainingCap: wallet.remainingCap(stage: pet.stage,
                                              petID: pet.id, at: now))
    }
}
