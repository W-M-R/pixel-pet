import SpriteKit

/// 精灵表取帧。
///
/// **布局参数不在这里** —— 帧尺寸、毛色数、走路帧序、行语义都由
/// `PetSheetLayout` 提供，`PetBreed` 注入。曾经它们是这个 enum 的
/// 全局 `static let`，导致 `PetBreed.colorCount` 与这里的 `colorCount`
/// 双轨：2 色品种的毛色选择器显示 2 格，渲染却按 4 色算列偏移。
///
/// 这里只剩「怎么取、怎么放大」两件事。
///
/// ⚠️ 两个坑：
/// 1. SpriteKit 纹理坐标原点在左下，sheet 行号自上而下，取 rect 必须 Y 翻转。
/// 2. `filteringMode` 不从父纹理继承，每个派生纹理都要单独设，否则放大发虚。
enum PetSpriteSheet {

    /// 宠物朝向。索引对应 `PetSheetLayout.facingRows`。
    enum Facing: Int, CaseIterable {
        case right = 0
        case front = 1   // 面向镜头
        case back  = 2   // 背对镜头
        case left  = 3

        func row(in layout: PetSheetLayout) -> Int {
            layout.facingRows.indices.contains(rawValue)
                ? layout.facingRows[rawValue]
                : rawValue
        }
    }

    /// 动作。
    enum Action {
        case walk(Facing)
        case eat

        func row(in layout: PetSheetLayout) -> Int {
            switch self {
            case .walk(let f): return f.row(in: layout)
            // 没有进食行时借用侧视行 —— 不换帧也比取到空白好
            case .eat: return layout.eatRow ?? layout.facingRows.first ?? 0
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
                        colorIndex: Int,
                        layout: PetSheetLayout) -> SKTexture {
        let sheetW = sheet.size().width
        let sheetH = sheet.size().height
        guard sheetW > 0, sheetH > 0 else { return sheet }

        // 毛色索引夹到布局声明的范围 —— 越界会取到空白或邻帧（不崩，静默错）。
        // 会越界的实际路径：旧存档的 colorIndex 是 3，切到 2 色品种。
        let color = min(max(0, colorIndex), max(0, layout.colorCount - 1))
        let absoluteColumn = color * layout.columnsPerColor + column
        let cell = layout.cell
        let originX = CGFloat(absoluteColumn) * cell
        let rowsInSheet = Int(sheetH / cell)
        let flippedRow = rowsInSheet - row - 1
        let originY = CGFloat(flippedRow) * cell

        let rect = CGRect(x: originX / sheetW,
                          y: originY / sheetH,
                          width: cell / sheetW,
                          height: cell / sheetH)

        let sub = SKTexture(rect: rect, in: sheet)
        sub.filteringMode = .nearest

        // 缓存键：sheet 尺寸能区分不同阶段的 sheet（它们尺寸相同但内容不同，
        // 所以还要带上 description 里的纹理标识）
        let key = "\(sheet.description)|\(row)|\(column)|\(color)|\(Int(cell))"
        if let hit = cache[key] { return hit }

        let scaled = upscaled(sub, cell: cell)
        cache[key] = scaled
        return scaled
    }

    /// 用 nearest 把小图整数放大，结果交给 linear 做连续缩放。
    ///
    /// `interpolationQuality = .none` 是关键 —— 放大这一步必须保持硬边，
    /// 否则像素画会先被糊一次。
    static func upscaled(_ tex: SKTexture, cell: CGFloat) -> SKTexture {
        let src = tex.cgImage()
        let w = Int(cell) * prescale
        let h = Int(cell) * prescale

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

    /// 走路循环的帧序。**3 帧 ping-pong，不是 4 帧循环。**
    ///
    /// ⚠️ **这是修「走路一顿一顿」的关键。**
    ///
    /// LPC Cats and Dogs 每个方向只有 **3 帧走路**，第 4 格是**坐/趴姿**：
    /// ```
    /// cat r0c3: 252px，趴卧（无腿、身体贴地）
    /// dog r0c3: 259px，同样是趴卧
    /// cat r1c3 / r2c3: 0px，完全空白
    /// ```
    /// 按 4 帧循环播的话，左右走每周期会「抽」一下趴下，
    /// 朝前/朝后走则会闪一帧空白 —— 这就是「一顿一顿」。
    ///
    /// 正确帧序是 `0 → 1 → 2 → 1` 的往复：col1 是 passing pose（中间姿），
    /// 往复时出现两次，视觉上就是左右腿交替。素材作者在 OpenGameArt 上传的
    /// walk 预览 GIF 用的正是这个序列（逐帧解码比对确认），每帧 150ms。
    ///
    /// 该资源也被 OpenGameArt 收录进「3 Frame Walk Cycles」合集，
    /// rework 版本的说明写明「3 tiles per direction」。
    ///
    /// 不用 `0→1→2` 硬循环：那样从 col2 跳回 col0 是同侧腿突然换边，会跳。
    ///
    /// 帧序现在在 `PetSheetLayout.walkSequence` —— 走路帧数不同的素材
    /// 只要换布局，不改这里。

    static func frames(from sheet: SKTexture,
                       action: Action,
                       colorIndex: Int,
                       layout: PetSheetLayout) -> [SKTexture] {
        let row = action.row(in: layout)
        switch action {
        case .walk:
            return layout.walkSequence.map {
                texture(from: sheet, row: row, column: $0,
                        colorIndex: colorIndex, layout: layout)
            }
        case .eat:
            // 进食行整个循环都是有效的咀嚼帧
            return (0..<layout.columnsPerColor).map {
                texture(from: sheet, row: row, column: $0,
                        colorIndex: colorIndex, layout: layout)
            }
        }
    }

    /// 睡觉 sheet（自绘补的，主 sheet 里确认没有 sleep 帧）。
    ///
    /// 布局在 `PetSheetLayout.sleepColumns/Rows`：列 = 毛色，行 = 呼气/吸气。
    /// 生成脚本 tools/make_sleep.py —— 调色板从主 sheet 自动提取，
    /// 保证毛色与走路帧一致。
    static func sleepFrames(from sheet: SKTexture,
                            colorIndex: Int,
                            layout: PetSheetLayout) -> [SKTexture] {
        let sheetW = sheet.size().width
        let sheetH = sheet.size().height
        guard sheetW > 0, sheetH > 0 else { return [] }

        let cell = layout.cell
        let color = min(max(0, colorIndex), max(0, layout.sleepColumns - 1))

        return (0..<layout.sleepRows).map { row in
            let flippedRow = layout.sleepRows - row - 1   // Y 翻转
            let rect = CGRect(x: CGFloat(color) * cell / sheetW,
                              y: CGFloat(flippedRow) * cell / sheetH,
                              width: cell / sheetW,
                              height: cell / sheetH)
            let sub = SKTexture(rect: rect, in: sheet)
            sub.filteringMode = .nearest

            // ⚠️ 必须和走路帧一样做预放大。
            // 节点缩放已经按 prescale 除过（见 PetScene.currentPetScale），
            // 这里若返回原尺寸纹理，睡觉时宠物会缩到 1/prescale。
            let key = "sleep|\(sheet.description)|\(row)|\(color)|\(Int(cell))"
            if let hit = cache[key] { return hit }
            let scaled = upscaled(sub, cell: cell)
            cache[key] = scaled
            return scaled
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
