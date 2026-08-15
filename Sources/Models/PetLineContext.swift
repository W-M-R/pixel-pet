import Foundation

/// 台词系统的状态快照。
///
/// **为什么独立成文件**：它原来住在 `PetChatEngine.swift` 里，但
/// **两套台词系统共用它** —— AI 生成（`PetChatEngine`）和预写台词
/// （`PetLines`）都以它为输入。放在 AI 引擎里会让人以为它是 AI 专属的。
///
/// 也让引擎不必依赖 `PetState`/`PetStore`：台词只关心「饿不饿」这种语义，
/// 不需要知道时间戳怎么算。
struct PetLineContext {
    var name: String
    var species: String
    /// 中文物种称呼。由 PetBreed.chineseNoun 传入 ——
    /// 原来是 `species == "dog" ? "小狗" : "小猫"` 的硬编码三元，
    /// 加第三个品种会全部显示成「小猫」。
    var chineseSpecies: String
    var satiety: Double
    var mood: Double
    var hygiene: Double
    var isDrowsy: Bool
    var ageInDays: Int
    var trigger: Trigger

    enum Trigger {
        case appeared          // 打开 app
        case fed
        case stroked
        case cleaned
        case wokenUp
    }

    /// 给模型看的中文状态描述。与英文版一一对应。
    var chineseStateDescription: String {
        var parts: [String] = []

        switch trigger {
        case .appeared:  parts.append("主人刚刚打开了 app。")
        case .fed:       parts.append("主人刚刚喂了你。")
        case .stroked:   parts.append("主人刚刚摸了你的头。")
        case .cleaned:   parts.append("主人刚刚给你洗了澡。")
        case .wokenUp:   parts.append("主人刚刚把你叫醒了。")
        }

        // 阈值走 StateThreshold —— 原来中英文各写一份 0.25/0.5，
        // 改一边忘一边会让两种语言描述出不同的宠物状态。
        switch StateThreshold.level(satiety) {
        case .critical: parts.append("你非常饿。")
        case .low:      parts.append("你有点饿。")
        default:        break
        }

        switch StateThreshold.level(mood) {
        case .critical, .low: parts.append("你觉得无聊寂寞。")
        case .high:           parts.append("你很开心。")
        case .ok:             break
        }

        if StateThreshold.level(hygiene) <= .low { parts.append("你觉得脏。") }
        if isDrowsy { parts.append("现在很晚了，你很困。") }
        if ageInDays >= 7 { parts.append("你已经在这里住了 \(ageInDays) 天。") }

        parts.append("说一句很短的话。")
        return parts.joined(separator: "")
    }

    /// 给模型看的英文状态描述。
    /// 用自然语言而不是数字，小模型对 "very hungry" 的理解好过 "satiety: 0.12"。
    var englishStateDescription: String {
        var parts: [String] = []

        switch trigger {
        case .appeared:  parts.append("Your owner just opened the app.")
        case .fed:       parts.append("Your owner just fed you.")
        case .stroked:   parts.append("Your owner just petted your head.")
        case .cleaned:   parts.append("Your owner just gave you a bath.")
        case .wokenUp:   parts.append("Your owner just woke you up.")
        }

        // 档位判断与 chineseStateDescription 完全一致 ——
        // 两边都走 StateThreshold.level，不会再漂移
        switch StateThreshold.level(satiety) {
        case .critical: parts.append("You are very hungry.")
        case .low:      parts.append("You are a bit hungry.")
        default:        break
        }

        switch StateThreshold.level(mood) {
        case .critical, .low: parts.append("You feel bored and lonely.")
        case .high:           parts.append("You feel happy.")
        case .ok:             break
        }

        if StateThreshold.level(hygiene) <= .low { parts.append("You feel dirty.") }
        if isDrowsy { parts.append("It is late and you are sleepy.") }
        if ageInDays >= 7 { parts.append("You have lived here for \(ageInDays) days.") }

        parts.append("Say one short sentence.")
        return parts.joined(separator: " ")
    }
}
