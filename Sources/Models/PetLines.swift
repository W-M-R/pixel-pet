import Foundation

/// 预写台词库。
///
/// 这不是"AI 不可用时的降级方案"，而是**主路径**：
/// - 中文环境：AI 模型在 350M 规模下中文不成句（实测"我哭了哭，饿了哭"），
///   所以中文只用这里的台词
/// - 英文环境：先立刻显示这里的台词，AI 在后台生成，出来了再替换
///   （AI 首句要 2-6 秒，不能让宠物干等）
/// - 模型未加载/设备不支持：全部用这里
///
/// 台词通过 Localizable.xcstrings 本地化，key 形如 `line.hungry.1`。
enum PetLines {

    /// 台词分组。和 PetLineContext.Trigger + 状态组合对应。
    enum Category: String, CaseIterable {
        case hungry
        case veryHungry
        case bored
        case dirty
        case sleepy
        case happy
        case greeting
        case fed
        case stroked
        case cleaned
        case wokenUp
        case longAbsence

        /// 每组的台词条数，用于随机挑选。
        /// 改这里要同步在 Localizable.xcstrings 里加对应 key。
        var count: Int {
            switch self {
            case .hungry, .bored, .dirty, .sleepy, .happy: return 4
            case .veryHungry, .greeting, .fed, .stroked, .cleaned: return 3
            case .wokenUp, .longAbsence: return 3
            }
        }
    }

    /// 按宠物状态选出最合适的一句。
    ///
    /// 优先级：触发动作 > 紧急生理需求 > 一般状态。
    /// 因为刚喂完就说"我好饿"会很怪。
    static func line(for context: PetLineContext, absentDays: Int = 0) -> String {
        let category = pickCategory(context, absentDays: absentDays)
        let index = Int.random(in: 1...category.count)
        let key = "line.\(category.rawValue).\(index)"
        // 用 L() 而非 NSLocalizedString —— 后者锁定进程启动语言，
        // 应用内切语言时台词不会跟着变。
        let format = L(key)
        // 支持 %@ 占位符插宠物名
        if format.contains("%@") {
            return String(format: format, context.name)
        }
        return format
    }

    private static func pickCategory(_ c: PetLineContext, absentDays: Int) -> Category {
        // 久别重逢优先，这是最有情绪价值的时刻
        if c.trigger == .appeared, absentDays >= 3 { return .longAbsence }

        switch c.trigger {
        case .fed:      return .fed
        case .stroked:  return .stroked
        case .cleaned:  return .cleaned
        case .wokenUp:  return .wokenUp
        case .appeared: break
        }

        // 台词的阈值比 HUD 更严 —— 台词低频触发，只在真的很惨时说重话
        if c.satiety < StateThreshold.lineUrgent { return .veryHungry }
        if c.satiety < StateThreshold.lineMild { return .hungry }
        if c.hygiene < StateThreshold.critical { return .dirty }
        if c.mood < StateThreshold.critical { return .bored }
        if c.isDrowsy { return .sleepy }
        if c.mood > StateThreshold.lineHappy { return .happy }
        return .greeting
    }
}
