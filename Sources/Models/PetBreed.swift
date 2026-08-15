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
    /// AI 台词里描述物种用的英文词
    let englishNoun: String

    var sheetName: String { id }

    /// 某阶段的 sheet 文件名
    func sheetName(for stage: PetStage) -> String {
        guard let suffix = stage.sheetSuffix else { return id }
        return "\(id)_\(suffix)"
    }

    /// 睡觉 sheet（自绘的，不分阶段）
    var sleepSheetName: String { "\(id)_sleep" }

    // MARK: - 注册表

    static let cat = PetBreed(id: "cat", nameKey: "breed.cat",
                              colorCount: 4, englishNoun: "cat")
    static let dog = PetBreed(id: "dog", nameKey: "breed.dog",
                              colorCount: 4, englishNoun: "dog")

    static let all: [PetBreed] = [.cat, .dog]

    static func byID(_ id: String) -> PetBreed {
        all.first { $0.id == id } ?? .cat
    }
}
