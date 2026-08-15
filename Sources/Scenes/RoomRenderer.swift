import SpriteKit

/// 房间渲染器。
///
/// **从 PetScene 抽出来的原因**：这 170 行只用 `size` / `wallBaseY` / `unit`
/// 三个输入，全部通过 `addChild` 输出，不读任何宠物状态 —— 边界天然干净。
/// 留在 PetScene 里会和行为逻辑混在一起，改房间视觉时得在状态机之间翻找。
///
/// 外部只需一句 `RoomRenderer.build(into:size:wallBaseY:unit:)`。
///
/// ⚠️ **不做数据驱动的配置表。** 这里画的是一幅固定构图的像素画，
/// 把窗/挂画/壁灯的坐标抽成 JSON 会让「月牙是亮圆叠一个天空色圆」
/// 这类绘画技巧变得不可读。可移动的家具已经由 `RoomLayout.Slot`
/// 提供数据驱动，静态装饰不需要同一套机制。
enum RoomRenderer {

    /// zPosition 分层。
    ///
    /// 原来是散在代码里的手排浮点（-3.5/-3.4/-3.35/-3.33/-3.32/-3.2/…），
    /// 插新元素要在缝里找数。集中成常量后能一眼看出层级关系。
    enum Layer {
        static let wall: CGFloat = -6
        static let wallStripe: CGFloat = -5
        static let floor: CGFloat = -6
        static let floorBand: CGFloat = -5.5
        static let floorSeam: CGFloat = -5

        /// 墙面装饰：-3.5（最里）到 -3.0（最外）
        static let decorFrame: CGFloat = -3.5
        static let decorFill: CGFloat = -3.4
        static let decorDetail: CGFloat = -3.35
        static let decorMid: CGFloat = -3.33
        static let decorFore: CGFloat = -3.3
        static let decorGlow: CGFloat = -3.25
        static let decorHighlight: CGFloat = -3.2
        static let decorShade: CGFloat = -3.19
        static let decorGrid: CGFloat = -3.1
        static let decorSill: CGFloat = -3.0

        /// 踢脚线压在家具底边之上一点，藏住接缝
        static let skirting: CGFloat = 0.5
    }

    /// 画整个房间。
    ///
    /// - Parameters:
    ///   - node: 挂载到哪（通常是 scene 本身）
    ///   - size: 场景尺寸
    ///   - wallBaseY: 墙脚线 y，也是地板最远处
    ///   - unit: 1 源像素 = 多少 pt
    static func build(into node: SKNode,
                      size: CGSize,
                      wallBaseY: CGFloat,
                      unit u: CGFloat) {
        let base = (wallBaseY / u).rounded() * u   // 墙脚线对齐像素网格
        buildWall(into: node, size: size, base: base, u: u)
        buildWallDecor(into: node, size: size, base: base, u: u)
        buildFloor(into: node, size: size, base: base, u: u)
        buildSkirting(into: node, size: size, base: base, u: u)
    }

    // MARK: - 墙

    private static func buildWall(into node: SKNode, size: CGSize,
                                  base: CGFloat, u: CGFloat) {
        let wall = SKSpriteNode(color: RoomPalette.wall.sk,
                                size: CGSize(width: size.width,
                                             height: size.height - base))
        wall.anchorPoint = CGPoint(x: 0, y: 0)
        wall.position = CGPoint(x: 0, y: base)
        wall.zPosition = Layer.wall
        node.addChild(wall)

        // 墙纸竖条纹：每 16 源像素一条宽 3px 的条，对比度拉到看得见为止
        var x: CGFloat = 0
        while x < size.width {
            let stripe = SKSpriteNode(color: RoomPalette.wallStripe.sk,
                                      size: CGSize(width: u * 3,
                                                   height: size.height - base))
            stripe.anchorPoint = CGPoint(x: 0, y: 0)
            stripe.position = CGPoint(x: x, y: base)
            stripe.zPosition = Layer.wallStripe
            node.addChild(stripe)
            x += u * 16
        }
    }

    // MARK: - 地板

    /// 地板：横向木板 + 竖向错缝。
    ///
    /// 纵深全靠这个纹理表现 —— 板宽随距离递增（远处密、近处疏），
    /// 这是真实透视里地板的样子。比画梯形轮廓自然得多：
    /// 真实房间的地板边缘不会明显收缩，收缩了就像漏斗。
    private static func buildFloor(into node: SKNode, size: CGSize,
                                   base: CGFloat, u: CGFloat) {
        let floor = SKSpriteNode(color: RoomPalette.floor.sk,
                                 size: CGSize(width: size.width, height: base))
        floor.anchorPoint = CGPoint(x: 0, y: 0)
        floor.position = .zero
        floor.zPosition = Layer.floor
        node.addChild(floor)

        var y: CGFloat = base
        var plankH: CGFloat = u * 5          // 最远处的板最窄
        var rowIndex = 0

        while y > 0 {
            let h = min(plankH, y)
            let rowY = y - h

            // 隔行换深浅，木板质感
            if rowIndex % 2 == 1 {
                let band = SKSpriteNode(color: RoomPalette.floorAlt.sk,
                                        size: CGSize(width: size.width, height: h))
                band.anchorPoint = CGPoint(x: 0, y: 0)
                band.position = CGPoint(x: 0, y: rowY)
                band.zPosition = Layer.floorBand
                node.addChild(band)
            }

            // 板缝
            let seam = SKSpriteNode(color: RoomPalette.floorSeam.sk,
                                    size: CGSize(width: size.width, height: u))
            seam.anchorPoint = CGPoint(x: 0, y: 0)
            seam.position = CGPoint(x: 0, y: rowY)
            seam.zPosition = Layer.floorSeam
            node.addChild(seam)

            // 竖向错缝：每行的短竖线错开半格，避免看起来像跑道
            let seg = u * 48
            var vx = (CGFloat(rowIndex % 2) * seg / 2)
            while vx < size.width {
                let v = SKSpriteNode(color: RoomPalette.floorSeam.sk,
                                     size: CGSize(width: u, height: h))
                v.anchorPoint = CGPoint(x: 0, y: 0)
                v.position = CGPoint(x: (vx / u).rounded() * u, y: rowY)
                v.zPosition = Layer.floorSeam
                node.addChild(v)
                vx += seg
            }

            y = rowY
            plankH += u * 2.2                // 越靠近镜头板越宽
            rowIndex += 1
        }
    }

    /// 踢脚线：坐在墙脚线上，两像素高，亮暗两色做立体感
    private static func buildSkirting(into node: SKNode, size: CGSize,
                                      base: CGFloat, u: CGFloat) {
        for (offset, color) in [(CGFloat(0), RoomPalette.skirtingDark),
                                (u, RoomPalette.skirtingLite)] {
            let n = SKSpriteNode(color: color.sk,
                                 size: CGSize(width: size.width, height: u))
            n.anchorPoint = CGPoint(x: 0, y: 0)
            n.position = CGPoint(x: 0, y: base + offset)
            n.zPosition = Layer.skirting
            node.addChild(n)
        }
    }

    // MARK: - 墙面装饰

    /// 窗、挂画、壁灯。
    ///
    /// 全部手绘像素块，尺寸严格取 u 的整数倍。**都是侧视/正视**，
    /// 和宠物的视角一致 —— 这是不用现成家具包的原因。
    ///
    /// 坐标规律：x 用屏宽比例，y 用 `base + u*n`，尺寸用 `u*n`。
    private static func buildWallDecor(into node: SKNode, size: CGSize,
                                       base: CGFloat, u: CGFloat) {
        func block(_ bx: CGFloat, _ by: CGFloat, _ bw: CGFloat, _ bh: CGFloat,
                   _ color: SKColor, _ z: CGFloat) {
            let n = SKSpriteNode(color: color, size: CGSize(width: bw, height: bh))
            n.anchorPoint = CGPoint(x: 0, y: 0)
            n.position = CGPoint(x: (bx / u).rounded() * u,
                                 y: (by / u).rounded() * u)
            n.zPosition = z
            node.addChild(n)
        }

        // ── 窗（正视，居中偏右）──
        let w = u * 38, h = u * 28
        let x = size.width * 0.60 - w / 2
        let y = base + u * 20

        block(x - u * 2, y - u * 2, w + u * 4, h + u * 4,
              RoomPalette.frameDark.sk, Layer.decorFrame)
        block(x, y, w, h, RoomPalette.sky.sk, Layer.decorFill)
        for (sx, sy) in [(5, 23), (13, 18), (28, 24), (33, 15), (20, 25), (9, 12)] {
            block(x + u * CGFloat(sx), y + u * CGFloat(sy), u, u,
                  RoomPalette.moon.sk, Layer.decorDetail)
        }
        block(x, y, w, u * 8, RoomPalette.hillFar.sk, Layer.decorMid)
        block(x, y, u * 20, u * 5, RoomPalette.hill.sk, Layer.decorMid)
        // 月牙：亮圆 + 偏移的天空色圆盖住一部分
        block(x + u * 25, y + u * 19, u * 5, u * 5,
              RoomPalette.moon.sk, Layer.decorHighlight)
        block(x + u * 27, y + u * 21, u * 4, u * 4,
              RoomPalette.sky.sk, Layer.decorShade)
        // 窗棂
        block(x + w / 2 - u / 2, y, u, h,
              RoomPalette.frameDark.sk, Layer.decorGrid)
        block(x, y + h / 2 - u / 2, w, u,
              RoomPalette.frameDark.sk, Layer.decorGrid)
        // 窗台
        block(x - u * 3, y - u * 3, w + u * 6, u * 2,
              RoomPalette.sill.sk, Layer.decorSill)

        // ── 挂画（正视，偏左）──
        let pw = u * 14, ph = u * 11
        let px2 = size.width * 0.18 - pw / 2
        let py2 = base + u * 28
        block(px2 - u, py2 - u, pw + u * 2, ph + u * 2,
              RoomPalette.frameDark.sk, Layer.decorFrame)
        block(px2, py2, pw, ph, RoomPalette.artBg.sk, Layer.decorFill)
        block(px2, py2, pw, u * 4, RoomPalette.artHill.sk, Layer.decorFore)
        block(px2 + u * 9, py2 + u * 7, u * 3, u * 3,
              RoomPalette.artSun.sk, Layer.decorFore)

        // ── 壁灯（侧视，画的右侧）──
        let lx = size.width * 0.32
        let ly = base + u * 34
        block(lx, ly, u * 2, u * 5,
              RoomPalette.frameDark.sk, Layer.decorFill)      // 支架
        block(lx - u * 2, ly + u * 5, u * 6, u * 3,
              RoomPalette.lampShade.sk, Layer.decorFore)
        // 灯光：一片半透明暖色向下扩散
        for i in 0..<3 {
            let gw = u * CGFloat(6 + i * 4)
            block(lx + u - gw / 2, ly - u * CGFloat(i * 3), gw, u * 3,
                  RoomPalette.lampGlow.sk.withAlphaComponent(0.10 - CGFloat(i) * 0.03),
                  Layer.decorGlow)
        }
    }
}
