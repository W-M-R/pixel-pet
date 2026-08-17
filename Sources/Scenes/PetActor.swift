import SpriteKit

/// 场景里的一只宠物。
///
/// ## 为什么要这个类型
///
/// `PetScene` 曾经直接持有 `pet: SKSpriteNode!` 加十来个单宠状态
/// （`behavior` / `facing` / `exactPosition` / `nextDecisionAt` /
/// `colorIndex` / `breed` / `stage` / `shadow` / `foodNode`）。
/// 那时数据层也只有一只宠物，所以够用。
///
/// 现在可以同时养多只，这些状态必须**按宠物各持一份** ——
/// 否则两只共用一个 `behavior`，一只走路另一只就跟着走。
///
/// 所以把「一只宠物在场景里的全部表现」收进这个类：
/// 精灵节点、影子、食盆、朝向、行为状态机、位置累加。
/// `PetScene` 退化成「管一批 actor + 房间 + 输入分发」。
///
/// ## 不含什么
///
/// 房间、地板、家具、气泡层都是**场景级**的，不进这里 ——
/// 它们不随宠物数量增加。气泡层通过 `anchor` 闭包取当前选中那只的位置。
@MainActor
final class PetActor {

    /// 对应的存档 id。场景靠它把 actor 和 `PetState` 对上。
    let petID: String

    private(set) var breed: PetBreed
    private(set) var colorIndex: Int
    private(set) var stage: PetStage

    let node: SKSpriteNode
    let shadow: SKShapeNode
    private var foodNode: SKNode?

    /// 精确位置（未吸附）。
    ///
    /// ⚠️ 不能直接把吸附后的值写回 `node.position` 当累加基准：
    /// 120fps 下最远处每帧只走 0.22pt，小于 1 物理像素（0.33pt），
    /// 吸附会把位移抹成 0 —— 宠物原地不动。
    var exactPosition: CGPoint = .zero

    /// 宠物当前行为。和 `PetState` 的「需求」分开 ——
    /// 需求是数据，行为是表现。
    enum Behavior {
        case idle
        case wandering(target: CGPoint)
        case following
        case eating
        case startled
        case sleeping
    }
    var behavior: Behavior = .idle
    var facing: PetSpriteSheet.Facing = .right
    var nextDecisionAt: TimeInterval = 0

    /// 素材。派生 sheet 缺失时回退源图，保证不会白屏。
    private var sheet: SKTexture?
    private var sleepSheet: SKTexture?

    private let pixelScale: CGFloat
    private var sheetLayout: PetSheetLayout { breed.layout }

    init(petID: String,
         breed: PetBreed,
         colorIndex: Int,
         stage: PetStage,
         pixelScale: CGFloat) {
        self.petID = petID
        self.breed = breed
        self.colorIndex = colorIndex
        self.stage = stage
        self.pixelScale = pixelScale

        shadow = SKShapeNode(ellipseOf: CGSize(width: 44, height: 12))
        shadow.fillColor = SKColor(white: 0, alpha: 0.18)
        shadow.strokeColor = .clear
        shadow.zPosition = 9

        // ⚠️ 必须把纹理传给 init，不能先 `SKSpriteNode()` 再赋 `.texture` ——
        // 后者**不会同步 `size`**，节点停在 0×0，有纹理也画不出来
        // （屏幕上一只宠物都看不见，而位置、缩放、parent 全是对的，
        // 极难从表象反推）。
        let first: SKTexture? = {
            guard let sheet = PetSpriteSheet.loadSheet(named: breed.sheetName(for: stage))
                ?? PetSpriteSheet.loadSheet(named: breed.sheetName) else { return nil }
            return PetSpriteSheet.texture(from: sheet, row: 0, column: 0,
                                          colorIndex: colorIndex,
                                          layout: breed.layout)
        }()
        node = SKSpriteNode(texture: first)
        node.zPosition = 10
        node.texture?.filteringMode = .nearest

        loadSheets()
        applyDepthScale(depth: 0)
    }

    /// 加进场景。影子和精灵是两个兄弟节点（影子要在家具之下）。
    func attach(to scene: SKScene) {
        scene.addChild(shadow)
        scene.addChild(node)
    }

    func removeFromScene() {
        shadow.removeFromParent()
        node.removeFromParent()
        foodNode?.removeFromParent()
        foodNode = nil
    }

    // MARK: - 外观

    /// 换品种/毛色/阶段。返回是否真的变了（没变就别重新贴图）。
    @discardableResult
    func updateAppearance(breed: PetBreed, colorIndex: Int, stage: PetStage) -> Bool {
        let changed = breed.id != self.breed.id
            || colorIndex != self.colorIndex
            || stage != self.stage
        guard changed else { return false }
        self.breed = breed
        self.colorIndex = colorIndex
        self.stage = stage
        loadSheets()
        return true
    }

    private func loadSheets() {
        // 成年用源图，其余阶段用 tools/make_stages.py 生成的派生 sheet。
        // 派生缺失时回退源图 —— 宁可体型不对也不要白屏。
        let name = breed.sheetName(for: stage)
        sheet = PetSpriteSheet.loadSheet(named: name)
            ?? PetSpriteSheet.loadSheet(named: breed.sheetName)
        sleepSheet = PetSpriteSheet.loadSheet(named: breed.sleepSheetName)
    }

    // MARK: - 几何

    /// 「1 源像素在屏幕上占多少 pt」。
    ///
    /// ⚠️ 纹理已预放大 `prescale` 倍，`node.yScale` 相应变小了同样倍数，
    /// 所以要乘回来。
    var sourcePixelUnit: CGFloat {
        node.yScale * CGFloat(PetSpriteSheet.prescale)
    }

    /// 脚底的 y。
    ///
    /// 不能直接用 `node.position.y`（那是节点中心），也不能硬编码偏移 ——
    /// 不同品种的轮廓不同，`footPadding` 是 per-breed 实测值。
    var feetY: CGFloat {
        node.position.y - (sheetLayout.cell / 2 - sheetLayout.footPadding) * sourcePixelUnit
    }

    func scale(atDepth depth: CGFloat) -> CGFloat {
        let perspective = 1 - depth * 0.25
        return pixelScale * stage.bodyScale * perspective
            / CGFloat(PetSpriteSheet.prescale)
    }

    func applyDepthScale(depth: CGFloat) {
        node.setScale(scale(atDepth: depth))
    }

    func syncShadow(depth: CGFloat, footInset: CGFloat) {
        shadow.position = CGPoint(x: node.position.x,
                                  y: feetY - pixelScale * footInset)
        let s = 1 - depth * 0.25
        shadow.setScale(s * stage.bodyScale)
    }

    // MARK: - 动画

    func applyWalkAnimation() {
        guard let sheet else { return }
        let frames = PetSpriteSheet.frames(from: sheet,
                                          action: .walk(facing),
                                          colorIndex: colorIndex,
                                          layout: sheetLayout)
        guard !frames.isEmpty else { return }
        node.removeAction(forKey: "anim")
        let anim = SKAction.animate(with: frames,
                                    timePerFrame: PetSpriteSheet.Action.walk(facing).timePerFrame,
                                    resize: false, restore: false)
        node.run(.repeatForever(anim), withKey: "anim")
    }

    func applyIdlePose() {
        guard let sheet else { return }
        node.removeAction(forKey: "anim")
        // ⚠️ cat 的 r1/r2 第 4 格是空白，所以正/背向时回退到走路第 0 帧。
        // 没有专门坐姿列的布局（idleColumn == nil）同样回退。
        let sideways = (facing == .right || facing == .left)
        let column = (sideways ? sheetLayout.idleColumn : nil) ?? 0
        node.texture = PetSpriteSheet.texture(from: sheet,
                                              row: facing.row(in: sheetLayout),
                                              column: column,
                                              colorIndex: colorIndex,
                                              layout: sheetLayout)
        node.texture?.filteringMode = .nearest
    }

    func applyEatAnimation(then completion: @escaping () -> Void) {
        guard let sheet else { completion(); return }
        let frames = PetSpriteSheet.frames(from: sheet, action: .eat,
                                           colorIndex: colorIndex,
                                           layout: sheetLayout)
        guard !frames.isEmpty else { completion(); return }
        node.removeAction(forKey: "anim")
        let chew = SKAction.animate(with: frames,
                                    timePerFrame: PetSpriteSheet.Action.eat.timePerFrame,
                                    resize: false, restore: false)
        node.run(.sequence([.repeat(chew, count: 4),
                            .run(completion)]), withKey: "anim")
    }

    /// 睡姿。独立 sheet；缺失时回退「压扁 + 呼吸缩放」。
    func applySleepPose(depth: CGFloat) {
        node.removeAction(forKey: "anim")
        applyDepthScale(depth: depth)

        let frames = sleepSheet.map {
            PetSpriteSheet.sleepFrames(from: $0, colorIndex: colorIndex,
                                       layout: sheetLayout)
        } ?? []

        if frames.count >= 2 {
            node.texture = frames[0]
            node.texture?.filteringMode = .nearest
            let breathe = SKAction.animate(with: frames, timePerFrame: 1.1,
                                           resize: false, restore: false)
            node.run(.repeatForever(breathe), withKey: "anim")
        } else if let sheet {
            node.texture = PetSpriteSheet.texture(
                from: sheet,
                row: PetSpriteSheet.Facing.right.row(in: sheetLayout),
                column: 0,
                colorIndex: colorIndex,
                layout: sheetLayout)
            node.texture?.filteringMode = .nearest
            let s0 = scale(atDepth: depth)
            node.yScale = s0 * 0.82
            node.xScale = s0 * 1.04
            let inhale = SKAction.group([
                .scaleY(to: s0 * 0.86, duration: 1.4),
                .scaleX(to: s0 * 1.02, duration: 1.4)])
            let exhale = SKAction.group([
                .scaleY(to: s0 * 0.82, duration: 1.4),
                .scaleX(to: s0 * 1.04, duration: 1.4)])
            inhale.timingMode = .easeInEaseOut
            exhale.timingMode = .easeInEaseOut
            node.run(.repeatForever(.sequence([inhale, exhale])), withKey: "anim")
        }
    }

    /// 按当前行为重新贴图。
    ///
    /// 换毛色/品种/阶段后必须调它，而且**不能一律播走路动画** ——
    /// 站着不动时（`.idle`，也是大多数时候）走路动画会被 idle 单帧盖掉，
    /// 而 `update` 的 `.idle` 分支不重设贴图，结果画面纹丝不动，
    /// 看起来像「换了没生效」。
    func reapplyCurrentPose(depth: CGFloat) {
        switch behavior {
        case .sleeping:
            applySleepPose(depth: depth)
        case .idle, .startled:
            applyIdlePose()
        case .wandering, .following:
            applyWalkAnimation()
        case .eating:
            // 咀嚼有完成回调驱动状态退出，中途换帧会打断它。
            break
        }
    }

    // MARK: - 食盆

    /// 食盆由场景手绘（要用房间调色板），actor 只负责持有与清理。
    func setFoodBowl(_ node: SKNode) { foodNode = node }

    /// 立刻移除，不做淡出 —— 换盆时用
    func clearFoodBowlImmediately() {
        foodNode?.removeFromParent()
        foodNode = nil
    }

    /// 吃完后淡出移除
    func clearFoodBowl() {
        foodNode?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        foodNode = nil
    }

    /// 命中测试。inset 收一点，避免透明边也算点中。
    func contains(_ point: CGPoint, inset: CGFloat = 14) -> Bool {
        node.frame.insetBy(dx: inset, dy: inset).contains(point)
    }
}
