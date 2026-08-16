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

    /// 已拥有的品种 ID。
    ///
    /// 开局选的那只自动进来。买新品种要先付钱，之后可以随时免费切换 ——
    /// 「买」是一次性解锁，不是消耗品。
    var ownedBreeds: Set<String>

    /// 是否已完成开局（选宠物 + 起名）。
    ///
    /// 存在钱包而非 PetState —— 重置宠物不该让人重走开局流程，
    /// 而且它和「送启动资金」这件事是同一个语义。
    var hasCompletedOnboarding: Bool

    /// 启动资金。
    ///
    /// 5000 枚，其中 4000 用于买第一只宠物，余 1000 起步。
    ///
    /// 1000 枚够买 28 份普通粮（35/份）或 6 份罐头 ——
    /// 有「刚好够用但要省着花」的紧张感，又不至于卡死（剩饭永久免费）。
    ///
    /// 定价推导见 docs/07-shop.md。
    static let initialCoins = 5000

    /// 第一只宠物的价格。
    ///
    /// 从启动资金里扣，让「选宠物」这件事有重量感 ——
    /// 直接送一只的话，开局的选择缺少代价。
    static let starterPrice = 4000

    init(now: Date = Date()) {
        coins = Self.initialCoins
        lastCollectedAt = now
        boostUntil = nil
        totalEarned = 0
        todayEarned = 0
        lastEarnDate = now
        claimedRewards = []
        ownedBreeds = []
        hasCompletedOnboarding = false
    }

    // MARK: - 品种拥有

    func owns(_ breed: PetBreed) -> Bool {
        // 开局品种只要买过就算拥有；其余看解锁记录
        ownedBreeds.contains(breed.id)
    }

    /// 能否买得起某个品种
    func canAfford(_ breed: PetBreed) -> Bool {
        coins >= breed.price
    }

    /// 购买品种。返回是否成功。
    @discardableResult
    mutating func purchase(_ breed: PetBreed) -> Bool {
        guard !owns(breed) else { return true }   // 已拥有，幂等
        guard coins >= breed.price else { return false }
        coins -= breed.price
        ownedBreeds.insert(breed.id)
        return true
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
        case ownedBreeds, hasCompletedOnboarding
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
        ownedBreeds = try c.decodeIfPresent(Set<String>.self, forKey: .ownedBreeds) ?? []
        // 旧存档没有这个字段。如果已经有宠物在养（钱包被用过），
        // 视为已完成开局，不该把老用户拉回选宠界面。
        if let done = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) {
            hasCompletedOnboarding = done
        } else {
            hasCompletedOnboarding = (totalEarned > 0 || !claimedRewards.isEmpty)
        }
    }
}
