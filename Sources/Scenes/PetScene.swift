import SpriteKit
import CoreMotion

/// 宠物主场景。
///
/// 差异化在这里：宠物会被戳到、会追手指、会响应摇晃。
/// 挂件类竞品（Pixel Pals 那种走 WidgetKit 时间线的）做不到真实互动，
/// 这是 SpriteKit 全屏场景的天然优势。
final class PetScene: SKScene {

    // MARK: - 配置

    /// 整数倍缩放，保证像素边界对齐。32×32 × 5 = 160pt
    private let pixelScale: CGFloat = 5
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

    /// 地面高度（场景底部往上留一点，宠物在这条线上活动）
    private var groundY: CGFloat { size.height * 0.28 }

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
        let scale = pixelScale * 0.8
        for slot in layout.slots {
            guard let item = RoomSpriteSheet.Furniture(rawValue: slot.id) else { continue }
            let node = SKSpriteNode(texture: RoomSpriteSheet.furnitureTexture(from: roomSheet, item))
            node.texture?.filteringMode = .nearest
            node.setScale(scale * slot.scaleMul)
            node.position = CGPoint(x: size.width * slot.xRatio, y: groundY + slot.yOffset)
            node.zPosition = slot.z
            node.name = slot.id
            addChild(node)
            furnitureNodes.append(node)
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
        shadow.zPosition = 1
        addChild(shadow)

        let firstFrame = sheet.map {
            PetSpriteSheet.texture(from: $0, row: 0, column: 0, colorIndex: colorIndex)
        }
        pet = SKSpriteNode(texture: firstFrame)
        pet.texture?.filteringMode = .nearest
        pet.setScale(pixelScale)
        pet.position = CGPoint(x: size.width / 2, y: groundY)
        pet.zPosition = 2
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
        let scale = pixelScale * 0.8   // 家具比宠物略小一点，避免抢主角

        for slot in layout.slots {
            guard let item = RoomSpriteSheet.Furniture(rawValue: slot.id) else { continue }
            let tex = RoomSpriteSheet.furnitureTexture(from: roomSheet, item)
            let node = SKSpriteNode(texture: tex)
            node.texture?.filteringMode = .nearest
            node.setScale(scale * slot.scaleMul)
            node.position = CGPoint(x: size.width * slot.xRatio,
                                    y: groundY + slot.yOffset)
            node.zPosition = slot.z
            node.name = slot.id
            addChild(node)
            furnitureNodes.append(node)
        }
    }

    /// 墙 + 地板 + 踢脚线。用纯色块，因为 Home Objects 包里没有墙纸/地板 tile。
    /// 放在场景里而不是 SwiftUI 层，这样家具和地面的相对位置只有一处真相。
    private func buildFloor() {
        let floorH = groundY + 6

        let wall = SKSpriteNode(color: SKColor(red: 0.30, green: 0.33, blue: 0.46, alpha: 1),
                                size: CGSize(width: size.width, height: size.height - floorH))
        wall.anchorPoint = CGPoint(x: 0, y: 0)
        wall.position = CGPoint(x: 0, y: floorH)
        wall.zPosition = -2
        addChild(wall)

        let floor = SKSpriteNode(color: SKColor(red: 0.45, green: 0.34, blue: 0.27, alpha: 1),
                                 size: CGSize(width: size.width, height: floorH))
        floor.anchorPoint = CGPoint(x: 0, y: 0)
        floor.position = .zero
        floor.zPosition = -2
        addChild(floor)

        // 踢脚线：一条深色窄带，把墙和地分开
        let skirting = SKSpriteNode(color: SKColor(red: 0.24, green: 0.19, blue: 0.16, alpha: 1),
                                    size: CGSize(width: size.width, height: 4))
        skirting.anchorPoint = CGPoint(x: 0, y: 0)
        skirting.position = CGPoint(x: 0, y: floorH - 2)
        skirting.zPosition = -1
        addChild(skirting)

        // 地板缝，给地面一点纵深
        var y: CGFloat = floorH - 18
        while y > 0 {
            let line = SKSpriteNode(color: SKColor(white: 0, alpha: 0.07),
                                    size: CGSize(width: size.width, height: 2))
            line.anchorPoint = CGPoint(x: 0, y: 0)
            line.position = CGPoint(x: 0, y: y)
            line.zPosition = -1
            addChild(line)
            y -= 18
        }
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
        shadow.position = CGPoint(x: pet.position.x, y: pet.position.y - 22)
    }

    // MARK: - 外部触发

    func triggerEat() {
        behavior = .eating
        touchPoint = nil
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

    /// 喂食时在宠物脚边放一个食盆。
    /// Home Objects 包里没有食盆，所以用像素矩形手绘一个 —— 12×6 的盆
    /// 加几块食物色块，保持和 32×32 素材相同的像素密度。
    private func dropFoodBowl() {
        foodNode?.removeFromParent()

        let unit = pixelScale          // 1 源像素 = pixelScale pt
        let container = SKNode()

        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: SKColor) {
            let n = SKSpriteNode(color: color, size: CGSize(width: w * unit, height: h * unit))
            n.anchorPoint = CGPoint(x: 0, y: 0)
            n.position = CGPoint(x: x * unit, y: y * unit)
            container.addChild(n)
        }

        let bowlDark = SKColor(red: 0.42, green: 0.26, blue: 0.20, alpha: 1)
        let bowlLite = SKColor(red: 0.58, green: 0.38, blue: 0.28, alpha: 1)
        let kibble   = SKColor(red: 0.80, green: 0.58, blue: 0.30, alpha: 1)

        // 盆身
        block(0, 0, 12, 2, bowlDark)
        block(-1, 2, 14, 2, bowlLite)
        // 食物
        block(2, 4, 3, 2, kibble)
        block(6, 4, 4, 2, kibble)
        block(4, 6, 3, 1, kibble)

        let side: CGFloat = facing == .right ? 22 : -34
        container.position = CGPoint(x: pet.position.x + side, y: pet.position.y - 24)
        container.zPosition = 3
        container.alpha = 0
        addChild(container)
        container.run(.fadeIn(withDuration: 0.15))
        foodNode = container
    }

    func triggerPlay() {
        showEmote(.music)
        // 蹦两下。像素风里跳跃用位移就够，不需要物理引擎。
        let up = SKAction.moveBy(x: 0, y: 26, duration: 0.16)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: 0, y: -26, duration: 0.16)
        down.timingMode = .easeIn
        pet.run(.repeat(.sequence([up, down]), count: 2))
    }

    func triggerClean() {
        showEmote(.droplet)
        let fade = SKAction.sequence([
            .fadeAlpha(to: 0.55, duration: 0.18),
            .fadeAlpha(to: 1, duration: 0.18)
        ])
        pet.run(.repeat(fade, count: 2))
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

        node.position = CGPoint(x: pet.position.x, y: pet.position.y + 60)
        node.zPosition = 5
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
            // 直接戳到宠物 → 抚摸反馈
            onPetTouched?()
            showEmote(.heart)
            let squash = SKAction.sequence([
                .scaleX(to: pixelScale * 1.1, y: pixelScale * 0.9, duration: 0.08),
                .scale(to: pixelScale, duration: 0.12)
            ])
            pet.run(squash)
        } else {
            touchPoint = CGPoint(x: location.x, y: groundY)
            applyWalkAnimation()
        }
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
