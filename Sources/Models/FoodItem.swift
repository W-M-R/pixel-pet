import Foundation

/// 一档食物。
///
/// 不做背包 —— 买了立即用。省掉一整套背包 UI，
/// 而且宠物 app 的核心是照顾，不是资源管理。
struct FoodItem: Identifiable, Hashable {

    let id: String
    let emoji: String
    let nameKey: String
    /// 附加效果的固定价（心情加成、buff）。
    ///
    /// **为什么固定而不按量**：附加效果的价值和宠物饿不饿无关 ——
    /// 小鱼干的 buff 是「24h 内达成率 ×1.6」，饱食 99% 时吃和空腹时吃
    /// 一样有用。原来整个价格都按恢复量算，导致**等饱食快满时买小鱼干
    /// 只要 3 枚却拿满额 buff**，那就成了最优解，破坏「奢侈品」定位。
    let extraPrice: Int

    /// 最低价。
    ///
    /// 防「饱食接近满时所有食物免费」—— 那样可以零成本反复点喂食，
    /// 刷 `foodCounts` 和美食类成就。
    /// 剩饭是唯一例外（`isFree`），它必须永久免费作防死锁的兜底。
    let minPrice: Int

    /// 是否免费无限
    let isFree: Bool
    /// 恢复饱食的比例（加到当前值上，封顶 1.0）
    let satietyRestore: Double
    /// 附加的心情提升
    let moodBonus: Double
    /// 吃了是否触发达成率 buff
    let grantsBoost: Bool

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

    /// 在当前饱食度下的实际花费。
    ///
    /// ```
    /// 花费 = max(最低价, 补上的饱食量 × 10 × 5 + 附加效果固定价)
    /// ```
    ///
    /// **饱食部分按量** —— 这是修「照顾越勤越亏」的关键（见上）。
    /// 半饱时吃罐头只补一半，就只收一半的饱食钱，所以不再需要
    /// 「现在吃有点浪费」的提示。
    ///
    /// **附加效果固定价** —— 否则饱食快满时买小鱼干几乎免费却拿满 buff。
    ///
    /// **最低价兜底** —— 否则饱食 100% 时一切免费，可零成本刷成就。
    func cost(currentSatiety: Double) -> Int {
        guard !isFree else { return 0 }
        let gained = actualRestore(currentSatiety: currentSatiety)
        let satietyPart = Int((gained * 10 * Double(Self.coinsPer10Percent)).rounded())
        return max(minPrice, satietyPart + extraPrice)
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
        extraPrice: 0, minPrice: 0, isFree: true,
        satietyRestore: 0.30, moodBonus: 0, grantsBoost: false)

    /// 日常主力。空腹价 35（0.70 × 10 × 5），无附加效果。
    static let kibble = FoodItem(
        id: "kibble", emoji: "🍚", nameKey: "food.kibble",
        extraPrice: 0, minPrice: 2, isFree: false,
        satietyRestore: 0.70, moodBonus: 0, grantsBoost: false)

    /// 空腹价 150 = 饱食 50 + 心情加成 100。
    ///
    /// 心情 +10% 的价值和饱食无关，所以那 100 枚是固定的 ——
    /// 满饱时吃罐头仍要 100 枚，不会变成白送 buff。
    static let can = FoodItem(
        id: "can", emoji: "🥫", nameKey: "food.can",
        extraPrice: 100, minPrice: 100, isFree: false,
        satietyRestore: 1.0, moodBonus: 0.10, grantsBoost: false)

    /// 空腹价 250 = 饱食 50 + 效果 200。卖的是 buff 和心情，不是饱食效率。
    ///
    /// buff 改成「抬高达成率」而非「乘收益」：额度制下任何乘法 buff
    /// 都会被封顶吃掉（实测多赚 +0）。抬达成率则在 2-4 次/天立刻生效，
    /// 帮「没空频繁开」的玩家追进度，而开得很勤的人本来就领满、无额外收益。
    static let driedFish = FoodItem(
        id: "dried_fish", emoji: "🐟", nameKey: "food.dried_fish",
        extraPrice: 200, minPrice: 200, isFree: false,
        satietyRestore: 1.0, moodBonus: 0.25, grantsBoost: true)

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
