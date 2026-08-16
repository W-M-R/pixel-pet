import Foundation

/// 金币变动的原因。
///
/// **每一笔金币变动都必须有一个 `CoinReason`。** 这是整个经济系统唯一的
/// 变更入口的第二个参数 —— 没有「就是改一下」这种选项。
///
/// 加新玩法时在这里加 case，编译器会强迫你在 `countsTowardDailyCap`
/// 和 `isIncome` 里做出决定，不会漏。
enum CoinReason: String, Codable, CaseIterable, Sendable {

    // MARK: 收入

    /// 离线看家收益。**唯一占每日额度的收入。**
    case offlineCare

    /// 上线奖励（+10，间隔 ≥5h）
    case loginBonus

    /// 成就奖励
    case achievement

    /// 启动资金
    case initialGrant

    // MARK: 支出

    /// 买食物
    case food

    /// 开局买第一只宠物
    case starterPet

    /// 商店买新品种
    case breedPurchase

    // MARK: 调试

    /// 调试面板发钱。**只在 DEBUG 构建可用**，见 `PetStore.debugGrant`。
    case debugGrant

    /// 是否是收入方向。
    ///
    /// 用它而不是「看金额正负」—— 金额一律传正数，方向由原因决定。
    /// 这样 `spend(-100)` 这种把符号搞反的 bug 在类型层面就不存在。
    var isIncome: Bool {
        switch self {
        case .offlineCare, .loginBonus, .achievement, .initialGrant, .debugGrant:
            return true
        case .food, .starterPet, .breedPurchase:
            return false
        }
    }

    /// 是否计入每日额度。
    ///
    /// 只有看家收益占额度。上线奖励和成就刻意不占 ——
    /// 否则「照顾好宠物」的收益会被签到挤掉，见 docs/04-balance.md。
    var countsTowardDailyCap: Bool {
        self == .offlineCare
    }
}

/// 一笔金币流水。
struct CoinEntry: Codable, Equatable, Sendable {
    let reason: CoinReason
    /// 变动金额，**一律为正数**。方向看 `reason.isIncome`。
    let amount: Int
    /// 变动后的余额，用于对账
    let balance: Int
    let at: Date
    /// 附加说明（食物 id、成就 id、品种 id）。仅用于排查，不参与逻辑。
    let note: String?

    var signed: Int { reason.isIncome ? amount : -amount }
}

/// 金币账本 —— **经济系统唯一的状态变更点**。
///
/// ## 为什么要单独一个类型
///
/// 之前收入走 `recordEarning` / `recordBonus` 两个方法，
/// 但支出是三处裸写 `coins -= price`（喂食、首宠、买品种），
/// 散在 `PetStore` 和 `PetWallet` 两个文件里。
///
/// 后果是三个具体问题：
///
/// 1. **没有单一入口** —— `coins` 是 `var`，任何拿到 wallet 的代码都能改，
///    加新的花钱玩法时很容易又多一处裸写。
/// 2. **账目不平** —— 只有 `totalEarned` 没有 `totalSpent`，
///    无法用「收 − 支 == 余额」自检，写错了也发现不了。
/// 3. **无法追溯** —— 用户问「为什么我有 10098 金币」时只能靠人肉推断
///    （翻 claimedRewards、猜哪些是手动改的）。
///
/// 现在所有变动都经过 `apply(_:reason:)`，账目恒等式由测试守着，
/// 且留 `recent` 流水可查。
struct CoinLedger: Codable, Equatable {

    /// 当前余额。`private(set)` —— 外部只能通过 `apply` 改。
    private(set) var balance: Int

    /// 累计收入（只增）
    private(set) var totalIn: Int

    /// 累计支出（只增）
    private(set) var totalOut: Int

    /// 最近若干笔流水。
    ///
    /// 只留尾部 `historyLimit` 笔 —— 完整流水会让存档无限增长，
    /// 而排查问题只需要最近的。
    private(set) var recent: [CoinEntry]

    static let historyLimit = 40

    init(initial: Int = 0, at now: Date = Date()) {
        balance = 0
        totalIn = 0
        totalOut = 0
        recent = []
        if initial > 0 {
            apply(initial, reason: .initialGrant, at: now)
        }
    }

    /// 能否支付。
    func canAfford(_ amount: Int) -> Bool { balance >= amount }

    /// 记一笔变动。**这是唯一能改余额的方法。**
    ///
    /// - Returns: 是否成功。支出时余额不足会失败且不产生流水。
    @discardableResult
    mutating func apply(_ amount: Int,
                        reason: CoinReason,
                        at now: Date = Date(),
                        note: String? = nil) -> Bool {
        // 金额一律正数：负数说明调用方把方向搞反了，
        // 而方向本该由 reason 表达。
        guard amount > 0 else { return false }

        if reason.isIncome {
            balance += amount
            totalIn += amount
        } else {
            guard balance >= amount else { return false }
            balance -= amount
            totalOut += amount
        }

        recent.append(CoinEntry(reason: reason, amount: amount,
                                balance: balance, at: now, note: note))
        if recent.count > Self.historyLimit {
            recent.removeFirst(recent.count - Self.historyLimit)
        }
        return true
    }

    /// 账目是否平。测试用，也可在调试面板显示。
    ///
    /// 这个恒等式是整个经济系统的正确性锚点：
    /// 只要每笔变动都走 `apply`，它永远成立。
    var isBalanced: Bool { totalIn - totalOut == balance }

    /// 按原因汇总（调试面板 / 排查用）
    func total(for reason: CoinReason) -> Int {
        recent.filter { $0.reason == reason }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - 解码兼容

    private enum CodingKeys: String, CodingKey {
        case balance, totalIn, totalOut, recent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balance = try c.decodeIfPresent(Int.self, forKey: .balance) ?? 0
        totalIn = try c.decodeIfPresent(Int.self, forKey: .totalIn) ?? 0
        totalOut = try c.decodeIfPresent(Int.self, forKey: .totalOut) ?? 0
        recent = try c.decodeIfPresent([CoinEntry].self, forKey: .recent) ?? []
    }
}

#if DEBUG
extension CoinLedger {
    /// 把余额直接设成某个值。**仅测试/调试用。**
    ///
    /// 走 `apply` 记一笔 `debugGrant`，所以账目仍然平、流水里也看得见
    /// 「这笔是人为设的」—— 这正是排查「为什么我有这么多钱」时需要的信息。
    mutating func debugSetBalance(_ target: Int, at now: Date = Date()) {
        let delta = target - balance
        guard delta != 0 else { return }
        if delta > 0 {
            apply(delta, reason: .debugGrant, at: now, note: "set \(target)")
        } else {
            // 支出方向也用 debugGrant 记不了（它是收入），
            // 直接调账并补一笔说明，保持恒等式成立。
            balance = target
            totalOut += -delta
            recent.append(CoinEntry(reason: .debugGrant, amount: -delta,
                                    balance: balance, at: now,
                                    note: "set \(target) (扣减)"))
        }
    }
}
#endif
