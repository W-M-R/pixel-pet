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

    /// 宠物的**精确**位置（未吸附）。
    ///
    /// ⚠️ 不能直接把吸附后的值写回 `pet.position` 当作累加基准：
    /// 120fps 下最远处每帧只走 0.22pt，小于 1 物理像素（0.33pt），
    /// 吸附会把位移抹成 0 —— 宠物原地不动。
    /// 所以精确位置在这里累加，`pet.position` 只承载显示用的吸附值。
    private var exactPosition: CGPoint = .zero

    // MARK: - 状态

    private var sheet: SKTexture?
    private var sleepSheet: SKTexture?
    private var roomSheet: SKTexture?
    private var emoteSheet: SKTexture?
    private var iconSheet: SKTexture?
    private var pet: SKSpriteNode!
    private var shadow: SKShapeNode!
    /// 气泡层。实现在 BubbleLayer —— 它通过 anchor 闭包取位置，
    /// 不需要知道宠物是什么、有没有换过、当前缩放多少。
    private var bubbles: BubbleLayer?
    private var foodNode: SKNode?

    private var colorIndex: Int = 0
    private var breed: PetBreed = .cat
    private var stage: PetStage = .adult

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

    /// 墙脚线。墙与地面的分界，也是地板的最远处。
    private var wallBaseY: CGFloat { size.height * 0.30 }

    /// 地板平面。宠物在这个梯形区域里自由走动（不再是一条线）。
    ///
    /// 前缘留 0.055H 而不是贴到 0：底部要给操作栏留位置，
    /// 而且宠物太靠下会被自己的影子挤出画面。
    private var floor: FloorPlane {
        FloorPlane(backY: wallBaseY - pixelScale * 2,
                   frontY: size.height * 0.055,
                   width: size.width)
    }

    /// 兼容用：默认站位取地板中段偏近处
    private var groundY: CGFloat { floor.y(atDepth: 0.35) }

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

    /// 配置宠物外观。阶段变化会换 sheet（幼年/成长/老年是程序化派生的）。
    func configure(breed: PetBreed, colorIndex: Int, stage: PetStage) {
        let changed = breed.id != self.breed.id
            || colorIndex != self.colorIndex
            || stage != self.stage
            || pet == nil
        guard changed else { return }
        self.breed = breed
        self.colorIndex = colorIndex
        self.stage = stage
        loadSheets()
        if pet != nil { applyWalkAnimation() }
    }

    /// 成年用源图，其余阶段用 tools/make_stages.py 生成的派生 sheet。
    /// 派生 sheet 缺失时回退源图，保证不会白屏。
    private func loadSheets() {
        sheet = PetSpriteSheet.loadSheet(named: breed.sheetName(for: stage))
            ?? PetSpriteSheet.loadSheet(named: breed.sheetName)
        sleepSheet = PetSpriteSheet.loadSheet(named: breed.sleepSheetName)
    }

    private func buildScene() {
        removeAllChildren()
        guard size.width > 1 else { return }

        loadSheets()
        roomSheet = RoomSpriteSheet.loadSheet(named: "house_objects")
        emoteSheet = RoomSpriteSheet.loadSheet(named: "emotes")
        iconSheet = RoomSpriteSheet.loadSheet(named: "icons")

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
        pet.setScale(pixelScale * stage.bodyScale / CGFloat(PetSpriteSheet.prescale))
        exactPosition = floor.clamp(CGPoint(x: size.width / 2, y: floor.y(atDepth: 0.35)))
        pet.position = exactPosition
        pet.zPosition = 10
        addChild(pet)

        applyWalkAnimation()
        syncShadow()

        // anchor 用闭包而非直接传节点 —— 宠物会换 sheet、换缩放，
        // 闭包保证每帧取到的都是当前值
        bubbles = BubbleLayer(
            parent: self,
            unit: pixelScale,
            emoteSheet: emoteSheet,
            iconSheet: iconSheet,
            anchor: { [weak self] in
                guard let self, self.pet != nil else { return .zero }
                return CGPoint(x: self.pet.position.x, y: self.petFeetY)
            },
            sceneWidth: { [weak self] in self?.size.width ?? 0 })
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
    /// 画房间。实现在 `RoomRenderer` —— 它只依赖 size/wallBaseY/unit，
    /// 不读宠物状态，抽出去后改房间视觉不用在行为逻辑里翻找。
    private func buildFloor() {
        RoomRenderer.build(into: self, size: size,
                           wallBaseY: wallBaseY, unit: pixelScale)
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
        let frames = PetSpriteSheet.frames(from: sheet, action: .eat,
                                           colorIndex: colorIndex)
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
        applyDepthScale()

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
            let s0 = currentPetScale
            pet.yScale = s0 * 0.82
            pet.xScale = s0 * 1.04
            let breathe = SKAction.sequence([
                .scaleY(to: s0 * 0.86, duration: 1.4),
                .scaleY(to: s0 * 0.82, duration: 1.4)
            ])
            breathe.timingMode = .easeInEaseOut
            pet.run(.repeatForever(breathe), withKey: "anim")
        }
    }

    /// 站住时的姿态。
    ///
    /// 用第 4 格 —— 它是坐/趴姿，正是宠物停下来该有的样子。
    /// （早先误把它当走路帧塞进循环，导致走路时每周期「抽」一下趴下。）
    ///
    /// ⚠️ cat 的 r1/r2 第 4 格是空白，所以正/背向时回退到走路第 0 帧。
    private func applyIdlePose() {
        guard let sheet, let pet else { return }
        pet.removeAction(forKey: "anim")
        let sideways = (facing == .right || facing == .left)
        pet.texture = PetSpriteSheet.texture(from: sheet,
                                             row: facing.row,
                                             column: sideways
                                                ? PetSpriteSheet.idleColumn : 0,
                                             colorIndex: colorIndex)
        pet.texture?.filteringMode = .nearest
        // 从睡姿回来要复位缩放，并保留当前深度的透视缩放
        applyDepthScale()
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
        bubbles?.sync()
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
        let target = floor.randomPoint()
        behavior = .wandering(target: target)
        updateFacing(toward: target)
        applyWalkAnimation()
    }

    /// 朝目标走一步。返回 true 表示已到达。
    ///
    /// 二维移动：x 和 y 同时推进。速度按 depth 缩放 —— 远处的宠物
    /// 视觉上更小，如果用同样的 pt/秒 会显得走得飞快。
    @discardableResult
    private func moveToward(_ target: CGPoint, speed: CGFloat, dt: TimeInterval) -> Bool {
        let dx = target.x - exactPosition.x
        let dy = target.y - exactPosition.y
        let dist = sqrt(dx * dx + dy * dy)

        // 到达阈值也按 depth 缩放，远处判定更宽松
        let d = floor.depth(atY: exactPosition.y)
        let arriveThreshold = 4 * floor.scaleFactor(atDepth: d)
        if dist < arriveThreshold { return true }

        let step = speed * floor.scaleFactor(atDepth: d) * CGFloat(dt)
        if step >= dist {
            exactPosition = floor.clamp(target)
        } else {
            exactPosition = floor.clamp(CGPoint(x: exactPosition.x + dx / dist * step,
                                                y: exactPosition.y + dy / dist * step))
        }
        pet.position = exactPosition
        updateFacing(toward: target)
        applyDepthScale()
        return false
    }

    /// 按移动向量选朝向。
    ///
    /// 四方向的选择规则：谁的位移分量更大就用那个方向。
    /// 加了 1.35 的横向偏好系数 —— 斜着走时优先显示侧视，
    /// 因为侧视帧的动作辨识度明显高于正面/背面（正背视只有 13px 宽）。
    private func updateFacing(toward target: CGPoint) {
        let dx = target.x - exactPosition.x
        let dy = target.y - exactPosition.y

        let newFacing: PetSpriteSheet.Facing
        if abs(dx) * 1.35 >= abs(dy) {
            newFacing = dx >= 0 ? .right : .left
        } else {
            // y 增大 = 往里走（远离镜头）= 看到背面
            newFacing = dy > 0 ? .back : .front
        }

        guard newFacing != facing else { return }
        facing = newFacing
        applyWalkAnimation()
    }

    /// 当前深度下宠物应有的基准缩放。所有动画都要以它为基准，
    /// 不能写死 pixelScale —— 否则宠物在远处做动作会突然放大。
    ///
    /// **连续值，不做量化。** 纹理已用 nearest 预放大 `prescale` 倍
    /// （见 `PetSpriteSheet.prescale`），所以这里要除掉那个倍数，
    /// 再由 linear 采样平滑地缩到目标尺寸 —— 这样 texel 边界不会
    /// 随缩放逐帧重新分配，走动就不闪了。
    private var currentPetScale: CGFloat {
        let depth = pet == nil ? 0 : floor.depth(atY: exactPosition.y)
        let target = floor.petScale(pixelScale: pixelScale,
                                    bodyScale: stage.bodyScale,
                                    depth: depth)
        return target / CGFloat(PetSpriteSheet.prescale)
    }

    /// 按当前 depth 调整宠物缩放，制造远近感。
    private func applyDepthScale() {
        guard let pet, !isSleeping else { return }
        pet.setScale(currentPetScale)
    }

    private func syncShadow() {
        guard let pet, let shadow else { return }
        // 影子贴在脚底，略微下沉 1 源像素，看起来像压在地上
        let d = floor.depth(atY: pet.position.y)
        let f = floor.scaleFactor(atDepth: d)
        shadow.position = CGPoint(x: pet.position.x, y: petFeetY - pixelScale * f)
        shadow.setScale(f)
        // 远处影子淡一些
        shadow.alpha = 0.18 * (0.7 + 0.3 * (1 - d))
    }

    // MARK: - 外部触发

    func triggerEat() {
        guard pet != nil else { return }
        behavior = .eating
        touchPoint = nil
        // 睡姿改过 yScale，先复位再放盆，否则 petFeetY 算出来是压扁后的位置
        pet.removeAction(forKey: "anim")
        applyDepthScale()
        dropFoodBowl()
        // 像素肉图标（icons.png 第 0 格）。原来是 🍖 emoji ——
        // emoji 字形随 iOS 版本变，缺字体时会渲染成问号。
        bubbles?.uiIcon(0)
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
        // 按品种取 —— 原来写死 5（按猫实测），而狗的内容底边在 y=28，
        // 所以狗的影子和食盆一直偏 2 源像素
        let bottomPadding = breed.footPadding
        // ⚠️ 纹理已预放大 prescale 倍，pet.yScale 相应变小了同样倍数。
        // 「1 源像素在屏幕上占多少 pt」= yScale × prescale。
        return pet.position.y
            - (frameH / 2 - bottomPadding) * sourcePixelUnit
    }

    /// 1 个**源图**像素当前在屏幕上占多少 pt。
    ///
    /// 纹理预放大后 `pet.xScale` 不再等于「源像素 → pt」的倍数，
    /// 差了 `prescale`。所有拿源图坐标算屏幕位置的地方都要用这个。
    private var sourcePixelUnit: CGFloat {
        pet.yScale * CGFloat(PetSpriteSheet.prescale)
    }

    /// 喂食时在宠物脚边放一个食盆。
    /// 素材包里没有食盆（而且那套是俯视的），所以手绘一个侧视的，
    /// 尺寸取 pixelScale 整数倍，与宠物同像素密度。
    private func dropFoodBowl() {
        foodNode?.removeFromParent()

        // 食盆和宠物同深度，所以用宠物当前缩放，不是 pixelScale。
        // 注意要换算成「源像素 → pt」，纹理预放大不影响手绘元素。
        let u = sourcePixelUnit        // 1 源像素 = u pt
        let container = SKNode()

        /// 以「盆底左边缘」为原点画，方便对齐地面
        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: SKColor) {
            let n = SKSpriteNode(color: color, size: CGSize(width: w * u, height: h * u))
            n.anchorPoint = CGPoint(x: 0, y: 0)
            n.position = CGPoint(x: x * u, y: y * u)
            container.addChild(n)
        }

        let bowlDark = RoomPalette.bowlDark.sk
        let bowlLite = RoomPalette.bowlLite.sk
        let kibble   = RoomPalette.bowlFood.sk

        // 盆身（宽 12 源像素，居中在原点两侧）
        block(-6, 0, 12, 2, bowlDark)
        block(-7, 2, 14, 1, bowlLite)
        // 食物堆
        block(-4, 3, 3, 2, kibble)
        block(0, 3, 4, 2, kibble)
        block(-2, 5, 3, 1, kibble)

        // 放在宠物**面朝的那一侧**，脚底同一水平线上。
        // 距离 = 宠物身体半宽(12源像素) + 盆半宽(7) + 一点间隙 ≈ 20 源像素
        // 朝向正面/背面时放右侧，避免盆压在身上
        let dir: CGFloat = facing == .left ? -1 : 1
        let side: CGFloat = dir * u * 20
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
        // 基准取**吸附后的显示位置**，和 moveToward 写入的值一致，
        // 否则蹦完会和 exactPosition 差半个像素，下一帧突跳一下。
        let baseY = exactPosition.y
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

    /// 按互动 id 播对应动画。
    ///
    /// 只做分发，不归一动画本体 —— 三个动画的实现方式完全不同
    /// （帧序列 / moveTo 序列 / fadeAlpha 序列），强行抽象成协议
    /// 只能消掉几行 emote 调用，却让「洗澡时宠物做什么」变得要跳转才能看懂。
    func playAnimation(for interactionID: String) {
        switch interactionID {
        case "play":  triggerPlay()
        case "clean": triggerClean()
        default:      break
        }
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

    // MARK: - 气泡（实现在 BubbleLayer）

    /// 台词气泡。转发给 BubbleLayer —— 保留这个方法是因为
    /// PetHomeView 已在多处调用，改签名的收益不大。
    func showSpeech(_ text: String,
                    duration: TimeInterval = BubbleLayer.defaultSpeechDuration) {
        bubbles?.speak(text, duration: duration)
    }

    func showNeedBubble(_ need: PetNeed) { bubbles?.need(need) }

    private func showEmote(_ emote: RoomSpriteSheet.Emote) {
        bubbles?.emote(emote)
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
            touchPoint = floor.clamp(location)
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
            .scaleX(to: currentPetScale * 1.12, y: currentPetScale * 0.88, duration: 0.08),
            .scale(to: currentPetScale, duration: 0.14)
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
        touchPoint = floor.clamp(location)
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
