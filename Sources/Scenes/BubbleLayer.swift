import SpriteKit

/// 气泡层：台词对话框、像素 emote 图标、emoji 回退。
///
/// **从 PetScene 抽出来的原因**：这是场景里最大的单一职责（163 行），
/// 而它对外界的依赖只有一个 —— 「气泡该挂在哪」。
/// 用一个 `anchor` 闭包表达这个依赖，就和宠物完全解耦了。
///
/// 外部只需三个方法：`speak(_:)` / `emote(_:)` / `sync()`。
///
/// 三种气泡样式刻意保留差异：
/// - 台词用像素直角框（有边框和台阶尾巴）—— 它承载最多信息，值得完整样式
/// - emote 用无框像素图标 —— 瞬时情绪，轻量
/// - emoji 是 emote 切图失败时的回退 —— emotes.png 的网格是反推出来的，
///   万一某格坐标不对，不能让气泡直接消失
@MainActor
final class BubbleLayer {

    /// 挂载到哪
    private weak var parent: SKNode?
    /// 1 源像素 = 多少 pt
    private let unit: CGFloat
    /// emote 图标 sheet
    private let emoteSheet: SKTexture?
    /// 自绘 UI 图标 sheet。emotes 那套没有食物/球/浴缸这类具体道具。
    private let iconSheet: SKTexture?

    /// 气泡锚点（通常是宠物脚底），每帧重新取。
    ///
    /// 用闭包而非直接持有宠物节点 —— 这样 BubbleLayer 不需要知道
    /// 宠物是什么、有没有换过、当前缩放多少。
    private let anchor: () -> CGPoint
    /// 场景宽度，用于边界钳制
    private let sceneWidth: () -> CGFloat

    private var node: SKNode?
    private var yOffset: CGFloat = 0
    private var halfWidth: CGFloat = 0

    /// 台词气泡的默认停留时长
    static let defaultSpeechDuration: TimeInterval = 6.0

    init(parent: SKNode,
         unit: CGFloat,
         emoteSheet: SKTexture?,
         iconSheet: SKTexture? = nil,
         anchor: @escaping () -> CGPoint,
         sceneWidth: @escaping () -> CGFloat) {
        self.parent = parent
        self.unit = unit
        self.emoteSheet = emoteSheet
        self.iconSheet = iconSheet
        self.anchor = anchor
        self.sceneWidth = sceneWidth
    }

    // MARK: - 对外接口

    /// 台词气泡：像素风的白底黑边对话框 + 小尾巴。
    ///
    /// 用多行文本而不是单行 —— 台词可能十几个字，单行会超出屏幕。
    /// 尺寸取 unit 整数倍，和其余像素元素保持同密度。
    func speak(_ text: String, duration: TimeInterval = defaultSpeechDuration) {
        guard let parent, !text.isEmpty else { return }
        node?.removeFromParent()

        let u = unit
        let maxWidth = sceneWidth() * 0.62

        let label = SKLabelNode(text: text)
        label.fontName = Self.fontName
        label.fontSize = Self.fontSize
        label.fontColor = RoomPalette.speechText.sk
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = maxWidth - u * 6
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center

        let textSize = label.calculateAccumulatedFrame().size
        let boxW = min(maxWidth, max(u * 20, textSize.width + u * 6))
        let boxH = max(u * 10, textSize.height + u * 5)

        let container = SKNode()

        // 外边框（深色）
        let border = SKSpriteNode(color: RoomPalette.speechBorder.sk,
                                  size: CGSize(width: boxW + u * 2,
                                               height: boxH + u * 2))
        border.position = .zero
        container.addChild(border)

        // 内底（浅色）
        let fill = SKSpriteNode(color: RoomPalette.speechFill.sk,
                                size: CGSize(width: boxW, height: boxH))
        fill.position = .zero
        container.addChild(fill)

        label.position = .zero
        label.zPosition = 1
        container.addChild(label)

        // 尾巴：两级台阶指向宠物
        for (i, w) in [3, 1].enumerated() {
            let step = SKSpriteNode(color: RoomPalette.speechFill.sk,
                                    size: CGSize(width: u * CGFloat(w), height: u))
            step.position = CGPoint(x: 0, y: -boxH / 2 - u * CGFloat(i) - u / 2)
            container.addChild(step)
            let edge = SKSpriteNode(color: RoomPalette.speechBorder.sk,
                                    size: CGSize(width: u * CGFloat(w) + u * 2,
                                                 height: u))
            edge.position = CGPoint(x: 0, y: step.position.y - u * 0.5)
            edge.zPosition = -1
            container.addChild(edge)
        }

        yOffset = u * 26 + boxH / 2
        halfWidth = boxW / 2 + u * 3
        present(container, hold: duration, fadeIn: 0.14, fadeOut: 0.28,
                scaleIn: true)
    }

    /// 像素 emote 图标。切图失败回退 emoji。
    func emote(_ emote: RoomSpriteSheet.Emote) {
        // 取不到就什么都不显示。**不回退 emoji** ——
        // emoji 字形随 iOS 版本变、缺字体时是问号，
        // 而且渐变高光会把像素观感压掉。宁可没气泡。
        guard let emoteSheet,
              let tex = RoomSpriteSheet.emoteTexture(from: emoteSheet, emote)
        else { return }
        let sprite = SKSpriteNode(texture: tex)
        sprite.texture?.filteringMode = .nearest
        sprite.setScale(unit * 0.9)
        // 头顶 = 脚底 + 内容高度(19 源像素)，再留 4 像素间隙
        yOffset = unit * 23
        halfWidth = unit * 5
        present(sprite, hold: 1.1, fadeIn: 0.15, fadeOut: 0.3, scaleIn: false)
    }

    /// 自绘像素图标气泡。
    ///
    /// `index` 是 `Assets/ui/icons.png` 里的格位，与 Views 层 `PixelIcon`
    /// 的 case 顺序一致（都源自 make_ui_icons.py 的 ORDER）。
    /// 取不到就什么都不显示 —— **不回退 emoji**，宁可没有也不要
    /// 一个渐变高光的 emoji 破坏像素观感，更不要问号。
    func uiIcon(_ index: Int) {
        guard let iconSheet,
              let tex = RoomSpriteSheet.uiIconTexture(from: iconSheet, index: index)
        else { return }
        let sprite = SKSpriteNode(texture: tex)
        sprite.texture?.filteringMode = .nearest
        sprite.setScale(unit * 0.9)
        yOffset = unit * 23
        halfWidth = unit * 5
        present(sprite, hold: 1.1, fadeIn: 0.15, fadeOut: 0.3, scaleIn: false)
    }


    /// 宠物需求气泡。
    ///
    /// ⚠️ 目前**没有调用方** —— 需求只在 HUD 用图标显示，
    /// 宠物头上不会自发冒需求气泡。留着是因为接上它的成本极低
    /// （在 update 里按 dominantNeed 定时触发即可），是个明确的待办。
    func need(_ need: PetNeed) {
        guard need != .content else { return }
        if let e = need.emote {
            emote(e)
        } else {
            // emotes 那套没有食物图标，用自绘的 icons.png。
            // 索引与 Views 层 PixelIcon 的 case 顺序一致。
            uiIcon(need.iconIndex)
        }
    }

    /// 让气泡跟着锚点走。**每帧调用。**
    ///
    /// 之前气泡位置在创建时固定，宠物走开后气泡留在原地。
    /// 现在每帧重算，并做屏幕边界钳制，避免气泡跑出画面。
    func sync() {
        guard let node, node.parent != nil else { return }
        let halfW = max(halfWidth, unit * 4)
        let base = anchor()
        let x = min(sceneWidth() - halfW, max(halfW, base.x))
        node.position = CGPoint(x: x, y: base.y + yOffset)
    }

    /// 立即移除当前气泡
    func clear() {
        node?.removeFromParent()
        node = nil
    }

    // MARK: - 内部

    /// 字体。
    ///
    /// ⚠️ 用 Menlo 而 HUD 用 SF Mono，是「两种等宽字体」的不一致。
    /// 统一到一种需要先确认 SKLabelNode 对 systemFont 的 monospaced
    /// 变体支持情况，留作待办。
    private static let fontName = "Menlo-Bold"
    private static let fontSize: CGFloat = 13

    /// 统一的进场/停留/退场。
    ///
    /// 淡出**不能**用 moveBy —— 每帧的 `sync()` 会覆盖位移，
    /// 两者打架会让气泡抖动。只做淡出和缩放。
    private func present(_ n: SKNode,
                         hold: TimeInterval,
                         fadeIn: TimeInterval,
                         fadeOut: TimeInterval,
                         scaleIn: Bool) {
        guard let parent else { return }
        node?.removeFromParent()

        n.zPosition = 20
        n.alpha = 0
        if scaleIn { n.setScale(0.85) }
        parent.addChild(n)
        node = n
        sync()

        let enter: SKAction = scaleIn
            ? .group([.fadeIn(withDuration: fadeIn),
                      .scale(to: 1, duration: fadeIn + 0.02)])
            : .fadeIn(withDuration: fadeIn)
        let exit: SKAction = scaleIn
            ? .group([.fadeOut(withDuration: fadeOut),
                      .scale(to: 0.94, duration: fadeOut)])
            : .fadeOut(withDuration: fadeOut)

        n.run(.sequence([enter, .wait(forDuration: hold), exit, .removeFromParent()]))
    }
}
