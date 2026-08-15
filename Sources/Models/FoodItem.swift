import Foundation

/// 一档食物。
///
/// 不做背包 —— 买了立即用。省掉一整套背包 UI，
/// 而且宠物 app 的核心是照顾，不是资源管理。
struct FoodItem: Identifiable, Hashable {

    let id: String
    let emoji: String
    let nameKey: String
    /// 价格，0 = 免费无限
    let price: Int
    /// 恢复饱食的比例（加到当前值上，封顶 1.0）
    let satietyRestore: Double
    /// 附加的心情提升
    let moodBonus: Double
    /// 吃了是否触发看家收益 buff
    let grantsBoost: Bool

    var isFree: Bool { price == 0 }

    /// 小鱼干 buff：24 小时内看家收益 ×1.3
    static let boostMultiplier: Double = 1.3
    static let boostDuration: TimeInterval = 24 * 3600

    // MARK: - 四档

    /// 免费保底。抄猫咪后院的 Thrifty Bitz ——
    /// 保证长期不登录的用户回来也能喂饭，不会「没钱→宠物一直饿→
    /// 收益系数低→更没钱」死循环。
    static let scraps = FoodItem(
        id: "scraps", emoji: "🥣", nameKey: "food.scraps",
        price: 0, satietyRestore: 0.30, moodBonus: 0, grantsBoost: false)

    /// 日常主力。性价比最高（0.80 小时/枚）。
    static let kibble = FoodItem(
        id: "kibble", emoji: "🍚", nameKey: "food.kibble",
        price: 7, satietyRestore: 0.70, moodBonus: 0, grantsBoost: false)

    static let can = FoodItem(
        id: "can", emoji: "🥫", nameKey: "food.can",
        price: 14, satietyRestore: 1.0, moodBonus: 0.10, grantsBoost: false)

    /// 卖的是 buff 和心情，不是饱食效率。
    /// 刻意设计成「略微亏本」—— 让它是一种经营选择，而非最优解。
    static let driedFish = FoodItem(
        id: "dried_fish", emoji: "🐟", nameKey: "food.dried_fish",
        price: 32, satietyRestore: 1.0, moodBonus: 0.25, grantsBoost: true)

    static let all: [FoodItem] = [.scraps, .kibble, .can, .driedFish]

    static func byID(_ id: String) -> FoodItem? {
        all.first { $0.id == id }
    }

    // MARK: - 「能管多久」

    /// 满值时能维持多久（小时）。用于商店里的静态标注。
    var hoursAtFull: Double {
        satietyRestore * (PetState.Decay.hunger / 3600)
    }

    /// 在当前饱食度下**实际**能维持多久（小时）。
    ///
    /// ⚠️ 恢复是「加到当前值并封顶 100%」，所以半饱时吃罐头只补 50%。
    /// 静态标注会让用户觉得被骗，所以 UI 用这个动态值，
    /// 顺便能提示「现在吃好东西浪费了」。
    func effectiveHours(currentSatiety: Double) -> Double {
        let after = min(1.0, currentSatiety + satietyRestore)
        let gained = max(0, after - currentSatiety)
        return gained * (PetState.Decay.hunger / 3600)
    }

    /// 当前吃是否浪费（实际恢复不足标称的 70%）
    func isWasteful(currentSatiety: Double) -> Bool {
        guard satietyRestore > 0 else { return false }
        let after = min(1.0, currentSatiety + satietyRestore)
        return (after - currentSatiety) < satietyRestore * 0.7
    }
}
