import Foundation

/// 结算时的上下文快照。
struct RewardContext {
    let pet: PetState
    let wallet: PetWallet
    let now: Date

    /// 距上次结算的小时数
    let offlineHours: Double

    /// 离线期间三维的平均状态（各 0...1）。
    ///
    /// 分开传而不是先合成一个数 —— 合成规则属于奖励规则自己的职责，
    /// 不同规则可能想用不同权重（比如将来加「只看心情的奖励」）。
    let avgSatiety: Double
    let avgMood: Double
    let avgHygiene: Double

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

    /// 返回 nil = 本次不触发
    func evaluate(_ ctx: RewardContext) -> RewardOutcome?
}

/// 一次结算的结果。
struct RewardSettlement {
    let totalCoins: Int
    /// 新解锁的一次性奖励 ID，调用方要写进存档
    let newlyClaimed: [String]
    /// 要展示的消息（通常只展示第一条）
    let messages: [(key: String, args: [CVarArg])]

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
        var claimed: [String] = []
        var messages: [(key: String, args: [CVarArg])] = []

        for rule in rules {
            // 一次性奖励已领过就跳过
            if rule.isOneTime, ctx.claimed.contains(rule.id) { continue }
            guard let out = rule.evaluate(ctx) else { continue }

            total += out.coins
            if rule.isOneTime { claimed.append(rule.id) }
            if !out.messageKey.isEmpty {
                messages.append((out.messageKey, out.messageArgs))
            }
        }

        return RewardSettlement(totalCoins: total,
                                newlyClaimed: claimed,
                                messages: messages)
    }

    /// 计算三维状态在离线期间的平均值。
    ///
    /// 三条线都是线性衰减，所以梯形法就是精确解：
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
        return RewardContext(
            pet: pet,
            wallet: wallet,
            now: now,
            offlineHours: hours,
            avgSatiety: averageLevel(offlineHours: hours,
                                     cycleHours: PetState.Decay.hunger / 3600),
            avgMood: averageLevel(offlineHours: hours,
                                  cycleHours: PetState.Decay.mood / 3600),
            avgHygiene: averageLevel(offlineHours: hours,
                                     cycleHours: PetState.Decay.hygiene / 3600))
    }
}
