import Foundation

/// 宠物当前最需要什么。
///
/// **从 PetState 抽出来的原因**：「哪个需求最紧急」是一条**展示决策**
/// （HUD 显示哪个图标、说哪类台词），不是状态存储。
/// 它依赖 `StateThreshold.hudAlert`，而 `PetState` 本身不该关心
/// 「多低才算需要提示」这种产品判断。
enum PetNeed: String, CaseIterable {
    case hungry
    case bored
    case dirty
    case sleepy
    case content

    /// 自绘图标 sheet（`Assets/ui/icons.png`）里的格位。
    ///
    /// **为什么是裸索引而不是 `PixelIcon`**：`PixelIcon` 住 Views 层，
    /// 而 Models 不得引用 Views（见 tools/check_layers.sh）。
    /// 两边的顺序都由 `tools/make_ui_icons.py` 的 ORDER 定义，
    /// 由 `testNeedIconIndicesMatchPixelIcon` 断言一致。
    ///
    /// 曾经这里是 emoji 表 —— emoji 字形随 iOS 版本变，
    /// 缺字体时渲染成问号，渐变高光也会把像素感压掉。
    var iconIndex: Int {
        switch self {
        case .hungry:  return 0     // meat
        case .bored:   return 1     // ball
        case .dirty:   return 2     // bath
        case .sleepy:  return 10    // sleep
        case .content: return 8     // heart
        }
    }

    var messageKey: String { "need.\(rawValue)" }
}

extension PetState {
    /// 取最紧急的需求。
    ///
    /// 顺序：生理需求优先于困倦 —— 饿着的时候不该只显示「困了」。
    /// 阈值见 `StateThreshold.hudAlert`（比台词的阈值宽松，
    /// 因为状态栏一直报警会让人焦虑）。
    func dominantNeed(at now: Date = Date()) -> PetNeed {
        let candidates: [(PetNeed, Double)] = [
            (.hungry, satiety(at: now)),
            (.bored,  mood(at: now)),
            (.dirty,  hygiene(at: now))
        ]
        if let worst = candidates.min(by: { $0.1 < $1.1 }),
           worst.1 < StateThreshold.hudAlert {
            return worst.0
        }
        if isDrowsy(at: now) { return .sleepy }
        return .content
    }
}
