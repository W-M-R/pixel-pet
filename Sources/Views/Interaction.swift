import SwiftUI

/// 一个互动按钮的 UI 配置。
///
/// **和 `InteractionEffect` 的分工**：
/// - `InteractionEffect`（Models 层）—— 改哪个时间戳、涨哪个计数、触发哪类台词
/// - `Interaction`（这里，Views 层）—— 按钮什么图标、什么文案、台词延迟多久
///
/// 原来两者合在 `Models/Interaction.swift`，导致 Models 依赖 Views
/// 和 Scenes（`PixelIcon`、`Pixel.RGB`、`PetSpriteSheet`），
/// 形成模块级循环。见 docs/06-architecture.md 的分层规则。
struct Interaction: Identifiable {

    /// 互动动画的时长常量。
    ///
    /// **放在 Views 层的原因**：它服务于「什么时候说台词」这个 UI 时序，
    /// 而且依赖 `PetSpriteSheet`（Scenes）。Models 不该知道动画多长。
    ///
    /// **为什么要集中**：说台词的延迟必须和动画时长对得上，但两者原来
    /// 分别写在 `PetHomeView`（0.7/0.8/1.6）和 `PetScene`（各自的 SKAction）里，
    /// 是跨文件的隐式依赖。实测发现喂食那条已经对不上：
    /// 咀嚼是 4 帧 × 0.22s × 重复 4 轮 = **3.52s**，而延迟写的是 1.6s ——
    /// 台词在动画演到一半就冒出来了。
    enum Duration {
        /// 咀嚼：4 帧 × 0.22s × 4 轮
        static let eat: TimeInterval =
            PetSpriteSheet.Action.eat.timePerFrame * 4 * 4
        /// 蹦跳：上下各 0.16s，重复 2 次
        static let hop: TimeInterval = 0.16 * 2 * 2
        /// 洗澡闪烁：两轮各 0.18s×2
        static let splash: TimeInterval = 0.18 * 2 * 2

        /// 说台词的延迟。
        ///
        /// **不用「动画时长 × 系数」的公式** —— 试过 60%，算出蹦跳 0.38s、
        /// 洗澡 0.43s，比原来手调的 0.7/0.8 更急，观感变差。
        /// 这些值是按「动作演到哪一拍最适合插话」调出来的，
        /// 和动画总长不成固定比例。
        ///
        /// 所以这里只做一件事：**保留手调值，但把它们和动画时长放在一起**，
        /// 改动画时能看到该同步检查延迟。
        static let sayAfterHop: TimeInterval = 0.7
        static let sayAfterSplash: TimeInterval = 0.8
        /// ⚠️ 原来是 1.6s，但咀嚼实际 3.52s —— 台词在动画演到一半就冒出来。
        /// 改成 2.2s：不必等全部演完（那样显得迟钝），但要过咀嚼的主要动作。
        static let sayAfterEat: TimeInterval = 2.2
    }

    /// 底层作用。id 和 trigger 都从它取，避免两处定义漂移。
    let effect: InteractionEffect
    /// 按钮文案的本地化 key
    let titleKey: String
    /// 按钮图标
    let icon: PixelIcon
    /// 台词延迟（秒）。要等动画演到合适的节点再说话。
    let sayDelay: TimeInterval

    var id: String { effect.id }
    var trigger: PetLineContext.Trigger { effect.trigger }

    // MARK: - 注册表

    static let all: [Interaction] = [play, clean]

    static let play = Interaction(
        effect: .play,
        titleKey: "action.play",
        icon: .ball,
        sayDelay: Duration.sayAfterHop)

    static let clean = Interaction(
        effect: .clean,
        titleKey: "action.clean",
        icon: .bath,
        sayDelay: Duration.sayAfterSplash)
}

/// 状态维度的展示信息。
///
/// 原来 `statusBar` 里三个 `StatBar` 是手写展开的，加维度要改 UI；
/// 现在改成遍历这张表。
///
/// **在 Views 层**：`tint` 是 `Pixel.RGB`，纯展示属性。
struct StatDimension: Identifiable {
    let id: String
    let labelKey: String
    let tint: Pixel.RGB
    /// 从状态里取当前值
    let value: (PetState, Date) -> Double

    static let all: [StatDimension] = [
        .init(id: "satiety", labelKey: "stat.satiety", tint: Pixel.satiety,
              value: { $0.satiety(at: $1) }),
        .init(id: "mood", labelKey: "stat.mood", tint: Pixel.mood,
              value: { $0.mood(at: $1) }),
        .init(id: "hygiene", labelKey: "stat.hygiene", tint: Pixel.hygiene,
              value: { $0.hygiene(at: $1) }),
    ]
}
