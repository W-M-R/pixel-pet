import Foundation
import CoreGraphics

/// 生命阶段。
///
/// 帧由 `tools/make_stages.py` 从成年帧程序化派生：
/// 抽躯干行改变头身比（幼体头占比更大），老年额外褪色。
/// 不是整体缩放 —— 那样头也变小，看起来只是「同一只宠物远了一点」。
enum PetStage: String, Codable, CaseIterable, Sendable {
    case young      // 幼年
    case growing    // 成长期
    case adult      // 成年
    case elder      // 老年

    /// 进入该阶段所需的天数下限
    var minDays: Int {
        switch self {
        case .young:   return 0
        case .growing: return 3
        case .adult:   return 7
        case .elder:   return 30
        }
    }

    /// 按相伴天数判断当前阶段
    static func forAge(days: Int) -> PetStage {
        // 从大到小找第一个够条件的
        for stage in [PetStage.elder, .adult, .growing, .young]
        where days >= stage.minDays {
            return stage
        }
        return .young
    }

    /// 距离下一阶段还差几天。已是最终阶段返回 nil。
    func daysToNext(from days: Int) -> Int? {
        let all = PetStage.allCases.sorted { $0.minDays < $1.minDays }
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return max(0, all[idx + 1].minDays - days)
    }

    var displayNameKey: String { "stage.\(rawValue)" }

    /// 体型缩放系数。
    ///
    /// 光靠抽行（改头身比）不够 —— 实测只差 2-6px，在 pixelScale=4 下
    /// 肉眼几乎不可辨。所以再叠一层整体缩放，让「大小」也有区别。
    ///
    /// 注意必须是能让 pixelScale 保持接近整数倍的值，
    /// 否则像素网格会错位、边缘发虚。pixelScale=4 时：
    ///   0.75 → 3.0 ✅ 整数
    ///   0.875 → 3.5 ⚠️ 半像素，但 32×32 源图下肉眼可接受
    ///   1.0 → 4.0 ✅
    var bodyScale: CGFloat {
        switch self {
        case .young:   return 0.75
        case .growing: return 0.875
        case .adult:   return 1.0
        case .elder:   return 0.94
        }
    }

    /// 该阶段的 sheet 后缀。成年直接用源图，没有后缀。
    var sheetSuffix: String? {
        self == .adult ? nil : rawValue
    }

    // MARK: - 经济参数

    /// 每日收益额度。
    ///
    /// 养大了赚得多。elder 略低于 adult（和 `bodyScale` 的 0.94 < 1.0 同构）：
    /// 老年期回落但仍高于幼年，不惩罚长期玩家。
    ///
    /// 硬约束：**必须大于该阶段的日常粮钱**，否则新手期怎么玩都亏。
    /// 日常粮钱 ≈ (24/`hungerCycleHours`) × 10 × `FoodItem.coinsPer10Percent`
    /// = 幼 100 / 成长 120 / 成年 150 / 老年 133。
    ///
    /// 峰值净结余 = `dailyCap` − 日常粮钱，与达成率无关 ——
    /// 所以「攒钱节奏」和「状态影响多大」是两个独立旋钮。
    var dailyCap: Int {
        switch self {
        case .young:   return 170
        case .growing: return 195
        case .adult:   return 225
        case .elder:   return 205
        }
    }

    /// 饱食衰减周期（小时）。**小宠物吃得少。**
    ///
    /// 按阶段区分是为了解耦两件事：如果所有阶段共用 8 小时，
    /// 那么幼年的支出标准和成年一样，但额度更低 —— 幼年必亏，
    /// 且「阶段差异」与「收支平衡」被压在同一个旋钮上，调不开。
    var hungerCycleHours: Double {
        switch self {
        case .young:   return 12
        case .growing: return 10
        case .adult:   return 8
        case .elder:   return 9
        }
    }
}

/// 宠物品种。
///
/// 抽象成一个可注册的表，加新宠物只需：
/// 1. 把 `<id>.png`（LPC 布局：16 列 × 8 行，32×32 格）放进 Assets/pets/
/// 2. 跑 `python3 tools/make_stages.py --pets <id>` 生成阶段帧
/// 3. 在 `PetBreed.all` 里加一条
/// 4. 补 `breed.<id>` 的本地化文案
///
/// 不需要改渲染代码。
struct PetBreed: Identifiable, Hashable, Codable, Sendable {
    /// 同时是 Assets/pets/ 下的文件名
    let id: String
    /// 本地化 key
    let nameKey: String
    /// 该 sheet 有几种毛色（LPC 标准是 4）
    let colorCount: Int
    /// 侧视帧里内容底边到格子底边的空白行数（源像素）。
    ///
    /// 决定影子、食盆、气泡挂在哪 —— 写死一个值的话，
    /// 轮廓不同的品种会出现「影子和脚脱开」。
    ///
    /// 实测（解码 PNG 逐行扫 alpha，r0c0 侧视帧）：
    ///   cat 内容底边 y=26 → 31-26 = 5
    ///   dog 内容底边 y=28 → 31-28 = 3
    /// 原来 `PetScene` 硬编码 5（按猫测的），所以**狗的影子和食盆
    /// 一直偏了 2 源像素（8pt）**。
    let footPadding: CGFloat

    /// AI 台词里描述物种用的英文词
    let englishNoun: String
    /// AI 台词里描述物种用的中文词。
    /// 单独存而不是拿 nameKey 查表 —— prompt 要的是「小猫」这种口语称呼，
    /// 而 nameKey 的译文是「猫」这种正式名。
    let chineseNoun: String

    // MARK: - 属性差异

    /// 售价（硬币）。0 = 开局赠送的基础品种。
    ///
    /// 定价推导见 docs/07-shop.md：中高频（3-4 次/天）约 30 天买得起，
    /// 中频 44 天，低频基本买不起。
    let price: Int

    /// 性格标签的本地化 key。给玩家看的一句话概括。
    let traitKey: String

    /// 心情衰减周期（小时）。**越短越黏人** —— 要更频繁陪玩。
    ///
    /// 这是唯一真正影响收益的属性差异：心情占达成率 60% 权重，
    /// 周期短则同样间隔下平均心情更低。
    let moodCycleHours: Double

    /// 清洁衰减周期（小时）。
    ///
    /// ⚠️ **不影响收益** —— 清洁不在达成率公式里（72h 周期让它长期接近
    /// 1.0，放进去只会稀释另两维，见 RewardRule 的注释）。
    /// 它影响的是「多久要洗一次澡」这个操作频率，属于体验差异。
    let hygieneCycleHours: Double

    /// 金币加成。用来**抵消** moodCycleHours 的优劣，让高频玩家
    /// 无论选哪只收益都接近。
    ///
    /// 配平方式见 docs/07-shop.md：反解出「4 次/天日净结余相等」的系数。
    /// 实测四个品种在 4 次/天时完全持平（都是 +96），
    /// 只在低频（2 次/天）才出现 +6~+12 的差异 ——
    /// 这正是想要的：**认真照顾的玩家不被品种选择惩罚**。
    let goldMultiplier: Double

    /// 是否是开局可选的基础品种
    var isStarter: Bool { price == 0 }

    var sheetName: String { id }

    /// 某阶段的 sheet 文件名
    func sheetName(for stage: PetStage) -> String {
        guard let suffix = stage.sheetSuffix else { return id }
        return "\(id)_\(suffix)"
    }

    /// 睡觉 sheet（自绘的，不分阶段）
    var sleepSheetName: String { "\(id)_sleep" }

    // MARK: - 注册表

    /// 猫：均衡型，开局可选
    static let cat = PetBreed(
        id: "cat", nameKey: "breed.cat",
        colorCount: 4, footPadding: 5,
        englishNoun: "cat", chineseNoun: "小猫",
        price: 0, traitKey: "trait.balanced",
        moodCycleHours: 18, hygieneCycleHours: 72, goldMultiplier: 1.00)

    /// 狗：黏人型，开局可选。心情掉得快，但金币加成更高。
    ///
    /// ⚠️ 金币曾是 1.05，那时**猫在全部四个阶段都支配狗**
    /// （4 次/天打平，1-3 次/天猫都更高，狗没有任何频次占优）。
    ///
    /// 根因：1.05 是按「4 次/天日净结余相等」反解的，但那个点双方都
    /// 撞额度上限、加成被 `min(remainingCap, ...)` 吃掉，所以「打平」是假象。
    /// 低频时加成生效了，可心情劣势也生效，狗就纯亏。
    ///
    /// 1.10 让差值变成 1次 +0 / 2次 −2 / 3次 +3 / 4次 +8 ——
    /// 猫在低频占优、狗在高频占优，支配关系消失。
    /// 由 `ConfigTests.testNoBreedDominatesAnother` 守着。
    static let dog = PetBreed(
        id: "dog", nameKey: "breed.dog",
        colorCount: 4, footPadding: 3,
        englishNoun: "dog", chineseNoun: "小狗",
        price: 0, traitKey: "trait.clingy",
        moodCycleHours: 14, hygieneCycleHours: 72, goldMultiplier: 1.10)

    /// 开局可选的品种（免费）
    static var starters: [PetBreed] { all.filter(\.isStarter) }

    /// 商店里能买的品种
    static var purchasable: [PetBreed] { all.filter { !$0.isStarter } }

    static let all: [PetBreed] = [.cat, .dog]

    static func byID(_ id: String) -> PetBreed {
        all.first { $0.id == id } ?? .cat
    }
}
