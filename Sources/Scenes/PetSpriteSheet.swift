import SpriteKit

/// LPC「Cats and Dogs」sprite sheet 的帧布局。
///
/// 布局是实测出来的（解码 PNG 逐格扫 alpha + 亮度重心），不是猜的：
/// - 512×256，帧 32×32，16 列 × 8 行，仅前 5 行有内容
/// - 每 4 列为一个动画循环，横向重复 4 次 = 4 种毛色
/// - r0 侧视朝右 / r1 朝前(镜头) / r2 朝后 / r3 侧视朝左 / r4 吃东西
///
/// 朝向判定依据：每列不透明高度剖面里头部更高。
/// r0 在 x=18..22 处高 17-18px（右侧），r3 在 x=10..12 处高 18-19px（左侧）。
///
/// ⚠️ 两个坑：
/// 1. SpriteKit 纹理坐标原点在左下，sheet 行号自上而下，取 rect 必须 Y 翻转。
/// 2. `filteringMode` 不从父纹理继承，每个派生纹理都要单独设，否则放大发虚。
enum PetSpriteSheet {

    static let frameSize = CGSize(width: 32, height: 32)
    static let columnsPerColor = 4
    static let colorCount = 4

    /// 宠物朝向。命名对应 sheet 行。
    enum Facing: Int, CaseIterable {
        case right = 0
        case front = 1   // 面向镜头
        case back  = 2   // 背对镜头
        case left  = 3

        var row: Int { rawValue }
    }

    /// 动作。目前 sheet 里只有 walk（4 向）和 eat。
    /// sleep 缺失——包描述提到 "bonus sleeping images"，但实测 r4 是吃东西的
    /// 咀嚼动画（头部上下小幅移动），没有独立的睡眠帧。第 5 步需要自绘。
    enum Action {
        case walk(Facing)
        case eat

        var row: Int {
            switch self {
            case .walk(let f): return f.row
            case .eat: return 4
            }
        }

        /// 每帧时长。吃东西比走路慢一点，看起来更从容。
        var timePerFrame: TimeInterval {
            switch self {
            case .walk: return 0.14
            case .eat:  return 0.22
            }
        }
    }

    /// 毛色索引 0..<4。LPC 包原文 "Four colors each"。
    struct ColorVariant: Identifiable, Hashable {
        let index: Int
        var id: Int { index }
    }

    static var colorVariants: [ColorVariant] {
        (0..<colorCount).map { ColorVariant(index: $0) }
    }

    static func texture(from sheet: SKTexture,
                        row: Int,
                        column: Int,
                        colorIndex: Int) -> SKTexture {
        let sheetW = sheet.size().width
        let sheetH = sheet.size().height
        guard sheetW > 0, sheetH > 0 else { return sheet }

        let absoluteColumn = colorIndex * columnsPerColor + column
        let originX = CGFloat(absoluteColumn) * frameSize.width
        let rowsInSheet = Int(sheetH / frameSize.height)
        let flippedRow = rowsInSheet - row - 1
        let originY = CGFloat(flippedRow) * frameSize.height

        let rect = CGRect(x: originX / sheetW,
                          y: originY / sheetH,
                          width: frameSize.width / sheetW,
                          height: frameSize.height / sheetH)

        let tex = SKTexture(rect: rect, in: sheet)
        tex.filteringMode = .nearest
        return tex
    }

    static func frames(from sheet: SKTexture,
                       action: Action,
                       colorIndex: Int) -> [SKTexture] {
        (0..<columnsPerColor).map {
            texture(from: sheet, row: action.row, column: $0, colorIndex: colorIndex)
        }
    }

    static func loadSheet(named name: String) -> SKTexture? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            let tex = SKTexture(image: image)
            tex.filteringMode = .nearest
            return tex
        }
        let tex = SKTexture(imageNamed: name)
        guard tex.size().width > 1 else { return nil }
        tex.filteringMode = .nearest
        return tex
    }
}
