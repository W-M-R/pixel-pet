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
    private var pet: SKSpriteNode!
    private var shadow: SKShapeNode!
    private var bubble: SKLabelNode?

    private var colorIndex: Int = 0
    private var species: PetSpecies = .cat

    /// 宠物当前行为。和 PetState 的「需求」分开——需求是数据，行为是表现。
    private enum Behavior {
        case idle
        case wandering(target: CGPoint)
        case following
        case eating
        case startled
    }
    private var behavior: Behavior = .idle
    private var facing: PetSpriteSheet.Facing = .right
    private var nextDecisionAt: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0

    private var touchPoint: CGPoint?
    private let motion = CMMotionManager()

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

    func configure(species: PetSpecies, colorIndex: Int) {
        guard species != self.species || colorIndex != self.colorIndex || pet == nil else { return }
        self.species = species
        self.colorIndex = colorIndex
        sheet = PetSpriteSheet.loadSheet(named: species.sheetName)
        if pet != nil { applyWalkAnimation() }
    }

    private func buildScene() {
        removeAllChildren()
        guard size.width > 1 else { return }

        sheet = PetSpriteSheet.loadSheet(named: species.sheetName)

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
        if pet == nil { buildScene() }
        else {
            pet.position.y = groundY
            syncShadow()
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
    }

    // MARK: - 行为驱动

    override func update(_ currentTime: TimeInterval) {
        guard pet != nil else { return }
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime

        if let touchPoint {
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
            case .eating, .startled:
                break
            }
        }
        syncShadow()
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
        showBubble("🍖")
        applyEatAnimation { [weak self] in
            guard let self else { return }
            self.behavior = .idle
            self.nextDecisionAt = 0
            self.applyIdlePose()
        }
    }

    func triggerPlay() {
        showBubble("🎾")
        // 蹦两下。像素风里跳跃用位移就够，不需要物理引擎。
        let up = SKAction.moveBy(x: 0, y: 26, duration: 0.16)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: 0, y: -26, duration: 0.16)
        down.timingMode = .easeIn
        pet.run(.repeat(.sequence([up, down]), count: 2))
    }

    func triggerClean() {
        showBubble("🛁")
        let fade = SKAction.sequence([
            .fadeAlpha(to: 0.55, duration: 0.18),
            .fadeAlpha(to: 1, duration: 0.18)
        ])
        pet.run(.repeat(fade, count: 2))
    }

    func showNeedBubble(_ need: PetNeed) {
        guard need != .content else { return }
        showBubble(need.emoji)
    }

    private func showBubble(_ text: String) {
        bubble?.removeFromParent()
        let label = SKLabelNode(text: text)
        label.fontSize = 26
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: pet.position.x, y: pet.position.y + 62)
        label.zPosition = 5
        label.alpha = 0
        addChild(label)
        bubble = label

        label.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .moveBy(x: 0, y: 14, duration: 0.15)]),
            .wait(forDuration: 1.0),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 10, duration: 0.3)]),
            .removeFromParent()
        ]))
    }

    // MARK: - 触摸

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self), pet != nil else { return }
        if pet.frame.insetBy(dx: -14, dy: -14).contains(location) {
            // 直接戳到宠物 → 抚摸反馈
            onPetTouched?()
            showBubble("💗")
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
        touchPoint = CGPoint(x: location.x, y: groundY)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchPoint = nil
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
        showBubble("❗")
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
