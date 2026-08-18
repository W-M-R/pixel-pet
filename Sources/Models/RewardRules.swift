import Foundation

// MARK: - 上线奖励

/// 每次打开 +1 枚，要求距上次结算 ≥5 小时。
///
/// 5 小时限制防无脑开关刷币。配合 8 小时饱食周期，
/// 自然形成「一天 3-4 次」的节奏上限。
///
/// 只给 1 枚是刻意的：它的作用是「每次回来都有一点点收获」的心理反馈，
/// 而非收入主力。主力是看家收益。
struct CheckInReward: RewardRule {
    let id = "checkin"
    let nameKey = "reward.checkin"
    let isOneTime = false

    static let minIntervalHours: Double = 5
    static let coins = 10

    var coinReason: CoinReason { .loginBonus }

    func evaluate(_ ctx: RewardContext) -> RewardOutcome? {
        guard ctx.offlineHours >= Self.minIntervalHours else { return nil }
        return RewardOutcome(coins: Self.coins, messageKey: "")   // 不单独说话
    }
}

// MARK: - 离线看家收益

/// 宠物在你离开时看家赚钱。**每日额度制。**
///
/// ```
/// 硬币 = min(今日剩余额度, 每日额度 × 达成率 × buff)
/// 达成率 = 0.05 + 0.30 × (0.40×饱食 + 0.60×心情)²      // 0.05 ~ 0.35
/// 每日额度 = PetStage.dailyCap                        // 幼170 → 成年225
/// ```
///
/// 为什么是额度制而不是「按小时 × 速率」：
/// 旧公式下支出随喂食次数线性增长，收入却被 10h 上限压平，
/// 导致「照顾越勤越亏」。按 Daniel Cook 的 source/sink 幂次分类，
/// 这是 capped source 配 repeatable sink 的经典失配 ——
/// 靠调单价永远调不平，必须让两端幂次对齐。详见 docs/04-balance.md。
///
/// **没有单次领取上限。** 早先加过（额度×15%），但实测它会盖住达成率：
/// 任何正常状态下都是单次上限在起作用，状态好坏完全不影响收益，
/// 把「照顾好宠物=赚得多」彻底架空了。防刷币交给额度封顶就够。
struct OfflineCareReward: RewardRule {
    let id = "offline_care"
    let nameKey = "reward.offline_care"
    let isOneTime = false
    /// 唯一占额度的规则
    let countsTowardDailyCap = true
    var coinReason: CoinReason { .offlineCare }

    /// 达成率区间。
    ///
    /// 上界 0.35 而非 1.0 是为了让「一次结算领不满额度」——
    /// 否则开一次和开五次收入相同，激励结构失效。
    /// 0.35 对应约 3 次结算才能领满，正好落在目标节奏（4-5 次/天）之下。
    enum Rate {
        static let floor = 0.05
        static let span = 0.30

        /// 心情权重高于饱食 —— 情绪价值是宠物 app 的核心。
        static let satietyWeight = 0.40
        static let moodWeight = 0.60
    }

    /// 达成率，范围 0.05 ~ 0.35。
    ///
    /// 用平方而非线性：线性只能拉开 2.2 倍差距，压不住喂食支出的增长。
    /// 平方后勤快照顾（0.30）与放养（0.08）差约 4 倍。
    static func achievementRate(satiety: Double, mood: Double) -> Double {
        let blend = Rate.satietyWeight * clamp(satiety) + Rate.moodWeight * clamp(mood)
        return Rate.floor + Rate.span * blend * blend
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    func evaluate(_ ctx: RewardContext) -> RewardOutcome? {
        // 太短不结算，避免频繁开关刷出零碎收益
        guard ctx.offlineHours >= 0.5 else { return nil }
        // 今日额度已用完
        guard ctx.remainingCap > 0 else { return nil }

        let rate = Self.achievementRate(satiety: ctx.avgSatiety, mood: ctx.avgMood)
        let boost = ctx.wallet.boostMultiplier(at: ctx.now)
        // 品种金币加成 —— 用来抵消心情周期的优劣，让高频玩家
        // 无论选哪只收益都接近（见 PetBreed.goldMultiplier）
        let breedBonus = ctx.pet.breed.goldMultiplier
        let want = Double(ctx.pet.stage.dailyCap) * rate * boost * breedBonus
        let coins = min(ctx.remainingCap, Int(want.rounded()))
        guard coins > 0 else { return nil }

        return RewardOutcome(coins: coins,
                             messageKey: "reward.offline.message",
                             messageArgs: [coins])
    }
}

// MARK: - 成就

/// 一次性成就。
///
/// 19 条用**同一个类型的 19 个实例**，数据驱动，不是 19 个 class。
struct AchievementRule: RewardRule {
    let id: String
    let nameKey: String
    let coins: Int
    let group: Group
    /// 条件判定
    let condition: (PetState, PetWallet) -> Bool
    /// 进度显示：(当前, 目标)。nil = 布尔型成就，没有进度条
    let progress: ((PetState, PetWallet) -> (Int, Int))?

    var isOneTime: Bool { true }

    enum Group: String, CaseIterable {
        case companion, growth, care, food, collection, economy
        var nameKey: String { "achv.group.\(rawValue)" }
    }

    /// 解锁条件的说明文案 key。
    ///
    /// 约定 `achv.<id>.desc` —— 由 id 推导而非单独存字段，
    /// 这样加成就时不会漏（漏了界面会显示 key 本身，测试也会抓）。
    var descKey: String { "achv.\(id).desc" }

    func evaluate(_ ctx: RewardContext) -> RewardOutcome? {
        guard condition(ctx.pet, ctx.wallet) else { return nil }
        return RewardOutcome(coins: coins,
                             messageKey: "reward.achievement.message",
                             messageArgs: [L(nameKey), coins])
    }

    // MARK: - 成就表

    static let all: [AchievementRule] =
        companion + growth + care + food + collection + economy

    /// 陪伴（5 条）。
    ///
    /// ⚠️ `streak_*` 看的是 **`wellCaredDays`（照顾达标天数）**，
    /// 不是「打开 app 的天数」。
    ///
    /// 原来看 `streakDays`，只要每天点开就 +1 —— 放养 30 天
    /// 照样拿满 2000 枚。当时时间型成就占全部成就金额的 61%，
    /// 完全不看照顾质量，导致「放养 30 天」和「认真养 13 天」
    /// 都能买第二只宠物，违反「照顾好宠物 = 赚得多」
    /// （docs/00-overview.md 第 5 条）。
    ///
    /// 达标定义：当天三维平均 ≥ `StateThreshold.wellCared`(0.6)。
    static let companion: [AchievementRule] = [
        .init(id: "first_feed", nameKey: "achv.first_feed", coins: 100, group: .companion,
              condition: { p, _ in (p.totalFeedCount ?? 0) >= 1 }, progress: nil),
        .cared(3, coins: 200), .cared(7, coins: 500),
        .cared(15, coins: 1000), .cared(30, coins: 2000),
    ]

    /// 成长（4 条）。
    ///
    /// **金额刻意压低。** 这几条纯粹是时间流逝的产物 ——
    /// 装着不管也会到成年、到老年，所以不该给大钱。
    /// 原来是 150/300/1000/3000（共 4450），现在 80/150/400/800（共 1430），
    /// 省下的 3020 枚挪到要真互动才拿得到的照料型。
    static let growth: [AchievementRule] = [
        .init(id: "stage_growing", nameKey: "achv.stage_growing", coins: 80, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.growing.minDays }, progress: nil),
        .init(id: "stage_adult", nameKey: "achv.stage_adult", coins: 150, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.adult.minDays }, progress: nil),
        .init(id: "stage_elder", nameKey: "achv.stage_elder", coins: 400, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.elder.minDays }, progress: nil),
        .init(id: "age_100", nameKey: "achv.age_100", coins: 800, group: .growth,
              condition: { p, _ in p.ageInDays >= 100 },
              progress: { p, _ in (min(p.ageInDays, 100), 100) }),
    ]

    /// 照料（11 条）—— **必须真的互动才拿得到**，是主要的金币来源。
    static let care: [AchievementRule] = [
        .counted("feed_50", key: "achv.feed_50", coins: 400, target: 50, group: .care,
                 value: { p, _ in p.totalFeedCount ?? 0 }),
        .counted("feed_200", key: "achv.feed_200", coins: 1200, target: 200, group: .care,
                 value: { p, _ in p.totalFeedCount ?? 0 }),
        .counted("feed_500", key: "achv.feed_500", coins: 2000, target: 500, group: .care,
                 value: { p, _ in p.totalFeedCount ?? 0 }),
        .counted("play_30", key: "achv.play_30", coins: 300, target: 30, group: .care,
                 value: { p, _ in p.totalPlayCount ?? 0 }),
        .counted("play_100", key: "achv.play_100", coins: 800, target: 100, group: .care,
                 value: { p, _ in p.totalPlayCount ?? 0 }),
        .counted("play_300", key: "achv.play_300", coins: 1800, target: 300, group: .care,
                 value: { p, _ in p.totalPlayCount ?? 0 }),
        .counted("clean_20", key: "achv.clean_20", coins: 300, target: 20, group: .care,
                 value: { p, _ in p.totalCleanCount ?? 0 }),
        .counted("clean_100", key: "achv.clean_100", coins: 1000, target: 100, group: .care,
                 value: { p, _ in p.totalCleanCount ?? 0 }),
        .counted("clean_300", key: "achv.clean_300", coins: 1800, target: 300, group: .care,
                 value: { p, _ in p.totalCleanCount ?? 0 }),
        // 状态型：奖励「把宠物照顾得好」这个结果本身，而非互动次数。
        //
        // ⚠️ 必须要求「已经养了一阵」——新宠物三维是满的，
        // 只判状态的话开局第一秒就白送 500 枚，而玩家什么都没做。
        // 门槛取「三类互动各做过一次」：那说明状态是维持出来的，不是初始值。
        .init(id: "all_high", nameKey: "achv.all_high", coins: 500, group: .care,
              condition: { p, _ in
                  guard (p.totalFeedCount ?? 0) >= 1,
                        (p.totalPlayCount ?? 0) >= 1,
                        (p.totalCleanCount ?? 0) >= 1 else { return false }
                  let now = Date()
                  return p.satiety(at: now) >= 0.9 && p.mood(at: now) >= 0.9
                      && p.hygiene(at: now) >= 0.9
              }, progress: nil),
    ]

    /// 美食（3 条，120 枚）
    static let food: [AchievementRule] = [
        .init(id: "food_can", nameKey: "achv.food_can", coins: 150, group: .food,
              condition: { p, _ in (p.foodCounts?[FoodItem.can.id] ?? 0) >= 1 }, progress: nil),
        .init(id: "food_fish", nameKey: "achv.food_fish", coins: 250, group: .food,
              condition: { p, _ in (p.foodCounts?[FoodItem.driedFish.id] ?? 0) >= 1 },
              progress: nil),
        .counted("food_fish_20", key: "achv.food_fish_20", coins: 800, target: 20, group: .food,
                 value: { p, _ in p.foodCounts?[FoodItem.driedFish.id] ?? 0 }),
    ]

    /// 收藏（4 条）。多宠玩法带来的新维度。
    static let collection: [AchievementRule] = [
        // ⚠️ 这两条读**钱包**，不是单只宠物。
        //
        // 品种和毛色在创建宠物时定死（`purchase` 的注释：「毛色在购买时
        // 定死，之后不能改」），所以单只的 `triedBreeds` / `triedColors`
        // 永远只有它自己那一个 —— 按单只判定的话这两条**永远拿不到**。
        //
        // 曾经它们看起来能达成，靠的是一个 bug：`completeOnboarding` 把
        // 占位猫的 `["cat"]` 并进了玩家选的品种，选狗就凑成 2 个。
        // 那导致选狗开局白送 300 枚而选猫不送。修掉泄漏后这两条就
        // 暴露为不可达 —— 一个 bug 掩盖了另一个。
        .counted("breed_2", key: "achv.breed_2", coins: 300, target: 2, group: .collection,
                 value: { _, w in w.ownedBreeds.count }),
        .counted("color_4", key: "achv.color_4", coins: 400, target: 4, group: .collection,
                 value: { _, w in w.triedColors.count }),
        // 同时养几只。`ownedBreeds` 是「买过的品种」，
        // 而真正的宠物数量在 PetStore.pets —— 钱包里记不到，
        // 所以用买过的品种数近似（每买一次就多一只）。
        .counted("pets_2", key: "achv.pets_2", coins: 500, target: 2, group: .collection,
                 value: { _, w in w.ownedBreeds.count }),
        .counted("pets_3", key: "achv.pets_3", coins: 1500, target: 3, group: .collection,
                 value: { _, w in w.ownedBreeds.count }),
    ]

    /// 经济（3 条）。给「攒钱」这件事本身一点反馈。
    ///
    /// ⚠️ **三条都用 `totalEarned`（累计赚取），不用余额。** 两个原因：
    /// 1. 余额会因为买东西下降，拿它当条件的话玩家不敢花钱
    /// 2. 启动资金就是 5000 —— 用余额的话「存款达 5000」在开局
    ///    第一秒就达成，白送 300 枚。这个 bug 是被
    ///    `OpeningSequenceTests` 抓到的：它断言「刚建的 store
    ///    不该有收益播报」，结果冒出一条成就。
    static let economy: [AchievementRule] = [
        .counted("rich_5000", key: "achv.rich_5000", coins: 300, target: 3000,
                 group: .economy, value: { _, w in w.totalEarned }),
        .counted("earn_10000", key: "achv.earn_10000", coins: 800, target: 10000,
                 group: .economy, value: { _, w in w.totalEarned }),
        .counted("earn_50000", key: "achv.earn_50000", coins: 2500, target: 50000,
                 group: .economy, value: { _, w in w.totalEarned }),
    ]

    // MARK: - 构造辅助

    /// 「照顾达标 N 天」。
    ///
    /// id 沿用 `streak_N` —— 改 id 会让已领过的老用户重新拿一遍。
    /// 但判定依据换成 `wellCaredDays`，文案也改了（见本地化）。
    private static func cared(_ days: Int, coins: Int) -> AchievementRule {
        .counted("streak_\(days)", key: "achv.streak_\(days)", coins: coins,
                 target: days, group: .companion,
                 value: { p, _ in p.wellCaredDays ?? 0 })
    }

    /// 带进度的计数型成就
    private static func counted(_ id: String, key: String, coins: Int, target: Int,
                                group: Group,
                                value: @escaping (PetState, PetWallet) -> Int) -> AchievementRule {
        .init(id: id, nameKey: key, coins: coins, group: group,
              condition: { p, w in value(p, w) >= target },
              progress: { p, w in (min(value(p, w), target), target) })
    }
}
