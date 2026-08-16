import Foundation

/// 台词系统的状态快照。
///
/// **为什么不直接传 `PetState`**：台词只关心「饿不饿」这种语义，
/// 不需要知道饱食度是怎么从时间戳算出来的。
/// `PetLines` 因此是纯函数，可以脱离 store 测试。
///
/// 曾经这里还有 `chineseStateDescription` / `englishStateDescription`
/// 两个 prompt 构造属性（给设备端 AI 模型看的自然语言描述），
/// 随 AI 功能一起删除。`species` / `chineseSpecies` 两个字段也只有
/// prompt 用得到，一并拔掉。
struct PetLineContext {
    var name: String
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
}
