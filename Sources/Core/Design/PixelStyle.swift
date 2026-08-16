import SwiftUI
import SpriteKit

/// 全项目的视觉常量。
///
/// **为什么在 `Core/Design/` 而不是 `Views/`**：它被 `Scenes/RoomPalette`
/// 依赖（那 38 个颜色全是 `Pixel.RGB`），放在 Views 会形成
/// `Scenes → Views` 的反向依赖。设计 token 是基础设施，不是视图。
///
/// ⚠️ 它 `import SpriteKit` 只为 `RGB.sk` 产 `SKColor`（跨层同色的关键）。
/// 这让 Core 层链 SpriteKit —— 可以用 `#if canImport` 隔离，
/// 但那样 `RoomPalette` 就用不了 `.sk` 了，得不偿失。
///
/// **建这一层的原因**：之前 SpriteKit 侧有 `PetScene.Palette` 约束配色，
/// SwiftUI 侧却完全没有对应约束 —— 于是散落出 4 种圆角、4 种白色叠层、
/// 10 种字号、3 套进度条实现。单看每处都合理，叠起来就是「不精致」。
///
/// 所有颜色同时提供 `Color`（SwiftUI）和 `SKColor`（SpriteKit）两种形态，
/// 保证两层永远同色。改一处即可全局生效。
enum Pixel {

    // MARK: - 网格

    /// 1 源像素 = 多少 pt。UI 的所有尺寸都应是它的整数倍，
    /// 这样边界落在物理像素上，不会出现半像素的模糊边。
    static let unit: CGFloat = 4

    /// 把任意长度吸附到像素网格
    static func snap(_ v: CGFloat) -> CGFloat {
        (v / unit).rounded() * unit
    }

    /// n 个像素单位
    static func u(_ n: CGFloat) -> CGFloat { n * unit }

    // MARK: - 配色
    //
    // 与房间同一套暖木色体系。原来 HUD 用 .black.opacity(0.32) 的
    // 「iOS 玻璃感」，压在像素房间上风格直接对撞，所以换成实色木质面板。

    /// 面板底色：深木色，不透明 —— 像素风不用半透明
    static let panel = RGB(0.20, 0.15, 0.12)
    /// 面板高光边（上/左）
    static let panelLite = RGB(0.42, 0.31, 0.23)
    /// 面板阴影边（下/右）
    static let panelDark = RGB(0.12, 0.09, 0.07)

    /// 按钮常态
    static let button = RGB(0.50, 0.37, 0.27)
    static let buttonLite = RGB(0.62, 0.47, 0.34)
    static let buttonDark = RGB(0.28, 0.20, 0.14)
    /// 按钮按下
    static let buttonPressed = RGB(0.36, 0.26, 0.19)

    /// 主文字：暖白，不用纯白 —— 纯白在木色上太刺眼
    static let text = RGB(0.96, 0.93, 0.86)
    /// 次要文字
    static let textDim = RGB(0.72, 0.65, 0.56)

    /// 状态条三色。原来用系统 orange/pink/cyan，
    /// cyan 尤其跳出暖木色体系，换成同色系但仍可区分的三色。
    static let satiety = RGB(0.91, 0.66, 0.29)   // 暖橙（食物）
    static let mood    = RGB(0.85, 0.45, 0.48)   // 玫红（心情）
    static let hygiene = RGB(0.52, 0.72, 0.78)   // 雾蓝（清洁）
    /// 状态过低的警示色
    static let warn    = RGB(0.82, 0.31, 0.28)

    /// 状态条空槽
    static let slotEmpty = RGB(0.14, 0.11, 0.09)

    /// 金币色
    static let coin = RGB(0.95, 0.78, 0.32)

    // MARK: - 字号
    //
    // 原来有 9/10/11/12/13/15/17/22/26/30pt 共 10 种，
    // 9pt/10pt 配 opacity(0.6) 小到接近不可读。收敛成 4 档。

    /// 标题（宠物名）
    static let titleSize: CGFloat = 17
    /// 正文
    static let bodySize: CGFloat = 13
    /// 标签（原 9-11pt 统一提到 12，中文在 9pt 下会糊）
    static let labelSize: CGFloat = 12
    /// 数字（金币等，等宽）
    static let numberSize: CGFloat = 15

    /// 等宽字体 —— 没有像素字体，用 monospaced 近似。
    /// 台词气泡的 Menlo 也统一到这里，消除「两种等宽字体」的不一致。
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - 颜色载体

    /// 同时能转成 SwiftUI Color 和 SpriteKit SKColor
    struct RGB {
        let r, g, b: CGFloat
        init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
            self.r = r; self.g = g; self.b = b
        }
        var color: Color { Color(red: r, green: g, blue: b) }
        var sk: SKColor { SKColor(red: r, green: g, blue: b, alpha: 1) }
        func opacity(_ a: Double) -> Color { color.opacity(a) }
    }
}

// MARK: - 像素面板

/// 像素风面板背景：实色 + 上下两条明暗边。
///
/// 不用圆角 —— 圆角需要抗锯齿曲线，和 nearest 采样的硬边像素直接打架。
/// 这是原来 HUD 最扎眼的地方（cornerRadius 14 的玻璃卡片压在像素房间上）。
struct PixelPanel: View {
    var fill: Pixel.RGB = Pixel.panel
    var lite: Pixel.RGB = Pixel.panelLite
    var dark: Pixel.RGB = Pixel.panelDark
    /// 边框粗细（像素单位）
    var border: CGFloat = 1

    var body: some View {
        let b = Pixel.u(border)
        ZStack {
            fill.color
            VStack(spacing: 0) {
                lite.color.frame(height: b)      // 上高光
                Spacer(minLength: 0)
                dark.color.frame(height: b)      // 下阴影
            }
            HStack(spacing: 0) {
                lite.color.frame(width: b)       // 左高光
                Spacer(minLength: 0)
                dark.color.frame(width: b)       // 右阴影
            }
        }
    }
}

extension View {
    /// 套一层像素面板背景
    func pixelPanel(fill: Pixel.RGB = Pixel.panel,
                    lite: Pixel.RGB = Pixel.panelLite,
                    dark: Pixel.RGB = Pixel.panelDark) -> some View {
        background(PixelPanel(fill: fill, lite: lite, dark: dark))
    }
}

// MARK: - 像素状态条

/// 分格状态条。
///
/// 原来是 `Capsule()` 胶囊 —— 抗锯齿曲线边缘和像素硬边冲突最明显的地方。
/// 改成离散方块格：既是像素风的标准做法，也让数值更易读
/// （数格子比估长度准）。
struct PixelBar: View {
    let value: Double
    let tint: Pixel.RGB
    /// 分几格
    var slots: Int = 10

    private var filled: Int {
        max(0, min(slots, Int((value * Double(slots)).rounded())))
    }

    /// 低于 30% 变警示色 —— 这条逻辑原来在两个文件各写一遍
    private var color: Pixel.RGB {
        value < 0.3 ? Pixel.warn : tint
    }

    var body: some View {
        HStack(spacing: Pixel.u(0.5)) {
            ForEach(0..<slots, id: \.self) { i in
                Rectangle()
                    .fill(i < filled ? color.color : Pixel.slotEmpty.color)
            }
        }
        .frame(height: Pixel.u(2))
    }
}

// MARK: - List 像素化

extension View {
    /// 把原生 List 的行背景换成像素木色。
    ///
    /// 只改配色不自绘控件 —— `Toggle` / `TextField` / `Picker` 的
    /// 无障碍支持、键盘处理、滚动行为都是大量隐性工作，
    /// 自绘的收益远小于风险。
    func listRowBackgroundPixel() -> some View {
        listRowBackground(
            PixelPanel(fill: Pixel.button,
                       lite: Pixel.buttonLite,
                       dark: Pixel.buttonDark)
        )
    }
}
