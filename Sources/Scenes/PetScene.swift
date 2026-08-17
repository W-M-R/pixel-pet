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

    private var roomSheet: SKTexture?
    private var emoteSheet: SKTexture?
    private var iconSheet: SKTexture?
    /// 景里的全部宠物。每只自己持有节点、影子、行为状态
    /// （见 `PetActor`）—— 共用一份状态的话，一只走路另一只会跟着走。
    private var actors: [PetActor] = []

    /// 当前选中那只的 id。三个互动按钮作用于它，气泡也挂在它头上。
    private var selectedID: String?

    /// 最后一次 `sync` 收到的存档快照。
    ///
    /// **必须留一份。** `buildScene()` 会清空 `actors`（尺寸变化要重排家具），
    /// 而 UI 层只在数据变化时才 `sync` —— 两者时序不保证：
    /// 首次 `didMove` 时场景还没尺寸，`sync` 直接返回，
    /// 之后 `buildScene` 建好房间却没有宠物可建，屏幕上就一只都没有。
    /// 存快照让 `buildScene` 能自己重放。
    private var lastPets: [PetState] = []

    private var selected: PetActor? {
        actors.first { $0.petID == selectedID } ?? actors.first
    }
    /// 气泡层。实现在 BubbleLayer —— 它通过 anchor 闭包取位置，
    /// 不需要知道宠物是什么、有没有换过、当前缩放多少。
    private var bubbles: BubbleLayer?
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
    var onFurnitureMoved: ((String, Double, Double) -> Void)?

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
                   frontY: floorFrontY,
                   width: size.width)
    }

    /// 兼容用：默认站位取地板中段偏近处
    private var groundY: CGFloat { floor.y(atDepth: 0.35) }

    /// 地板最近处的 y —— **要把底部按钮区让出来**。
    ///
    /// 原来是 `size.height * 0.055`（≈53pt），而三个互动按钮
    /// 占到 y≈97pt（55pt 按钮 + 34pt 安全区 + 8pt 边距）。
    /// 结果宠物能整个走到按钮上面，挡住「喂食」很难点。
    ///
    /// SpriteKit 场景是全屏的（`ignoresSafeArea`），所以这里得自己
    /// 算出按钮区的高度。数值和 `PetHomeView.actionBar` 的布局耦合 ——
    /// 由 `testFloorClearsActionBar` 守着，改按钮尺寸时会失败提醒。
    private var floorFrontY: CGFloat {
        // 按钮本体：图标 24 + 间距 4 + 文字 13 + 上下内边距 14
        let buttonHeight: CGFloat = 55
        // 底部安全区（Home 指示器）。取不到时用 34 兜底。
        let safeBottom = view?.safeAreaInsets.bottom ?? 34
        // VStack 的 .padding(.bottom, 8) + 一点余量，让脚底不贴按钮边
        return buttonHeight + safeBottom + 8 + pixelScale * 2
    }

    var onPetTouched: (() -> Void)?

    /// 点中某只时回调，让 UI 层同步选中状态（store 才是真相源）。
    var onPetSelected: ((String) -> Void)?

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
        bowlNode = nil
        bowlItem = nil
        for node in furnitureNodes { node.removeFromParent() }
        furnitureNodes.removeAll()
        guard let roomSheet, size.width > 1 else { return }
        let scale = pixelScale
        for slot in layout.slots {
            addFurniture(slot, sheet: roomSheet, scale: scale)
        }
    }

    /// 配置宠物外观。阶段变化会换 sheet（幼年/成长/老年是程序化派生的）。
    /// 按存档同步场景里的宠物。
    ///
    /// 增删改都在这里：新养的加进来、删掉的移走、外观变了重贴图。
    /// **不重建整个场景** —— 重建会让所有宠物位置归零、动画重启。
    func sync(pets: [PetState], selectedID: String) {
        self.selectedID = selectedID
        self.lastPets = pets
        guard size.width > 1 else { return }

        // 移走已经不存在的
        let liveIDs = Set(pets.map(\.id))
        for a in actors where !liveIDs.contains(a.petID) {
            a.removeFromScene()
        }
        actors.removeAll { !liveIDs.contains($0.petID) }

        for (index, p) in pets.enumerated() {
            if let a = actors.first(where: { $0.petID == p.id }) {
                // 已有：只在外观真的变了时重贴图
                if a.updateAppearance(breed: p.breed, colorIndex: p.colorIndex,
                                      stage: p.stage) {
                    let d = floor.depth(atY: a.exactPosition.y)
                    a.applyDepthScale(depth: d)
                    a.reapplyCurrentPose(depth: d)
                }
            } else {
                actors.append(spawn(p, index: index, total: pets.count))
            }
        }
    }

    /// 造一只新 actor 并摆到场上。
    ///
    /// 横向按序号错开，避免多只叠在一起 —— 之后它们各自随机游走，
    /// 初始位置只需要不重叠。
    private func spawn(_ p: PetState, index: Int, total: Int) -> PetActor {
        let a = PetActor(petID: p.id, breed: p.breed, colorIndex: p.colorIndex,
                         stage: p.stage, pixelScale: pixelScale)
        let slots = max(total, 1) + 1
        let x = size.width * CGFloat(index + 1) / CGFloat(slots)
        let depth = 0.35 + CGFloat(index % 2) * 0.15   // 前后也错开一点
        a.exactPosition = floor.clamp(CGPoint(x: x, y: floor.y(atDepth: depth)))
        a.node.position = a.exactPosition
        a.attach(to: self)
        a.applyDepthScale(depth: floor.depth(atY: a.exactPosition.y))
        a.applyWalkAnimation()
        return a
    }

    private func buildScene() {
        removeAllChildren()
        guard size.width > 1 else { return }

        // 自绘的侧视家具。原来是 house_objects.png（OGA，俯视）——
        // 和侧视宠物放一起怎么摆都别扭，见 RoomLayout.default 的注释。
        roomSheet = RoomSpriteSheet.loadSheet(named: "furniture")
        emoteSheet = RoomSpriteSheet.loadSheet(named: "emotes")
        iconSheet = RoomSpriteSheet.loadSheet(named: "icons")

        buildRoom()

        // 宠物由 sync(pets:selectedID:) 建 —— 场景不知道有几只，
        // 那是存档的事。这里只搭房间，然后用快照重放。
        actors.removeAll()

        // anchor 用闭包而非直接传节点：宠物会换 sheet、换缩放，
        // 而且**选中的是哪只会变** —— 闭包保证每帧取到当前那只的位置。
        bubbles = BubbleLayer(
            parent: self,
            unit: pixelScale,
            emoteSheet: emoteSheet,
            iconSheet: iconSheet,
            anchor: { [weak self] in
                guard let a = self?.selected else { return .zero }
                return CGPoint(x: a.node.position.x, y: a.feetY)
            },
            sceneWidth: { [weak self] in self?.size.width ?? 0 })

        // 重放快照 —— 见 lastPets 的注释
        if !lastPets.isEmpty {
            sync(pets: lastPets, selectedID: selectedID ?? lastPets[0].id)
        }
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
    /// 摆一件家具。
    ///
    /// 素材是**侧视**的自绘 sheet（`Assets/room/furniture.png`）——
    /// 原来用的 OGA Home Objects 是俯视的，和侧视宠物放一起
    /// 「怎么摆都别扭」，见 `RoomLayout.default` 的注释。
    private func addFurniture(_ slot: RoomLayout.Slot,
                              sheet: SKTexture,
                              scale: CGFloat) {
        guard let item = FurnitureItem.byID(slot.id),
              let tex = RoomSpriteSheet.furnitureTexture(
                from: sheet, index: item.sheetIndex, cellWidth: item.cellWidth)
        else { return }

        let node = SKSpriteNode(texture: tex)
        node.texture?.filteringMode = .nearest
        // 底部锚点 —— 家具贴地，位置的语义是「底边站在哪」
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.setScale(FurnitureItem.displayScale * slot.scaleMul)

        // ⚠️ **家具底边要对齐宠物的脚底，不是宠物的节点中心。**
        //
        // `FloorPlane` 的 y 全部按宠物**节点中心**算
        // （spawn 时 `node.position = floor.y(atDepth:)`）。
        // 而宠物的脚底比中心低 `(cell/2 - footPadding)` 源像素 ——
        // 猫是 11 源像素、约 37pt。
        //
        // 家具原来直接把 `floor.y(atDepth:)` 当底边用，
        // 于是同一个 depth 下家具底边和宠物**中心**齐平，
        // 家具就比宠物脚底高了一截 —— 碗看起来像悬浮在空中。
        let centerY = floor.y(atDepth: slot.depth)
        node.position = CGPoint(x: size.width * slot.xRatio,
                                y: centerY - petFootDrop(atDepth: slot.depth))
        node.zPosition = slot.z
        node.name = slot.id
        addChild(node)
        furnitureNodes.append(node)

        if item.isBowl {
            bowlNode = node
            bowlItem = item
        }
    }

    /// 同一个 depth 下，宠物脚底比节点中心低多少 pt。
    ///
    /// 家具要减掉这个值才能和宠物「站在同一条线上」。
    /// 用第一只宠物的布局算 —— 各品种的 footPadding 差 2 源像素（8pt），
    /// 家具对齐取一个代表值足够，不值得为此让家具按品种偏移。
    private func petFootDrop(atDepth depth: CGFloat) -> CGFloat {
        guard let a = actors.first ?? nil else {
            // 还没有宠物时用猫的参数兜底
            let unit = pixelScale * PetStage.adult.bodyScale
            return (32 / 2 - 5) * unit
        }
        let unit = a.scale(atDepth: depth) * CGFloat(PetSpriteSheet.prescale)
        return (a.layoutCell / 2 - a.layoutFootPadding) * unit
    }

    /// 当前的饭碗节点与规格。没买碗时是 nil。
    private var bowlNode: SKNode?
    private var bowlItem: FurnitureItem?

    /// 碗在地板坐标系里的 y（= 宠物节点中心的那条线）。
    ///
    /// 注意碗节点的 `position.y` 是**底边**且已经减过 `petFootDrop`，
    /// 所以要加回来才是地板坐标。
    private var bowlCenterY: CGFloat {
        guard let bowl = bowlNode else { return floor.y(atDepth: 0.55) }
        let d = floor.depth(atY: bowl.position.y + petFootDrop(atDepth: 0.5))
        return floor.y(atDepth: d)
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

    override func update(_ currentTime: TimeInterval) {
        guard !actors.isEmpty else { return }
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime

        // **每只独立驱动。** 共用一份 behavior 的话，
        // 一只决定走路，另一只会跟着走。
        for a in actors {
            step(a, at: currentTime, dt: dt)
        }
        sortByDepth()
        bubbles?.sync()
    }

    /// 按 y 排 z —— **2.5D 的遮挡关系**。
    ///
    /// 谁的脚底更靠下（y 更小 = 离镜头更近），谁画在前面。
    ///
    /// 这是你要的"视觉反馈"：宠物和家具**不做碰撞**（可以穿过去，
    /// 也可以互相交叉走），但走到家具前面就挡住它、走到后面就被挡住。
    /// 靠遮挡表达前后关系，比让宠物绕路自然得多 ——
    /// 绕路需要寻路，而且房间这么小，绕起来会显得很蠢。
    ///
    /// 顺带解决了「碗像悬浮在空中」：碗和宠物进同一套深度排序后，
    /// 站在碗后面的宠物会被碗遮住下半身，那个遮挡就是"碗在地上"的证据。
    private func sortByDepth() {
        // 家具和宠物一起排。用脚底/底边（而非节点中心）——
        // 那才是"站在地板哪个位置"。
        var items: [(node: SKNode, footY: CGFloat)] = actors.map {
            ($0.node, $0.feetY)
        }
        for n in furnitureNodes {
            // 家具是底部锚点，position.y 就是底边
            items.append((n, n.position.y))
        }
        // footY 越小（越近）→ zPosition 越大（越靠前）
        for (i, e) in items.sorted(by: { $0.footY > $1.footY }).enumerated() {
            e.node.zPosition = 10 + CGFloat(i)
        }
        // 吃饭中的宠物强制盖碗之上 —— 头压住碗口才像"埋进碗里"。
        // 否则按脚底排序时它在碗后面，头会被碗沿挡掉。
        if let bowl = bowlNode {
            for a in actors where a.isEating {
                a.node.zPosition = bowl.zPosition + 0.5
            }
        }
        // 影子要跟着自己的宠物，且在它下面一层
        for a in actors {
            a.shadow.zPosition = a.node.zPosition - 0.5
        }
    }

    /// 推进一只宠物一帧。
    ///
    /// 只有**选中那只**会追手指 —— 全都追的话点一下屏幕所有宠物一起挤过来，
    /// 而且分不清在跟谁互动。
    private func step(_ a: PetActor, at time: TimeInterval, dt: TimeInterval) {
        let isSelected = (a.petID == selected?.petID)

        if let touchPoint, isSelected, !isSleeping(a) {
            a.behavior = .following
            moveToward(a, target: touchPoint, speed: followSpeed, dt: dt)
        } else {
            switch a.behavior {
            case .following:
                a.behavior = .idle
                a.nextDecisionAt = time + 0.4
            case .idle:
                if time > a.nextDecisionAt { decideNextMove(a, at: time) }
            case .wandering(let target):
                if moveToward(a, target: target, speed: walkSpeed, dt: dt) {
                    a.behavior = .idle
                    a.applyIdlePose()
                    a.nextDecisionAt = time + .random(in: 1.2...3.5)
                }
            case .walkingToBowl(let target):
                if moveToward(a, target: target, speed: followSpeed, dt: dt) {
                    startChewing(a)
                }
            case .eating, .startled, .sleeping:
                break
            }
        }
        syncShadow(a)
    }

    /// 由 UI 层按 `PetState.isDrowsy` 驱动。困了就趴下，休息够了自己起来。
    ///
    /// 作用于全部宠物 —— 作息是按真实时间算的，不分选中与否。
    func setSleeping(_ sleeping: Bool) {
        for a in actors {
            if sleeping {
                guard !isSleeping(a) else { continue }
                a.behavior = .sleeping
                a.applySleepPose(depth: depth(of: a))
            } else {
                guard isSleeping(a) else { continue }
                a.behavior = .idle
                a.nextDecisionAt = 0
                a.applyIdlePose()
            }
        }
        if sleeping {
            touchPoint = nil
            showEmote(.sleep)
        }
    }

    private func isSleeping(_ a: PetActor) -> Bool {
        if case .sleeping = a.behavior { return true }
        return false
    }

    private func depth(of a: PetActor) -> CGFloat {
        floor.depth(atY: a.exactPosition.y)
    }

    private func decideNextMove(_ a: PetActor, at time: TimeInterval) {
        // 70% 概率走一段，30% 继续待着
        guard Double.random(in: 0...1) < 0.7 else {
            a.nextDecisionAt = time + .random(in: 1...2.5)
            return
        }
        let target = floor.randomPoint()
        a.behavior = .wandering(target: target)
        updateFacing(a, toward: target)
        a.applyWalkAnimation()
    }

    /// 朝目标走一步。返回 true 表示已到达。
    ///
    /// 二维移动：x 和 y 同时推进。速度按 depth 缩放 —— 远处的宠物
    /// 视觉上更小，如果用同样的 pt/秒 会显得走得飞快。
    @discardableResult
    private func moveToward(_ a: PetActor, target: CGPoint,
                            speed: CGFloat, dt: TimeInterval) -> Bool {
        let dx = target.x - a.exactPosition.x
        let dy = target.y - a.exactPosition.y
        let dist = sqrt(dx * dx + dy * dy)

        // 到达阈值也按 depth 缩放，远处判定更宽松
        let d = depth(of: a)
        let arriveThreshold = 4 * floor.scaleFactor(atDepth: d)
        if dist < arriveThreshold { return true }

        let step = speed * floor.scaleFactor(atDepth: d) * CGFloat(dt)
        if step >= dist {
            a.exactPosition = floor.clamp(target)
        } else {
            a.exactPosition = floor.clamp(
                CGPoint(x: a.exactPosition.x + dx / dist * step,
                        y: a.exactPosition.y + dy / dist * step))
        }
        a.node.position = a.exactPosition
        // 走向饭碗时**不改朝向** —— 朝向在派位时就定好了（决定嘴在哪一侧），
        // 每帧按"朝目标点"重算会让宠物走到位后背对着碗。
        if case .walkingToBowl = a.behavior {} else {
            updateFacing(a, toward: target)
        }
        applyDepthScale(a)
        return false
    }

    /// 按移动向量选朝向。
    ///
    /// 四方向的选择规则：谁的位移分量更大就用那个方向。
    /// 加了 1.35 的横向偏好系数 —— 斜着走时优先显示侧视，
    /// 因为侧视帧的动作辨识度明显高于正面/背面（正背视只有 13px 宽）。
    private func updateFacing(_ a: PetActor, toward target: CGPoint) {
        let dx = target.x - a.exactPosition.x
        let dy = target.y - a.exactPosition.y

        let newFacing: PetSpriteSheet.Facing
        if abs(dx) * 1.35 >= abs(dy) {
            newFacing = dx >= 0 ? .right : .left
        } else {
            // y 增大 = 往里走（远离镜头）= 看到背面
            newFacing = dy > 0 ? .back : .front
        }

        guard newFacing != a.facing else { return }
        a.facing = newFacing
        a.applyWalkAnimation()
    }

    /// 按当前 depth 调整缩放，制造远近感。
    ///
    /// **连续值，不做量化。** 纹理已用 nearest 预放大 `prescale` 倍，
    /// 所以 `PetActor.scale(atDepth:)` 里除掉了那个倍数，
    /// 再由 linear 采样平滑缩到目标尺寸 —— texel 边界不会随缩放
    /// 逐帧重新分配，走动就不闪了。
    private func applyDepthScale(_ a: PetActor) {
        guard !isSleeping(a) else { return }
        a.applyDepthScale(depth: depth(of: a))
    }

    private func syncShadow(_ a: PetActor) {
        let d = floor.depth(atY: a.node.position.y)
        let f = floor.scaleFactor(atDepth: d)
        // 影子贴在脚底，略微下沉 1 源像素，看起来像压在地上
        a.syncShadow(depth: d, footInset: f)
        a.shadow.setScale(f)
        // 远处影子淡一些
        a.shadow.alpha = 0.18 * (0.7 + 0.3 * (1 - d))
    }

    // MARK: - 外部触发

    /// 喂食。
    ///
    /// **有饭碗时所有宠物围过来吃**（按碗的容量排位），
    /// 没碗时回退到「在选中那只脚边放个临时食盆」的老行为。
    ///
    /// 容量按侧视排：宠物头只能朝左右，站在碗上方/下方会像叠在碗上。
    /// 所以只排左右两侧 —— 圆碗 2 位，长碗 4 位（左右各两、前后微错开）。
    func triggerEat() {
        if let bowl = bowlNode, let item = bowlItem {
            gatherToBowl(bowl, item: item)
        } else if let a = selected {
            feedInPlace(a)
        }
    }

    /// 围到碗边吃 —— **头要埋进碗里**。
    ///
    /// ## 素材事实
    ///
    /// 进食帧（`eatRow` = r4）是**背面俯视**姿态：尾巴在上、头在下，
    /// 和 r2（朝后走）几乎一样。它没有侧向版本，也不是"低头"动作。
    ///
    /// 所以做不到"围着碗一圈各自侧头吃"。能做到的是：
    /// 宠物背对镜头、**头压在碗上**，靠遮挡表达"埋进碗里"。
    ///
    /// ## 站位怎么算
    ///
    /// 关键是让**头**落在碗心，不是脚底或身体中心 ——
    /// 拿身体中心对碗的话，头会在碗上方一截，看起来只是站在碗旁边
    /// （前几轮就是这个问题）。
    ///
    /// 头在帧里距格底 `eatHeadFromBottom`（实测 8 源像素），
    /// 所以节点中心 = 碗心 + (cell/2 - 8) × unit。
    ///
    /// 碗的位置由玩家自由拖动，所以这里一切都从 `bowl.position` 现算。
    private func gatherToBowl(_ bowl: SKNode, item: FurnitureItem) {
        touchPoint = nil
        bubbles?.uiIcon(0)

        // 按「离碗近的先来」排队，容量满了的这次就不吃
        let queue = actors.sorted {
            abs($0.node.position.x - bowl.position.x)
                < abs($1.node.position.x - bowl.position.x)
        }

        // 碗的**实际屏幕矩形**。
        //
        // 不要从 `bowl.position` 手算 —— 它是底部锚点、且摆位时已经减过
        // `petFootDrop`，再拿它加半个碗高会算出一个偏低一大截的"碗心"
        // （实测宠物直接跑到碗下方去了）。
        // 用 `calculateAccumulatedFrame()` 拿真实边界，最不容易错。
        let bowlRect = bowl.calculateAccumulatedFrame()
        let bowlCX = bowlRect.midX
        // 碗口略高于几何中心 —— 食物画在碗的上半部
        let bowlMouthY = bowlRect.minY + bowlRect.height * 0.62

        for (i, a) in queue.enumerated() where i < item.feedSlots {
            // 睡着的先叫醒 —— `step()` 会跳过 .sleeping，
            // 不唤醒它永远走不过来（实测：一只吃上了，另一只在原地睡）
            if isSleeping(a) {
                a.nextDecisionAt = 0
                a.applyIdlePose()
            }

            // 用碗所在深度的缩放 —— 宠物走到那里就是这个大小
            let depthThere = floor.depth(atY: bowlMouthY)
            let unit = a.scale(atDepth: depthThere) * CGFloat(PetSpriteSheet.prescale)

            // 多只时横向铺开，间距略小于身体宽度 —— 挤在一起才像抢食
            let bodyW = 22 * unit
            let step: CGFloat
            switch i {
            case 0: step = 0
            case 1: step = 1
            case 2: step = -1
            default: step = CGFloat(i % 2 == 1 ? (i + 1) / 2 : -((i + 1) / 2))
            }

            // ⚠️ **走路目标必须是地板上的合法点。**
            //
            // 曾经直接把「头埋进碗」的位置当走路目标，但那个 y 在地板范围
            // 之上，而 `moveToward` 里会 `floor.clamp(target)` ——
            // 位置被夹回地板，距离永远大于到达阈值，**永远到不了**，
            // 所以一直停在 `.walkingToBowl`，播的是走路动画而不是吃饭。
            // 表现就是"宠物站在碗旁边用走路姿态"。
            //
            // 正解：走路用地板坐标，"埋进碗"是**到达后的视觉偏移**
            // （见 `startChewing`）。两件事分开，不跟地板系统对抗。
            let target = floor.clamp(CGPoint(x: bowlCX + step * bodyW,
                                             y: bowlMouthY))
            a.behavior = .walkingToBowl(target: target)
            // 记下头该埋到哪 —— 到达后由 startChewing 做视觉偏移
            a.eatAnchor = CGPoint(x: bowlCX + step * bodyW, y: bowlMouthY)
            a.applyWalkAnimation()
        }
    }

    /// 到碗边了，开始咀嚼。
    private func startChewing(_ a: PetActor) {
        a.behavior = .eating
        // 盖在碗沿上 —— 头压住碗口才像"埋进碗里"。
        // sortByDepth 每帧会重排 z，用这个标记让它把吃饭的宠物提到碗之上。
        a.isEating = true

        // **把头挪进碗里。**
        //
        // 走路目标只能是地板上的合法点（见 gatherToBowl 的注释），
        // 所以"埋进碗"这一步在到达后用视觉偏移完成：
        // 头在进食帧里距格底 `eatHeadFromBottom`（实测 8 源像素），
        // 要让头落在碗心，节点中心就得在碗心上方 (cell/2 - 8) × unit。
        if let anchor = a.eatAnchor {
            let unit = a.sourcePixelUnit
            let headOffset = (a.layoutCell / 2 - a.layoutEatHeadFromBottom) * unit
            let dest = CGPoint(x: anchor.x, y: anchor.y + headOffset)
            // 短促地凑过去，别硬切 —— 硬切会看起来像瞬移
            a.node.run(.move(to: dest, duration: 0.18), withKey: "lean")
        }
        // ⚠️ 这里**不设 facing**。进食帧固定取 `layout.eatRow`（第 4 行），
        // 那是正面低头的对称姿态，不看朝向 ——
        // 曾经在这里写 `a.facing = 碗在左还是右`，那行代码完全无效，
        // 却让人误以为"朝向已经处理过了"，掩盖了真正的问题
        // （素材没有侧向进食帧，所以必须站碗正后方）。
        a.applyEatAnimation { [weak self, weak a] in
            guard let a else { return }
            a.isEating = false
            a.eatAnchor = nil
            // 吃完退回地板上的合法位置 —— 否则它会停在偏移过的 y 上，
            // 下一次随机游走会从那个"悬空"的点开始算。
            if let floor = self?.floor {
                a.exactPosition = floor.clamp(a.node.position)
                a.node.position = a.exactPosition
            }
            a.behavior = .idle
            a.nextDecisionAt = 0
            a.applyIdlePose()
        }
    }

    /// 没买碗时的老行为：在脚边放个临时食盆。
    private func feedInPlace(_ a: PetActor) {
        a.behavior = .eating
        touchPoint = nil
        // 睡姿改过 yScale，先复位再放盆，否则 feetY 算出来是压扁后的位置
        a.node.removeAction(forKey: "anim")
        a.applyDepthScale(depth: depth(of: a))
        dropFoodBowl(for: a)
        // 像素肉图标（icons.png 第 0 格）。原来是 🍖 emoji ——
        // emoji 字形随 iOS 版本变，缺字体时会渲染成问号。
        bubbles?.uiIcon(0)
        a.applyEatAnimation { [weak a] in
            guard let a else { return }
            a.clearFoodBowl()
            a.behavior = .idle
            a.nextDecisionAt = 0
            a.applyIdlePose()
        }
    }

    /// 喂食时在宠物脚边放一个食盆。
    /// 素材包里没有食盆（而且那套是俯视的），所以手绘一个侧视的，
    /// 尺寸取 pixelScale 整数倍，与宠物同像素密度。
    private func dropFoodBowl(for a: PetActor) {
        a.clearFoodBowlImmediately()

        // 食盆和宠物同深度，所以用宠物当前缩放，不是 pixelScale。
        // 注意要换算成「源像素 → pt」，纹理预放大不影响手绘元素。
        let u = a.sourcePixelUnit      // 1 源像素 = u pt
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
        let dir: CGFloat = a.facing == .left ? -1 : 1
        let side: CGFloat = dir * u * 20
        container.position = CGPoint(x: a.node.position.x + side, y: a.feetY)
        container.zPosition = 11
        container.alpha = 0
        addChild(container)
        container.run(.fadeIn(withDuration: 0.15))
        a.setFoodBowl(container)
    }

    func triggerPlay() {
        guard let a = selected else { return }
        // 玩耍会叫醒宠物
        if isSleeping(a) {
            a.behavior = .idle
            a.nextDecisionAt = 0
            a.applyIdlePose()
        }
        showEmote(.music)

        // 蹦两下。用 moveTo 回到基准 y 而不是 moveBy 抵消位移 ——
        // moveBy 一旦被打断（中途切睡觉/换宠物），宠物会永久停在半空。
        // 基准取**吸附后的显示位置**，和 moveToward 写入的值一致，
        // 否则蹦完会和 exactPosition 差半个像素，下一帧突跳一下。
        let baseY = a.exactPosition.y
        let hop = SKAction.sequence([
            {
                let up = SKAction.moveTo(y: baseY + pixelScale * 7, duration: 0.16)
                up.timingMode = .easeOut
                return up
            }(),
            {
                let down = SKAction.moveTo(y: baseY, duration: 0.16)
                down.timingMode = .easeIn
                return down
            }()
        ])
        a.node.removeAction(forKey: "hop")
        a.node.run(.repeat(hop, count: 2), withKey: "hop")
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
        guard let a = selected else { return }
        showEmote(.droplet)
        // 结尾显式设回 alpha=1，防止动画被打断后宠物半透明卡住
        let fade = SKAction.sequence([
            .fadeAlpha(to: 0.55, duration: 0.18),
            .fadeAlpha(to: 1, duration: 0.18),
            .fadeAlpha(to: 0.55, duration: 0.18),
            .fadeAlpha(to: 1, duration: 0.18)
        ])
        a.node.removeAction(forKey: "clean")
        a.node.run(fade, withKey: "clean")
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
        guard let location = touches.first?.location(in: self),
              !actors.isEmpty else { return }

        // 先看是不是按在家具上 —— 长按才拖，短按当作点地面
        if let node = furnitureHit(at: location) {
            pendingDragNode = node
            dragArmTimer?.invalidate()
            dragArmTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                guard let self, let n = self.pendingDragNode else { return }
                self.beginDrag(n)
            }
        }

        // 点到哪只就选中它并抚摸。
        //
        // 多只可能视觉重叠，所以取**最靠前**的（y 小 = 离镜头近），
        // 和绘制顺序一致 —— 否则会点中被挡住的那只。
        let hit = actors
            .filter { $0.contains(location, inset: -14) }
            .min { $0.node.position.y < $1.node.position.y }

        if let hit {
            if hit.petID != selectedID {
                selectedID = hit.petID
                onPetSelected?(hit.petID)
            }
            strokePet(hit)
        } else if let a = selected, !isSleeping(a) {
            touchPoint = floor.clamp(location)
            a.applyWalkAnimation()
        }
    }

    /// 戳到宠物：抚摸反馈。
    ///
    /// 睡着时戳会把它叫醒 —— 必须先退出 .sleeping，
    /// 否则挤压动画的 `scale(to: pixelScale)` 会覆盖睡姿的压扁状态，
    /// 造成「状态是睡着、外观是站着」的不一致。
    private func strokePet(_ a: PetActor) {
        if isSleeping(a) {
            a.behavior = .idle
            a.nextDecisionAt = 0
            a.applyIdlePose()
            showEmote(.question)      // 被叫醒，一脸问号
        } else {
            showEmote(.heart)
        }
        onPetTouched?()

        let s0 = a.scale(atDepth: depth(of: a))
        a.node.removeAction(forKey: "squash")
        let squash = SKAction.sequence([
            .scaleX(to: s0 * 1.12, y: s0 * 0.88, duration: 0.08),
            .scale(to: s0, duration: 0.14)
        ])
        a.node.run(squash, withKey: "squash")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self) else { return }

        if let dragging = draggingNode {
            // **二维自由拖动，只要落在地板上。**
            // 曾经只能改 x，纵向得去改代码。
            let clamped = floor.clamp(location)
            dragging.position = CGPoint(x: min(size.width * 0.94,
                                               max(size.width * 0.06, clamped.x)),
                                        y: clamped.y)
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
            onFurnitureMoved?(id,
                              Double(node.position.x / size.width),
                              Double(floor.depth(atY: node.position.y)))
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
            guard let self, let data, !self.isStartled,
                  !self.actors.isEmpty else { return }
            let a = data.acceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            // 静止时约为 1g。超过 1.8 认为是明显摇晃。
            guard magnitude > 1.8 else { return }
            self.startleAll()
        }
    }

    /// 摇晃惊到**全部**宠物 —— 手机在抖，没道理只有一只感觉到。
    private func startleAll() {
        isStartled = true
        touchPoint = nil
        showEmote(.alert)

        let shake = SKAction.sequence([
            .moveBy(x: -6, y: 0, duration: 0.05),
            .moveBy(x: 12, y: 0, duration: 0.05),
            .moveBy(x: -6, y: 0, duration: 0.05)
        ])
        let group = DispatchGroup()
        for a in actors {
            a.behavior = .startled
            group.enter()
            a.node.run(.repeat(shake, count: 3)) { [weak a] in
                a?.behavior = .idle
                a?.nextDecisionAt = 0
                a?.applyIdlePose()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isStartled = false
        }
    }
}
