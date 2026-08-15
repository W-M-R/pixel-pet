import SpriteKit

/// 房间配色。
///
/// **用 `Pixel.RGB` 而非裸 `SKColor` 的原因**：`PetHomeView` 的背景兜底色
/// 原来是手抄的墙色字面量 `Color(red: 0.85, green: 0.78, blue: 0.68)` ——
/// 和这里的 `wall` 同值但各写一份。改墙色时改了一处忘了另一处，
/// AppIcon 的配色至今还是更早的冷蓝紫，就是这个结构的后果。
///
/// `Pixel.RGB` 同时提供 `.color`（SwiftUI）和 `.sk`（SpriteKit），
/// 所以两层能引用同一个定义。
enum RoomPalette {
    // 墙：暖调米色，比原来的冷紫更像家里
    static let wall         = Pixel.RGB(0.85, 0.78, 0.68)
    static let wallStripe   = Pixel.RGB(0.82, 0.755, 0.655)

    // 地板：木色，和墙有明确冷暖/明度区分
    static let floor        = Pixel.RGB(0.62, 0.44, 0.31)
    static let floorSeam    = Pixel.RGB(0.50, 0.34, 0.23)
    static let floorAlt     = Pixel.RGB(0.58, 0.41, 0.29)
    static let skirtingDark = Pixel.RGB(0.38, 0.26, 0.19)
    static let skirtingLite = Pixel.RGB(0.72, 0.56, 0.42)

    // 窗外夜景
    static let sky          = Pixel.RGB(0.14, 0.19, 0.36)
    static let hill         = Pixel.RGB(0.17, 0.27, 0.31)
    static let hillFar      = Pixel.RGB(0.20, 0.24, 0.36)
    static let moon         = Pixel.RGB(0.98, 0.96, 0.86)
    static let frameDark    = Pixel.RGB(0.35, 0.24, 0.18)
    /// 与 skirtingLite 同值 —— 窗台和踢脚线本来就该是同一种木料
    static let sill         = Pixel.RGB(0.72, 0.56, 0.42)

    // 挂画
    static let artBg        = Pixel.RGB(0.56, 0.72, 0.78)
    static let artHill      = Pixel.RGB(0.42, 0.60, 0.42)
    static let artSun       = Pixel.RGB(0.96, 0.80, 0.42)

    // 壁灯
    static let lampShade    = Pixel.RGB(0.90, 0.74, 0.44)
    static let lampGlow     = Pixel.RGB(1.00, 0.92, 0.70)

    // 台词气泡
    static let speechFill   = Pixel.RGB(0.98, 0.97, 0.94)
    static let speechBorder = Pixel.RGB(0.24, 0.20, 0.24)
    static let speechText   = Pixel.RGB(0.18, 0.16, 0.20)

    // 食盆（原来散在 dropFoodBowl 里，一并收进来）
    static let bowlDark     = Pixel.RGB(0.42, 0.26, 0.20)
    static let bowlLite     = Pixel.RGB(0.58, 0.38, 0.28)
    static let bowlFood     = Pixel.RGB(0.80, 0.58, 0.30)
}
