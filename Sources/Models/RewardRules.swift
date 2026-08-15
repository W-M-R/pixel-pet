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
        let want = Double(ctx.pet.stage.dailyCap) * rate * boost
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
        case companion, growth, care, food, collection
        var nameKey: String { "achv.group.\(rawValue)" }
    }

    func evaluate(_ ctx: RewardContext) -> RewardOutcome? {
        guard condition(ctx.pet, ctx.wallet) else { return nil }
        return RewardOutcome(coins: coins,
                             messageKey: "reward.achievement.message",
                             messageArgs: [L(nameKey), coins])
    }

    // MARK: - 19 条

    static let all: [AchievementRule] = companion + growth + care + food + collection

    /// 陪伴（5 条，380 枚）
    static let companion: [AchievementRule] = [
        .init(id: "first_feed", nameKey: "achv.first_feed", coins: 100, group: .companion,
              condition: { p, _ in (p.totalFeedCount ?? 0) >= 1 }, progress: nil),
        .streak(3, coins: 200), .streak(7, coins: 500),
        .streak(15, coins: 1000), .streak(30, coins: 2000),
    ]

    /// 成长（4 条，445 枚）
    static let growth: [AchievementRule] = [
        .init(id: "stage_growing", nameKey: "achv.stage_growing", coins: 150, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.growing.minDays }, progress: nil),
        .init(id: "stage_adult", nameKey: "achv.stage_adult", coins: 300, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.adult.minDays }, progress: nil),
        .init(id: "stage_elder", nameKey: "achv.stage_elder", coins: 1000, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.elder.minDays }, progress: nil),
        .init(id: "age_100", nameKey: "achv.age_100", coins: 3000, group: .growth,
              condition: { p, _ in p.ageInDays >= 100 },
              progress: { p, _ in (min(p.ageInDays, 100), 100) }),
    ]

    /// 照料（5 条，320 枚）
    static let care: [AchievementRule] = [
        .counted("feed_50", key: "achv.feed_50", coins: 400, target: 50, group: .care,
                 value: { p, _ in p.totalFeedCount ?? 0 }),
        .counted("feed_200", key: "achv.feed_200", coins: 1200, target: 200, group: .care,
                 value: { p, _ in p.totalFeedCount ?? 0 }),
        .counted("play_30", key: "achv.play_30", coins: 300, target: 30, group: .care,
                 value: { p, _ in p.totalPlayCount ?? 0 }),
        .counted("clean_20", key: "achv.clean_20", coins: 300, target: 20, group: .care,
                 value: { p, _ in p.totalCleanCount ?? 0 }),
        .counted("clean_100", key: "achv.clean_100", coins: 1000, target: 100, group: .care,
                 value: { p, _ in p.totalCleanCount ?? 0 }),
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

    /// 收藏（2 条，70 枚）
    static let collection: [AchievementRule] = [
        .counted("breed_2", key: "achv.breed_2", coins: 300, target: 2, group: .collection,
                 value: { p, _ in p.triedBreeds?.count ?? 1 }),
        .counted("color_4", key: "achv.color_4", coins: 400, target: 4, group: .collection,
                 value: { p, _ in p.triedColors?.count ?? 1 }),
    ]

    // MARK: - 构造辅助

    private static func streak(_ days: Int, coins: Int) -> AchievementRule {
        .counted("streak_\(days)", key: "achv.streak_\(days)", coins: coins,
                 target: days, group: .companion,
                 value: { p, _ in p.streakDays ?? 1 })
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
