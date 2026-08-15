import Foundation

/// 一档食物。
///
/// 不做背包 —— 买了立即用。省掉一整套背包 UI，
/// 而且宠物 app 的核心是照顾，不是资源管理。
struct FoodItem: Identifiable, Hashable {

    let id: String
    let emoji: String
    let nameKey: String
    /// 单价倍率。0 = 免费无限。实际花费见 `cost(currentSatiety:)`。
    let priceMultiplier: Int
    /// 恢复饱食的比例（加到当前值上，封顶 1.0）
    let satietyRestore: Double
    /// 附加的心情提升
    let moodBonus: Double
    /// 吃了是否触发达成率 buff
    let grantsBoost: Bool

    var isFree: Bool { priceMultiplier == 0 }

    // MARK: - 计价

    /// 每恢复 10% 饱食的基准价。
    ///
    /// **按恢复量计价，不按次固定价。** 这是修「照顾越勤越亏」的关键：
    /// 一天需要补的饱食总量由周期决定（24h ÷ 周期），与喂几次无关，
    /// 所以支出会饱和成常数级，和有上限的收入幂次对齐。
    ///
    /// 固定价（线性支出）配额度制收入（常数级）必然导致次数越多越亏 ——
    /// 见 docs/04-balance.md 的 source/sink 幂次分析。
    static let coinsPer10Percent = 5

    /// 小鱼干 buff：24 小时内达成率 ×1.6
    static let boostMultiplier: Double = 1.6
    static let boostDuration: TimeInterval = 24 * 3600

    /// 在当前饱食度下的实际花费 —— **只为「补上的量」付钱**。
    ///
    /// 半饱时吃罐头只补一半，所以只收一半钱。
    /// 因此不再需要「现在吃有点浪费」的提示：随时喂不亏。
    func cost(currentSatiety: Double) -> Int {
        guard priceMultiplier > 0 else { return 0 }
        let gained = actualRestore(currentSatiety: currentSatiety)
        let unit = Double(Self.coinsPer10Percent * priceMultiplier)
        return Int((gained * 10 * unit).rounded())
    }

    /// 满价（饱食为 0 时）。仅用于文档/商店的参考标注。
    var fullPrice: Int { cost(currentSatiety: 0) }

    /// 实际能补上的饱食量（受 100% 封顶）
    func actualRestore(currentSatiety: Double) -> Double {
        let cur = min(1, max(0, currentSatiety))
        return min(satietyRestore, 1.0 - cur)
    }

    // MARK: - 四档

    /// 免费保底。抄猫咪后院的 Thrifty Bitz ——
    /// 保证长期不登录的用户回来也能喂饭，不会「没钱→宠物一直饿→
    /// 达成率低→更没钱」死循环。
    ///
    /// 论文里这叫 weak static engine，专门用来防 converter engine 的死锁。
    static let scraps = FoodItem(
        id: "scraps", emoji: "🥣", nameKey: "food.scraps",
        priceMultiplier: 0, satietyRestore: 0.30, moodBonus: 0, grantsBoost: false)

    /// 日常主力。满价 35（0.70 × 10 × 5）。
    static let kibble = FoodItem(
        id: "kibble", emoji: "🍚", nameKey: "food.kibble",
        priceMultiplier: 1, satietyRestore: 0.70, moodBonus: 0, grantsBoost: false)

    /// 满价 150。倍率 3 让它是「偶尔犒赏」而非日常选择。
    static let can = FoodItem(
        id: "can", emoji: "🥫", nameKey: "food.can",
        priceMultiplier: 3, satietyRestore: 1.0, moodBonus: 0.10, grantsBoost: false)

    /// 满价 250。卖的是 buff 和心情，不是饱食效率。
    ///
    /// buff 改成「抬高达成率」而非「乘收益」：额度制下任何乘法 buff
    /// 都会被封顶吃掉（实测多赚 +0）。抬达成率则在 2-4 次/天立刻生效，
    /// 帮「没空频繁开」的玩家追进度，而开得很勤的人本来就领满、无额外收益。
    static let driedFish = FoodItem(
        id: "dried_fish", emoji: "🐟", nameKey: "food.dried_fish",
        priceMultiplier: 5, satietyRestore: 1.0, moodBonus: 0.25, grantsBoost: true)

    static let all: [FoodItem] = [.scraps, .kibble, .can, .driedFish]

    static func byID(_ id: String) -> FoodItem? {
        all.first { $0.id == id }
    }

    // MARK: - 「能管多久」

    /// 在当前饱食度下**实际**能维持多久（小时）。
    ///
    /// 周期随生命阶段变化，所以要传 stage。
    func effectiveHours(currentSatiety: Double, stage: PetStage) -> Double {
        actualRestore(currentSatiety: currentSatiety) * stage.hungerCycleHours
    }
}
