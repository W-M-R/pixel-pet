import Foundation

/// 钱包。
///
/// **独立于 `PetState` 存档**（`wallet.json`）—— 换宠物不该清空钱包，
/// 两者生命周期不同。也让 `PetState` 已经很复杂的解码兼容逻辑不再变复杂。
struct PetWallet: Codable, Equatable {

    var coins: Int

    /// 上次结算时间。离线收益与上线奖励都以它为基准。
    var lastCollectedAt: Date

    /// 小鱼干 buff 到期时间。nil = 无 buff。
    ///
    /// 存在钱包而非 `PetState`：它是经济系统的一部分，换宠物不该清除。
    var boostUntil: Date?

    /// 累计赚取（只增不减，成就用）
    var totalEarned: Int

    /// 今日已从看家收益赚到的额度。跨日由 `recordEarning` 自动重置。
    ///
    /// **必须落盘。** 只在内存里算的话，反复开关 app 每次都能拿满额度 ——
    /// 这是额度制最主要的刷币面。
    var todayEarned: Int

    /// `todayEarned` 对应的日期，用于判断跨日
    var lastEarnDate: Date

    /// 已领取的一次性奖励 ID
    var claimedRewards: Set<String>

    /// 启动资金。
    ///
    /// 不给的话新玩家第一顿只能吃剩饭（30% 饱食），第一印象是「穷」。
    /// 100 枚够买两三份普通粮，让第一次喂食就有得选。
    static let initialCoins = 100

    init(now: Date = Date()) {
        coins = Self.initialCoins
        lastCollectedAt = now
        boostUntil = nil
        totalEarned = 0
        todayEarned = 0
        lastEarnDate = now
        claimedRewards = []
    }

    // MARK: - 每日额度

    /// 今日剩余额度。跨日自动视为满额。
    func remainingCap(stage: PetStage, at now: Date = Date()) -> Int {
        let cap = stage.dailyCap
        guard Calendar.current.isDate(lastEarnDate, inSameDayAs: now) else {
            return cap
        }
        return max(0, cap - todayEarned)
    }

    /// 记一笔看家收益。跨日先归零，再累加。
    ///
    /// 日历逻辑收在这里，`PetStore` 只调一次 —— 避免跨日判断散落多处。
    mutating func recordEarning(_ amount: Int, at now: Date = Date()) {
        guard amount > 0 else { return }
        if !Calendar.current.isDate(lastEarnDate, inSameDayAs: now) {
            todayEarned = 0
        }
        todayEarned += amount
        lastEarnDate = now
        coins += amount
        totalEarned += amount
    }

    /// 记一笔不占额度的收入（上线奖励、成就）
    mutating func recordBonus(_ amount: Int) {
        guard amount > 0 else { return }
        coins += amount
        totalEarned += amount
    }

    // MARK: - buff

    /// buff 是否生效
    func hasBoost(at now: Date = Date()) -> Bool {
        guard let until = boostUntil else { return false }
        return now < until
    }

    /// 达成率倍率
    func boostMultiplier(at now: Date = Date()) -> Double {
        hasBoost(at: now) ? FoodItem.boostMultiplier : 1.0
    }

    // MARK: - 解码兼容

    private enum CodingKeys: String, CodingKey {
        case coins, lastCollectedAt, boostUntil, totalEarned
        case todayEarned, lastEarnDate, claimedRewards
    }

    /// 所有字段都用 decodeIfPresent —— 将来加字段时旧存档不会解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? Self.initialCoins
        lastCollectedAt = try c.decodeIfPresent(Date.self, forKey: .lastCollectedAt) ?? Date()
        boostUntil = try c.decodeIfPresent(Date.self, forKey: .boostUntil)
        totalEarned = try c.decodeIfPresent(Int.self, forKey: .totalEarned) ?? 0
        todayEarned = try c.decodeIfPresent(Int.self, forKey: .todayEarned) ?? 0
        lastEarnDate = try c.decodeIfPresent(Date.self, forKey: .lastEarnDate) ?? .distantPast
        claimedRewards = try c.decodeIfPresent(Set<String>.self, forKey: .claimedRewards) ?? []
    }
}
