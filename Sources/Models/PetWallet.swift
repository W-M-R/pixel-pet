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

    /// 已领取的一次性奖励 ID
    var claimedRewards: Set<String>

    /// 启动资金。
    ///
    /// 不给的话新玩家第一顿只能吃剩饭（30% 饱食），第一印象是「穷」。
    /// 100 枚够买一份普通粮 + 攒一点，让第一次喂食就有得选。
    static let initialCoins = 100

    init(now: Date = Date()) {
        coins = Self.initialCoins
        lastCollectedAt = now
        boostUntil = nil
        totalEarned = 0
        claimedRewards = []
    }

    /// buff 是否生效
    func hasBoost(at now: Date = Date()) -> Bool {
        guard let until = boostUntil else { return false }
        return now < until
    }

    /// 看家收益倍率
    func boostMultiplier(at now: Date = Date()) -> Double {
        hasBoost(at: now) ? FoodItem.boostMultiplier : 1.0
    }

    // MARK: - 解码兼容

    private enum CodingKeys: String, CodingKey {
        case coins, lastCollectedAt, boostUntil, totalEarned, claimedRewards
    }

    /// 所有字段都用 decodeIfPresent —— 将来加字段时旧存档不会解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        lastCollectedAt = try c.decodeIfPresent(Date.self, forKey: .lastCollectedAt) ?? Date()
        boostUntil = try c.decodeIfPresent(Date.self, forKey: .boostUntil)
        totalEarned = try c.decodeIfPresent(Int.self, forKey: .totalEarned) ?? 0
        claimedRewards = try c.decodeIfPresent(Set<String>.self, forKey: .claimedRewards) ?? []
    }
}
