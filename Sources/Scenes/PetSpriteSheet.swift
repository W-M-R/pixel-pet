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

    /// 预放大倍数。
    ///
    /// **这是修「走动时一闪一闪」的关键。**
    ///
    /// 问题的本质：宠物按屏幕 y 连续缩放（2.5D 伪深度），而 nearest 采样下
    /// 非整数缩放会让 texel 落在屏幕像素边界上 —— 部分 texel 渲染成 2 个
    /// 物理像素、部分 1 个，且「哪些变胖」随缩放连续漂移，逐帧重新分配。
    ///
    /// 试过把缩放量化到 1/3 网格（Unity Pixel Perfect Camera 的思路），
    /// 但那套方案的前提是**全场景共用一个像素网格**；伪深度让每只宠物在
    /// 不同 y 有不同缩放，前提不成立。实测结果是把连续抖动换成了 11% 的
    /// 单步跳档（young 只有 3.0 / 2.667 / 2.333 三档），反而更刺眼。
    ///
    /// 正解是**先用 nearest 整数放大到 8 倍**得到一张「像素块已经烘死」的
    /// 大图，再让 SpriteKit 用 **linear** 对它做连续缩小。
    /// 这样 texel 边界永远由 bilinear 平滑处理，不存在帧间跳变。
    ///
    /// 代价是显存 ×64，但 32×32 的素材放大到 256×256 只有 256KB 级，可忽略。
    static let prescale = 8

    /// 预放大后的纹理缓存。
    ///
    /// key 要包含所有影响像素的因素。不缓存会每帧重新走 CGContext 放大，
    /// 那比抖动问题严重得多。
    private static var cache: [String: SKTexture] = [:]

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

        let sub = SKTexture(rect: rect, in: sheet)
        sub.filteringMode = .nearest

        // 缓存键：sheet 尺寸能区分不同阶段的 sheet（它们尺寸相同但内容不同，
        // 所以还要带上 description 里的纹理标识）
        let key = "\(sheet.description)|\(row)|\(column)|\(colorIndex)"
        if let hit = cache[key] { return hit }

        let scaled = upscaled(sub)
        cache[key] = scaled
        return scaled
    }

    /// 用 nearest 把小图整数放大，结果交给 linear 做连续缩放。
    ///
    /// `interpolationQuality = .none` 是关键 —— 放大这一步必须保持硬边，
    /// 否则像素画会先被糊一次。
    static func upscaled(_ tex: SKTexture) -> SKTexture {
        let src = tex.cgImage()
        let w = Int(frameSize.width) * prescale
        let h = Int(frameSize.height) * prescale

        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            tex.filteringMode = .nearest
            return tex
        }
        ctx.interpolationQuality = .none      // 硬边放大，别插值
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let out = ctx.makeImage() else {
            tex.filteringMode = .nearest
            return tex
        }
        let result = SKTexture(cgImage: out)
        // 放大图用 linear：缩小时由 bilinear 平滑 texel 边界，消除逐帧跳变
        result.filteringMode = .linear
        return result
    }

    /// 每行实际的有效帧数。
    ///
    /// ⚠️ **正视/背视只有 3 帧，第 4 格不可用。**
    ///
    /// 实测（解码 PNG 逐格量内容宽度，只看第一个毛色）：
    /// ```
    /// cat r0 侧视: [24,24,23,23] ✅      dog r0 侧视: [26,27,26,24] ✅
    /// cat r1 正视: [13,13,13, 0] ⚠️      dog r1 正视: [11,11,11,25] ⚠️
    /// cat r2 背视: [13,13,13, 0] ⚠️      dog r2 背视: [11,11,11,27] ⚠️
    /// cat r3 侧视: [23,24,24,23] ✅      dog r3 侧视: [26,27,26,24] ✅
    /// cat r4 进食: [13,13,13,13] ✅      dog r4 进食: [11,11,11,11] ✅
    /// ```
    ///
    /// 猫的第 4 格是**空的**；狗的第 4 格**非空但是另一个姿态**
    /// （侧躺的狗，宽 25-27px vs 正常 11px）。两种都会造成
    /// 宠物朝前/朝后走时画面突变 —— 表现为"头尾分离"。
    ///
    /// 判定不依赖物种名：这是 LPC sheet 的统一布局，
    /// 加新宠物也适用。
    static func frameCount(row: Int) -> Int {
        (row == Facing.front.row || row == Facing.back.row) ? 3 : columnsPerColor
    }

    static func frames(from sheet: SKTexture,
                       action: Action,
                       colorIndex: Int) -> [SKTexture] {
        (0..<frameCount(row: action.row)).map {
            texture(from: sheet, row: action.row, column: $0, colorIndex: colorIndex)
        }
    }

    /// 睡觉 sheet（自绘补的，主 sheet 里确认没有 sleep 帧）。
    /// 布局 4 列(毛色) × 2 行(呼气/吸气)，每格 32×32。
    /// 生成脚本 tools/make_sleep.py —— 调色板从主 sheet 自动提取，
    /// 保证 4 种毛色与走路帧一致。
    enum Sleep {
        static let columns = 4
        static let rows = 2
    }

    static func sleepFrames(from sheet: SKTexture, colorIndex: Int) -> [SKTexture] {
        let sheetW = sheet.size().width
        let sheetH = sheet.size().height
        guard sheetW > 0, sheetH > 0 else { return [] }

        return (0..<Sleep.rows).map { row in
            let flippedRow = Sleep.rows - row - 1   // Y 翻转
            let rect = CGRect(x: CGFloat(colorIndex) * frameSize.width / sheetW,
                              y: CGFloat(flippedRow) * frameSize.height / sheetH,
                              width: frameSize.width / sheetW,
                              height: frameSize.height / sheetH)
            let tex = SKTexture(rect: rect, in: sheet)
            tex.filteringMode = .nearest
            return tex
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
