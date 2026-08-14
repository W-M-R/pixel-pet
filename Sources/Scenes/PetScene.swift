import SpriteKit
import CoreMotion

/// 宠物主场景。
///
/// 差异化在这里：宠物会被戳到、会追手指、会响应摇晃。
/// 挂件类竞品（Pixel Pals 那种走 WidgetKit 时间线的）做不到真实互动，
/// 这是 SpriteKit 全屏场景的天然优势。
final class PetScene: SKScene {

    // MARK: - 配置

    /// 整数倍缩放，保证像素边界对齐。
    ///
    /// 用 4 而不是 5：家具的真实尺寸比宠物大得多（床 60×64 vs 猫 24×19，
    /// 也就是 2.5 倍宽 3.4 倍高），这个比例本身是对的，但 ×5 之后一张床
    /// 就占掉大半屏，房间塞不下几件家具。缩到 ×4 让构图有呼吸空间。
    private let pixelScale: CGFloat = 4
    private let walkSpeed: CGFloat = 34      // pt/秒
    private let followSpeed: CGFloat = 82    // 追手指时快一些

    // MARK: - 状态

    private var sheet: SKTexture?
    private var sleepSheet: SKTexture?
    private var roomSheet: SKTexture?
    private var emoteSheet: SKTexture?
    private var pet: SKSpriteNode!
    private var shadow: SKShapeNode!
    private var bubble: SKNode?
    private var foodNode: SKNode?

    private var colorIndex: Int = 0
    private var species: PetSpecies = .cat

    /// 宠物当前行为。和 PetState 的「需求」分开——需求是数据，行为是表现。
    private enum Behavior {
        case idle
        case wandering(target: CGPoint)
        case following
        case eating
        case startled
        case sleeping
    }
    private var behavior: Behavior = .idle
    private var facing: PetSpriteSheet.Facing = .right
    private var nextDecisionAt: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0

    private var touchPoint: CGPoint?
    private let motion = CMMotionManager()

    // MARK: - 家具

    private var furnitureNodes: [SKSpriteNode] = []
    var layout: RoomLayout = .default

    /// 正在拖动的家具。长按 0.35s 才进入拖动，避免和「点空地让宠物走过去」冲突。
    private var draggingNode: SKSpriteNode?
    private var pendingDragNode: SKSpriteNode?
    private var dragArmTimer: Timer?

    /// 家具被移动后回调，交给 RoomStore 持久化
    var onFurnitureMoved: ((String, Double) -> Void)?

    // MARK: - 房间几何
    //
    // 三条水平基准线，从上到下：
    //
    //   ┌──────────────────┐
    //   │      墙           │
    //   │  ┌──┐ ┌┐ ┌──┐    │  家具靠墙，底边坐在 wallBaseY
    //   ├──┴──┴─┴┴─┴──┴────┤  wallBaseY（墙脚线）
    //   │                   │  地面通道 —— 宠物独占
    //   │      🐈          │  groundY（宠物脚底）
    //   └──────────────────┘
    //
    // 分层的意义：家具和宠物在垂直方向上不重叠，所以永远不会互相遮挡。
    // 之前家具和宠物都堆在 groundY 附近，宠物一走过去就被压住。

    /// 墙脚线。墙与地面的分界，家具坐在这条线上。
    ///
    /// 0.34 是按最高家具反推的：书架/床 64 源像素 × pixelScale 4 = 256pt，
    /// 顶边落在 0.34H + 256 ≈ 0.61H，正好在状态栏（约 0.80H 以上）之下，
    /// 留出明显间隙。再高就会显得顶到 UI。
    private var wallBaseY: CGFloat { size.height * 0.30 }

    /// 宠物脚底线。墙脚线下方留一条通道，
    /// 高度约宠物身高的 1.5 倍，够走动又不空旷。
    private var groundY: CGFloat { size.height * 0.155 }

    var onPetTouched: (() -> Void)?

    // MARK: - 生命周期

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
        buildScene()
        startMotion()
    }

    override func willMove(from view: SKView) {
        motion.stopAccelerometerUpdates()
    }

    /// 布局变了以后重建房间（改布局/重置时调用）。
    /// 只重建家具，不动宠物，免得打断它当前的行为。
    func rebuildRoom() {
        for node in furnitureNodes { node.removeFromParent() }
        furnitureNodes.removeAll()
        guard let roomSheet, size.width > 1 else { return }
        let scale = pixelScale
        for slot in layout.slots {
            addFurniture(slot, sheet: roomSheet, scale: scale)
        }
    }

    func configure(species: PetSpecies, colorIndex: Int) {
        guard species != self.species || colorIndex != self.colorIndex || pet == nil else { return }
        self.species = species
        self.colorIndex = colorIndex
        sheet = PetSpriteSheet.loadSheet(named: species.sheetName)
        sleepSheet = PetSpriteSheet.loadSheet(named: "\(species.sheetName)_sleep")
        if pet != nil { applyWalkAnimation() }
    }

    private func buildScene() {
        removeAllChildren()
        guard size.width > 1 else { return }

        sheet = PetSpriteSheet.loadSheet(named: species.sheetName)
        sleepSheet = PetSpriteSheet.loadSheet(named: "\(species.sheetName)_sleep")
        roomSheet = RoomSpriteSheet.loadSheet(named: "house_objects")
        emoteSheet = RoomSpriteSheet.loadSheet(named: "emotes")

        buildRoom()

        // 影子：一个扁椭圆，给宠物一点重量感
        shadow = SKShapeNode(ellipseOf: CGSize(width: 44, height: 12))
        shadow.fillColor = SKColor(white: 0, alpha: 0.18)
        shadow.strokeColor = .clear
        shadow.zPosition = 9
        addChild(shadow)

        let firstFrame = sheet.map {
            PetSpriteSheet.texture(from: $0, row: 0, column: 0, colorIndex: colorIndex)
        }
        pet = SKSpriteNode(texture: firstFrame)
        pet.texture?.filteringMode = .nearest
        pet.setScale(pixelScale)
        pet.position = CGPoint(x: size.width / 2, y: groundY)
        pet.zPosition = 10
        addChild(pet)

        applyWalkAnimation()
        syncShadow()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 1 else { return }
        // 尺寸变了要重排家具，不然会错位
        buildScene()
    }

    // MARK: - 房间

    /// 家具摆放。位置来自 RoomStore（屏宽比例），支持长按拖动。
    private func buildRoom() {
        buildFloor()
        guard let roomSheet else { return }
        furnitureNodes.removeAll()
        // 家具与宠物同一像素密度。之前乘 0.8 会让家具的像素格
        // 比宠物小，两种密度混在一起看着很脏。
        let scale = pixelScale

        for slot in layout.slots {
            addFurniture(slot, sheet: roomSheet, scale: scale)
        }
    }

    /// 家具锚点设在**底部中心**，这样 yOffset 直接就是「底边离墙脚线多高」，
    /// 不用为每件家具单独算高度的一半。
    private func addFurniture(_ slot: RoomLayout.Slot,
                              sheet: SKTexture,
                              scale: CGFloat) {
        guard let item = RoomSpriteSheet.Furniture(rawValue: slot.id) else { return }
        let node = SKSpriteNode(texture: RoomSpriteSheet.furnitureTexture(from: sheet, item))
        node.texture?.filteringMode = .nearest
        // 地毯平铺在地上，用中心锚点；其余家具立着，用底部锚点，
        // 这样 yOffset 的语义就是「底边离墙脚线多高」。
        node.anchorPoint = item == .rug ? CGPoint(x: 0.5, y: 0.5)
                                        : CGPoint(x: 0.5, y: 0)
        node.setScale(scale * slot.scaleMul)
        node.position = CGPoint(x: size.width * slot.xRatio,
                                y: wallBaseY + slot.yOffset)
        node.zPosition = slot.z
        node.name = slot.id
        addChild(node)
        furnitureNodes.append(node)
    }

    /// 墙 + 地板。
    ///
    /// Home Objects 包里没有墙纸/地板 tile，所以这些是用像素块画的。
    /// 关键是**所有尺寸取 pixelScale 的整数倍**，让手绘部分和 32×32
    /// 素材保持同一像素密度 —— 否则会出现「细线条 + 粗像素」混在一起
    /// 的廉价感。
    private func buildFloor() {
        let u = pixelScale                    // 1 源像素 = pixelScale pt
        let base = (wallBaseY / u).rounded() * u   // 墙脚线对齐像素网格

        // ── 墙 ──
        let wall = SKSpriteNode(color: Palette.wall,
                                size: CGSize(width: size.width, height: size.height - base))
        wall.anchorPoint = CGPoint(x: 0, y: 0)
        wall.position = CGPoint(x: 0, y: base)
        wall.zPosition = -6
        addChild(wall)

        // 墙纸竖条纹：每 8 源像素一条宽 2px 的条，对比度拉到看得见为止
        var x: CGFloat = 0
        while x < size.width {
            let stripe = SKSpriteNode(color: Palette.wallStripe,
                                      size: CGSize(width: u * 3, height: size.height - base))
            stripe.anchorPoint = CGPoint(x: 0, y: 0)
            stripe.position = CGPoint(x: x, y: base)
            stripe.zPosition = -5
            addChild(stripe)
            x += u * 16
        }

        buildWallDecor(base: base, u: u)

        // ── 地板 ──
        let floor = SKSpriteNode(color: Palette.floor,
                                 size: CGSize(width: size.width, height: base))
        floor.anchorPoint = CGPoint(x: 0, y: 0)
        floor.position = .zero
        floor.zPosition = -6
        addChild(floor)

        // 地板条：横向木纹，间距随纵向递增，制造一点透视纵深
        var y: CGFloat = base - u * 3
        var gap: CGFloat = u * 3
        while y > 0 {
            let plank = SKSpriteNode(color: Palette.floorSeam,
                                     size: CGSize(width: size.width, height: u))
            plank.anchorPoint = CGPoint(x: 0, y: 0)
            plank.position = CGPoint(x: 0, y: y)
            plank.zPosition = -5
            addChild(plank)
            y -= gap
            gap += u * 0.5                  // 越靠下间距越大 = 越近
        }

        // ── 踢脚线：坐在墙脚线上，两像素高，亮暗两色做立体感 ──
        let skirtDark = SKSpriteNode(color: Palette.skirtingDark,
                                     size: CGSize(width: size.width, height: u))
        skirtDark.anchorPoint = CGPoint(x: 0, y: 0)
        skirtDark.position = CGPoint(x: 0, y: base)
        skirtDark.zPosition = 0.5           // 压在家具底边之上一点，藏住接缝
        addChild(skirtDark)

        let skirtLite = SKSpriteNode(color: Palette.skirtingLite,
                                     size: CGSize(width: size.width, height: u))
        skirtLite.anchorPoint = CGPoint(x: 0, y: 0)
        skirtLite.position = CGPoint(x: 0, y: base + u)
        skirtLite.zPosition = 0.5
        addChild(skirtLite)
    }

    /// 墙上的装饰：窗、挂画、壁灯。
    ///
    /// 全部手绘像素块，尺寸严格取 u 的整数倍。**都是侧视/正视**，
    /// 和宠物的视角一致 —— 这是不用现成家具包的原因。
    private func buildWallDecor(base: CGFloat, u: CGFloat) {
        func block(_ bx: CGFloat, _ by: CGFloat, _ bw: CGFloat, _ bh: CGFloat,
                   _ color: SKColor, _ z: CGFloat) {
            let n = SKSpriteNode(color: color, size: CGSize(width: bw, height: bh))
            n.anchorPoint = CGPoint(x: 0, y: 0)
            n.position = CGPoint(x: (bx / u).rounded() * u,
                                 y: (by / u).rounded() * u)
            n.zPosition = z
            addChild(n)
        }

        // ── 窗（正视，居中偏右）──
        let w = u * 38, h = u * 28
        let x = size.width * 0.60 - w / 2
        let y = base + u * 20

        block(x - u * 2, y - u * 2, w + u * 4, h + u * 4, Palette.frameDark, -3.5)
        block(x, y, w, h, Palette.sky, -3.4)
        for (sx, sy) in [(5, 23), (13, 18), (28, 24), (33, 15), (20, 25), (9, 12)] {
            block(x + u * CGFloat(sx), y + u * CGFloat(sy), u, u, Palette.moon, -3.35)
        }
        block(x, y, w, u * 8, Palette.hillFar, -3.33)
        block(x, y, u * 20, u * 5, Palette.hill, -3.32)
        // 月牙：亮圆 + 偏移的天空色圆盖住一部分
        block(x + u * 25, y + u * 19, u * 5, u * 5, Palette.moon, -3.2)
        block(x + u * 27, y + u * 21, u * 4, u * 4, Palette.sky, -3.19)
        // 窗棂
        block(x + w / 2 - u / 2, y, u, h, Palette.frameDark, -3.1)
        block(x, y + h / 2 - u / 2, w, u, Palette.frameDark, -3.1)
        // 窗台
        block(x - u * 3, y - u * 3, w + u * 6, u * 2, Palette.sill, -3.0)

        // ── 挂画（正视，偏左）──
        let pw = u * 14, ph = u * 11
        let px2 = size.width * 0.18 - pw / 2
        let py2 = base + u * 28
        block(px2 - u, py2 - u, pw + u * 2, ph + u * 2, Palette.frameDark, -3.5)
        block(px2, py2, pw, ph, Palette.artBg, -3.4)
        block(px2, py2, pw, u * 4, Palette.artHill, -3.3)
        block(px2 + u * 9, py2 + u * 7, u * 3, u * 3, Palette.artSun, -3.3)

        // ── 壁灯（侧视，画的右侧）──
        let lx = size.width * 0.32
        let ly = base + u * 34
        block(lx, ly, u * 2, u * 5, Palette.frameDark, -3.4)      // 支架
        block(lx - u * 2, ly + u * 5, u * 6, u * 3, Palette.lampShade, -3.3)
        // 灯光：一片半透明暖色向下扩散
        for i in 0..<3 {
            let gw = u * CGFloat(6 + i * 4)
            block(lx + u - gw / 2, ly - u * CGFloat(i * 3), gw, u * 3,
                  Palette.lampGlow.withAlphaComponent(0.10 - CGFloat(i) * 0.03), -3.25)
        }
    }

    /// 房间配色。集中放一处，方便整体调色而不用满场景找魔数。
    private enum Palette {
        // 墙：暖调米色，比原来的冷紫更像家里
        static let wall         = SKColor(red: 0.85, green: 0.78, blue: 0.68, alpha: 1)
        static let wallStripe   = SKColor(red: 0.82, green: 0.755, blue: 0.655, alpha: 1)
        // 地板：木色，和墙有明确冷暖/明度区分
        static let floor        = SKColor(red: 0.62, green: 0.44, blue: 0.31, alpha: 1)
        static let floorSeam    = SKColor(red: 0.52, green: 0.35, blue: 0.24, alpha: 1)
        static let skirtingDark = SKColor(red: 0.38, green: 0.26, blue: 0.19, alpha: 1)
        static let skirtingLite = SKColor(red: 0.72, green: 0.56, blue: 0.42, alpha: 1)
        // 窗外夜景
        static let sky          = SKColor(red: 0.14, green: 0.19, blue: 0.36, alpha: 1)
        static let hill         = SKColor(red: 0.17, green: 0.27, blue: 0.31, alpha: 1)
        static let hillFar      = SKColor(red: 0.20, green: 0.24, blue: 0.36, alpha: 1)
        static let moon         = SKColor(red: 0.98, green: 0.96, blue: 0.86, alpha: 1)
        static let frameDark    = SKColor(red: 0.35, green: 0.24, blue: 0.18, alpha: 1)
        static let sill         = SKColor(red: 0.72, green: 0.56, blue: 0.42, alpha: 1)
        // 挂画
        static let artBg        = SKColor(red: 0.56, green: 0.72, blue: 0.78, alpha: 1)
        static let artHill      = SKColor(red: 0.42, green: 0.60, blue: 0.42, alpha: 1)
        static let artSun       = SKColor(red: 0.96, green: 0.80, blue: 0.42, alpha: 1)
        // 壁灯
        static let lampShade    = SKColor(red: 0.90, green: 0.74, blue: 0.44, alpha: 1)
        static let lampGlow     = SKColor(red: 1.00, green: 0.92, blue: 0.70, alpha: 1)
    }

    // MARK: - 动画

    private func applyWalkAnimation() {
        guard let sheet, let pet else { return }
        let frames = PetSpriteSheet.frames(from: sheet,
                                           action: .walk(facing),
                                           colorIndex: colorIndex)
        guard !frames.isEmpty else { return }
        pet.removeAction(forKey: "anim")
        let anim = SKAction.animate(with: frames,
                                    timePerFrame: PetSpriteSheet.Action.walk(facing).timePerFrame,
                                    resize: false,
                                    restore: false)
        pet.run(.repeatForever(anim), withKey: "anim")
    }

    private func applyEatAnimation(then completion: @escaping () -> Void) {
        guard let sheet, let pet else { return }
        let frames = PetSpriteSheet.frames(from: sheet, action: .eat, colorIndex: colorIndex)
        guard !frames.isEmpty else { completion(); return }
        pet.removeAction(forKey: "anim")
        let chew = SKAction.animate(with: frames,
                                    timePerFrame: PetSpriteSheet.Action.eat.timePerFrame,
                                    resize: false,
                                    restore: false)
        pet.run(.sequence([.repeat(chew, count: 4), .run(completion)]), withKey: "anim")
    }

    /// 睡觉姿态。主 sheet 里确认没有 sleep 帧（r4 是咀嚼），
    /// 所以用自绘的趴卧 sheet（tools/make_sleep.py 生成，调色板取自主 sheet）。
    /// 若自绘 sheet 缺失则回退到「侧视帧压扁 + 呼吸缩放」。
    private func applySleepPose() {
        guard let pet else { return }
        pet.removeAction(forKey: "anim")
        pet.setScale(pixelScale)

        let frames = sleepSheet.map {
            PetSpriteSheet.sleepFrames(from: $0, colorIndex: colorIndex)
        } ?? []

        if frames.count >= 2 {
            pet.texture = frames[0]
            pet.texture?.filteringMode = .nearest
            // 呼吸节奏放慢，2.2s 一次起伏
            let breathe = SKAction.animate(with: frames,
                                           timePerFrame: 1.1,
                                           resize: false,
                                           restore: false)
            pet.run(.repeatForever(breathe), withKey: "anim")
        } else if let sheet {
            // 回退方案
            pet.texture = PetSpriteSheet.texture(from: sheet,
                                                 row: PetSpriteSheet.Facing.right.row,
                                                 column: 0,
                                                 colorIndex: colorIndex)
            pet.texture?.filteringMode = .nearest
            pet.yScale = pixelScale * 0.82
            pet.xScale = pixelScale * 1.04
            let breathe = SKAction.sequence([
                .scaleY(to: pixelScale * 0.86, duration: 1.4),
                .scaleY(to: pixelScale * 0.82, duration: 1.4)
            ])
            breathe.timingMode = .easeInEaseOut
            pet.run(.repeatForever(breathe), withKey: "anim")
        }
    }

    /// 站住时把动画停在第一帧。sheet 里没有独立的 idle 动作，
    /// 所以「静止」就是走路动画的第 0 帧。
    private func applyIdlePose() {
        guard let sheet, let pet else { return }
        pet.removeAction(forKey: "anim")
        pet.texture = PetSpriteSheet.texture(from: sheet,
                                             row: facing.row,
                                             column: 0,
                                             colorIndex: colorIndex)
        pet.texture?.filteringMode = .nearest
        // 从睡姿回来要复位缩放
        pet.setScale(pixelScale)
    }

    // MARK: - 行为驱动

    override func update(_ currentTime: TimeInterval) {
        guard pet != nil else { return }
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime

        if let touchPoint, !isSleeping {
            behavior = .following
            moveToward(touchPoint, speed: followSpeed, dt: dt)
        } else {
            switch behavior {
            case .following:
                behavior = .idle
                nextDecisionAt = currentTime + 0.4
            case .idle:
                if currentTime > nextDecisionAt { decideNextMove(at: currentTime) }
            case .wandering(let target):
                if moveToward(target, speed: walkSpeed, dt: dt) {
                    behavior = .idle
                    applyIdlePose()
                    nextDecisionAt = currentTime + .random(in: 1.2...3.5)
                }
            case .eating, .startled, .sleeping:
                break
            }
        }
        syncShadow()
    }

    /// 由 UI 层按 PetState.energy 驱动。困了就趴下，休息够了自己起来。
    func setSleeping(_ sleeping: Bool) {
        if sleeping {
            guard !isSleeping else { return }
            behavior = .sleeping
            touchPoint = nil
            applySleepPose()
            showEmote(.sleep)
        } else {
            guard isSleeping else { return }
            behavior = .idle
            nextDecisionAt = 0
            applyIdlePose()
        }
    }

    private var isSleeping: Bool {
        if case .sleeping = behavior { return true }
        return false
    }

    private func decideNextMove(at time: TimeInterval) {
        // 70% 概率走一段，30% 继续待着
        guard Double.random(in: 0...1) < 0.7 else {
            nextDecisionAt = time + .random(in: 1...2.5)
            return
        }
        let margin: CGFloat = 60
        let target = CGPoint(x: .random(in: margin...(size.width - margin)), y: groundY)
        behavior = .wandering(target: target)
        updateFacing(towardX: target.x)
        applyWalkAnimation()
    }

    /// 返回 true 表示已到达
    @discardableResult
    private func moveToward(_ target: CGPoint, speed: CGFloat, dt: TimeInterval) -> Bool {
        let dx = target.x - pet.position.x
        if abs(dx) < 4 { return true }
        let step = speed * CGFloat(dt)
        pet.position.x += dx > 0 ? min(step, dx) : max(-step, dx)
        updateFacing(towardX: target.x)
        return false
    }

    private func updateFacing(towardX x: CGFloat) {
        let newFacing: PetSpriteSheet.Facing = x > pet.position.x ? .right : .left
        guard newFacing != facing else { return }
        facing = newFacing
        applyWalkAnimation()
    }

    private func syncShadow() {
        guard let pet, let shadow else { return }
        // 影子贴在脚底，略微下沉 1 源像素，看起来像压在地上
        shadow.position = CGPoint(x: pet.position.x, y: petFeetY - pixelScale)
    }

    // MARK: - 外部触发

    func triggerEat() {
        guard pet != nil else { return }
        behavior = .eating
        touchPoint = nil
        // 睡姿改过 yScale，先复位再放盆，否则 petFeetY 算出来是压扁后的位置
        pet.removeAction(forKey: "anim")
        pet.setScale(pixelScale)
        dropFoodBowl()
        showEmojiBubble("🍖")
        applyEatAnimation { [weak self] in
            guard let self else { return }
            self.foodNode?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            self.foodNode = nil
            self.behavior = .idle
            self.nextDecisionAt = 0
            self.applyIdlePose()
        }
    }

    /// 宠物脚底的 y 坐标。
    ///
    /// 不能直接用 `pet.position.y` —— 那是节点中心。也不能硬编码偏移，
    /// 因为偏移量随 pixelScale 变（曾经写死 -24，pixelScale 从 5 改到 4
    /// 之后食盆就跑到宠物头上去了）。
    ///
    /// 帧是 32×32，而猫的内容底边在第 26 行，即底部有 5 行空白。
    /// 所以脚底 = 中心 - (16 - 5) × pixelScale。
    private var petFeetY: CGFloat {
        let frameH = PetSpriteSheet.frameSize.height        // 32
        let bottomPadding: CGFloat = 5                      // 实测内容底边 y=26
        return pet.position.y - (frameH / 2 - bottomPadding) * pixelScale
    }

    /// 喂食时在宠物脚边放一个食盆。
    /// 素材包里没有食盆（而且那套是俯视的），所以手绘一个侧视的，
    /// 尺寸取 pixelScale 整数倍，与宠物同像素密度。
    private func dropFoodBowl() {
        foodNode?.removeFromParent()

        let u = pixelScale             // 1 源像素 = pixelScale pt
        let container = SKNode()

        /// 以「盆底左边缘」为原点画，方便对齐地面
        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: SKColor) {
            let n = SKSpriteNode(color: color, size: CGSize(width: w * u, height: h * u))
            n.anchorPoint = CGPoint(x: 0, y: 0)
            n.position = CGPoint(x: x * u, y: y * u)
            container.addChild(n)
        }

        let bowlDark = SKColor(red: 0.42, green: 0.26, blue: 0.20, alpha: 1)
        let bowlLite = SKColor(red: 0.58, green: 0.38, blue: 0.28, alpha: 1)
        let kibble   = SKColor(red: 0.80, green: 0.58, blue: 0.30, alpha: 1)

        // 盆身（宽 12 源像素，居中在原点两侧）
        block(-6, 0, 12, 2, bowlDark)
        block(-7, 2, 14, 1, bowlLite)
        // 食物堆
        block(-4, 3, 3, 2, kibble)
        block(0, 3, 4, 2, kibble)
        block(-2, 5, 3, 1, kibble)

        // 放在宠物**面朝的那一侧**，脚底同一水平线上。
        // 距离 = 宠物身体半宽(12源像素) + 盆半宽(7) + 一点间隙 ≈ 20 源像素
        let side: CGFloat = (facing == .right ? 1 : -1) * u * 20
        container.position = CGPoint(x: pet.position.x + side, y: petFeetY)
        container.zPosition = 11
        container.alpha = 0
        addChild(container)
        container.run(.fadeIn(withDuration: 0.15))
        foodNode = container
    }

    func triggerPlay() {
        guard let pet else { return }
        // 玩耍会叫醒宠物
        if isSleeping {
            behavior = .idle
            nextDecisionAt = 0
            applyIdlePose()
        }
        showEmote(.music)

        // 蹦两下。用 moveTo 回到基准 y 而不是 moveBy 抵消位移 ——
        // moveBy 一旦被打断（中途切睡觉/换宠物），宠物会永久停在半空。
        let baseY = groundY
        let hop = SKAction.sequence([
            {
                let a = SKAction.moveTo(y: baseY + pixelScale * 7, duration: 0.16)
                a.timingMode = .easeOut
                return a
            }(),
            {
                let a = SKAction.moveTo(y: baseY, duration: 0.16)
                a.timingMode = .easeIn
                return a
            }()
        ])
        pet.removeAction(forKey: "hop")
        pet.run(.repeat(hop, count: 2), withKey: "hop")
    }

    func triggerClean() {
        guard let pet else { return }
        showEmote(.droplet)
        // 结尾显式设回 alpha=1，防止动画被打断后宠物半透明卡住
        let fade = SKAction.sequence([
            .fadeAlpha(to: 0.55, duration: 0.18),
            .fadeAlpha(to: 1, duration: 0.18),
            .fadeAlpha(to: 0.55, duration: 0.18),
            .fadeAlpha(to: 1, duration: 0.18)
        ])
        pet.removeAction(forKey: "clean")
        pet.run(fade, withKey: "clean")
    }

    func showNeedBubble(_ need: PetNeed) {
        guard need != .content else { return }
        if let emote = need.emote {
            showEmote(emote)
        } else {
            // 这套 emotes 里没有食物图标，饿的时候只能用 emoji
            showEmojiBubble(need.emoji)
        }
    }

    /// 优先用像素 emote；切图失败就回退到 emoji。
    /// 回退是必要的 —— emotes.png 的网格是反推出来的，
    /// 万一某个格子坐标不对，不能让气泡直接消失。
    private func showEmote(_ emote: RoomSpriteSheet.Emote) {
        guard let emoteSheet,
              let tex = RoomSpriteSheet.emoteTexture(from: emoteSheet, emote) else {
            showEmojiBubble(fallbackEmoji(for: emote))
            return
        }
        let sprite = SKSpriteNode(texture: tex)
        sprite.texture?.filteringMode = .nearest
        sprite.setScale(pixelScale * 0.9)
        present(bubbleNode: sprite)
    }

    private func showEmojiBubble(_ text: String) {
        let label = SKLabelNode(text: text)
        label.fontSize = 26
        label.verticalAlignmentMode = .center
        present(bubbleNode: label)
    }

    private func present(bubbleNode node: SKNode) {
        guard let pet else { return }
        bubble?.removeFromParent()

        // 气泡浮在头顶上方。头顶 = 脚底 + 内容高度(19 源像素)，再留 4 像素间隙
        node.position = CGPoint(x: pet.position.x, y: petFeetY + pixelScale * 23)
        node.zPosition = 20
        node.alpha = 0
        addChild(node)
        bubble = node

        node.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .moveBy(x: 0, y: 14, duration: 0.15)]),
            .wait(forDuration: 1.1),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 10, duration: 0.3)]),
            .removeFromParent()
        ]))
    }

    private func fallbackEmoji(for emote: RoomSpriteSheet.Emote) -> String {
        switch emote {
        case .heart:      return "💗"
        case .heartbreak: return "💔"
        case .sleep:      return "💤"
        case .music:      return "🎵"
        case .droplet:    return "💧"
        case .alert:      return "❗"
        case .question:   return "❓"
        case .ellipsis:   return "💭"
        case .sweat:      return "💦"
        }
    }

    // MARK: - 触摸

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self), pet != nil else { return }

        // 先看是不是按在家具上 —— 长按才拖，短按当作点地面
        if let node = furnitureHit(at: location) {
            pendingDragNode = node
            dragArmTimer?.invalidate()
            dragArmTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                guard let self, let n = self.pendingDragNode else { return }
                self.beginDrag(n)
            }
        }

        if pet.frame.insetBy(dx: -14, dy: -14).contains(location) {
            strokePet()
        } else if !isSleeping {
            touchPoint = CGPoint(x: location.x, y: groundY)
            applyWalkAnimation()
        }
    }

    /// 戳到宠物：抚摸反馈。
    ///
    /// 睡着时戳会把它叫醒 —— 必须先退出 .sleeping，
    /// 否则挤压动画的 `scale(to: pixelScale)` 会覆盖睡姿的压扁状态，
    /// 造成「状态是睡着、外观是站着」的不一致。
    private func strokePet() {
        guard let pet else { return }

        if isSleeping {
            behavior = .idle
            nextDecisionAt = 0
            applyIdlePose()
            showEmote(.question)      // 被叫醒，一脸问号
        } else {
            showEmote(.heart)
        }
        onPetTouched?()

        pet.removeAction(forKey: "squash")
        let squash = SKAction.sequence([
            .scaleX(to: pixelScale * 1.12, y: pixelScale * 0.88, duration: 0.08),
            .scale(to: pixelScale, duration: 0.14)
        ])
        pet.run(squash, withKey: "squash")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self) else { return }

        if let dragging = draggingNode {
            dragging.position.x = min(size.width * 0.94,
                                      max(size.width * 0.06, location.x))
            return
        }
        // 手指移开了原位置就取消待拖动，避免误触发
        if let pending = pendingDragNode,
           !pending.frame.insetBy(dx: -20, dy: -20).contains(location) {
            cancelPendingDrag()
        }
        touchPoint = CGPoint(x: location.x, y: groundY)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
        touchPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
        touchPoint = nil
    }

    // MARK: - 家具拖动

    /// 命中检测按 z 从高到低，这样叠在上面的家具优先被抓到。
    /// 地毯(z=0)故意排除 —— 它铺在地上，拖它体验很怪。
    private func furnitureHit(at point: CGPoint) -> SKSpriteNode? {
        furnitureNodes
            .filter { $0.name != RoomSpriteSheet.Furniture.rug.rawValue }
            .sorted { $0.zPosition > $1.zPosition }
            .first { $0.frame.contains(point) }
    }

    private func beginDrag(_ node: SKSpriteNode) {
        draggingNode = node
        pendingDragNode = nil
        touchPoint = nil          // 拖家具时宠物不要跟着走
        node.removeAction(forKey: "lift")
        node.run(.group([
            .scale(to: node.xScale * 1.08, duration: 0.12),
            .fadeAlpha(to: 0.85, duration: 0.12)
        ]), withKey: "lift")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func endDrag() {
        dragArmTimer?.invalidate()
        dragArmTimer = nil
        pendingDragNode = nil

        guard let node = draggingNode else { return }
        draggingNode = nil
        node.removeAction(forKey: "lift")
        node.run(.group([
            .scale(to: node.xScale / 1.08, duration: 0.12),
            .fadeAlpha(to: 1, duration: 0.12)
        ]))
        if let id = node.name, size.width > 0 {
            onFurnitureMoved?(id, Double(node.position.x / size.width))
        }
    }

    private func cancelPendingDrag() {
        dragArmTimer?.invalidate()
        dragArmTimer = nil
        pendingDragNode = nil
    }

    // MARK: - 摇晃

    private var isStartled = false

    private func startMotion() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data, let pet = self.pet, !self.isStartled else { return }
            let a = data.acceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            // 静止时约为 1g。超过 1.8 认为是明显摇晃。
            guard magnitude > 1.8 else { return }
            self.startle(pet)
        }
    }

    private func startle(_ pet: SKSpriteNode) {
        isStartled = true
        behavior = .startled
        touchPoint = nil
        showEmote(.alert)
        let shake = SKAction.sequence([
            .moveBy(x: -6, y: 0, duration: 0.05),
            .moveBy(x: 12, y: 0, duration: 0.05),
            .moveBy(x: -6, y: 0, duration: 0.05)
        ])
        pet.run(.repeat(shake, count: 3)) { [weak self] in
            guard let self else { return }
            self.isStartled = false
            self.behavior = .idle
            self.nextDecisionAt = 0
            self.applyIdlePose()
        }
    }
}
