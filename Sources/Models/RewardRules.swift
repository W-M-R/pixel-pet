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
    static let coins = 1

    func evaluate(_ ctx: RewardContext) -> RewardOutcome? {
        guard ctx.offlineHours >= Self.minIntervalHours else { return nil }
        return RewardOutcome(coins: Self.coins, messageKey: "")   // 不单独说话
    }
}

// MARK: - 离线看家收益

/// 宠物在你离开时看家赚钱。
///
/// ```
/// 硬币 = min(离线小时, 10) × 0.9 × 状态系数 × buff倍率
/// 状态系数 = 0.3 + (三维压缩乘积) × 1.05        // 0.58 ~ 1.35
/// ```
///
/// 完整推导见 docs/01-economy.md。
struct OfflineCareReward: RewardRule {
    let id = "offline_care"
    let nameKey = "reward.offline_care"
    let isOneTime = false

    static let ratePerHour: Double = 0.9
    static let maxHours: Double = 10

    /// 三维压缩区间。**宽度即权重。**
    ///
    /// 为什么用乘法而不是加权平均：清洁周期 72h，离线 24h 时它还有 0.83，
    /// 等权平均会被它拉高，掩盖饱食只剩 0.17 的事实。
    /// 但纯乘法太狠（24h 只剩 0.05，收益归零），所以先压缩到不触底的区间。
    enum Weight {
        /// 心情最重 —— 情绪价值是宠物 app 的核心
        static let moodBase = 0.45, moodSpan = 0.55
        /// 饱食中等 —— 有免费剩饭保底，不该惩罚过重
        static let satietyBase = 0.70, satietySpan = 0.30
        /// 清洁最轻 —— 周期 72h，本就是低频维护
        static let hygieneBase = 0.85, hygieneSpan = 0.15

        static let coefBase = 0.30, coefSpan = 1.05
    }

    /// 状态系数，范围 0.58 ~ 1.35
    static func stateCoefficient(satiety: Double, mood: Double, hygiene: Double) -> Double {
        let s = clamp(satiety), m = clamp(mood), h = clamp(hygiene)
        let factor = (Weight.satietyBase + Weight.satietySpan * s)
            * (Weight.moodBase + Weight.moodSpan * m)
            * (Weight.hygieneBase + Weight.hygieneSpan * h)
        return Weight.coefBase + factor * Weight.coefSpan
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    func evaluate(_ ctx: RewardContext) -> RewardOutcome? {
        // 太短不结算，避免频繁开关刷出零碎收益
        guard ctx.offlineHours >= 0.5 else { return nil }

        let hours = min(ctx.offlineHours, Self.maxHours)
        let coef = Self.stateCoefficient(satiety: ctx.avgSatiety,
                                         mood: ctx.avgMood,
                                         hygiene: ctx.avgHygiene)
        let boost = ctx.wallet.boostMultiplier(at: ctx.now)
        let raw = hours * Self.ratePerHour * coef * boost
        let coins = Int(raw.rounded())
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
        .init(id: "first_feed", nameKey: "achv.first_feed", coins: 10, group: .companion,
              condition: { p, _ in (p.totalFeedCount ?? 0) >= 1 }, progress: nil),
        .streak(3, coins: 20), .streak(7, coins: 50),
        .streak(15, coins: 100), .streak(30, coins: 200),
    ]

    /// 成长（4 条，445 枚）
    static let growth: [AchievementRule] = [
        .init(id: "stage_growing", nameKey: "achv.stage_growing", coins: 15, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.growing.minDays }, progress: nil),
        .init(id: "stage_adult", nameKey: "achv.stage_adult", coins: 30, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.adult.minDays }, progress: nil),
        .init(id: "stage_elder", nameKey: "achv.stage_elder", coins: 100, group: .growth,
              condition: { p, _ in p.ageInDays >= PetStage.elder.minDays }, progress: nil),
        .init(id: "age_100", nameKey: "achv.age_100", coins: 300, group: .growth,
              condition: { p, _ in p.ageInDays >= 100 },
              progress: { p, _ in (min(p.ageInDays, 100), 100) }),
    ]

    /// 照料（5 条，320 枚）
    static let care: [AchievementRule] = [
        .counted("feed_50", key: "achv.feed_50", coins: 40, target: 50, group: .care,
                 value: { p, _ in p.totalFeedCount ?? 0 }),
        .counted("feed_200", key: "achv.feed_200", coins: 120, target: 200, group: .care,
                 value: { p, _ in p.totalFeedCount ?? 0 }),
        .counted("play_30", key: "achv.play_30", coins: 30, target: 30, group: .care,
                 value: { p, _ in p.totalPlayCount ?? 0 }),
        .counted("clean_20", key: "achv.clean_20", coins: 30, target: 20, group: .care,
                 value: { p, _ in p.totalCleanCount ?? 0 }),
        .counted("clean_100", key: "achv.clean_100", coins: 100, target: 100, group: .care,
                 value: { p, _ in p.totalCleanCount ?? 0 }),
    ]

    /// 美食（3 条，120 枚）
    static let food: [AchievementRule] = [
        .init(id: "food_can", nameKey: "achv.food_can", coins: 15, group: .food,
              condition: { p, _ in (p.foodCounts?[FoodItem.can.id] ?? 0) >= 1 }, progress: nil),
        .init(id: "food_fish", nameKey: "achv.food_fish", coins: 25, group: .food,
              condition: { p, _ in (p.foodCounts?[FoodItem.driedFish.id] ?? 0) >= 1 },
              progress: nil),
        .counted("food_fish_20", key: "achv.food_fish_20", coins: 80, target: 20, group: .food,
                 value: { p, _ in p.foodCounts?[FoodItem.driedFish.id] ?? 0 }),
    ]

    /// 收藏（2 条，70 枚）
    static let collection: [AchievementRule] = [
        .counted("breed_2", key: "achv.breed_2", coins: 30, target: 2, group: .collection,
                 value: { p, _ in p.triedBreeds?.count ?? 1 }),
        .counted("color_4", key: "achv.color_4", coins: 40, target: 4, group: .collection,
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
