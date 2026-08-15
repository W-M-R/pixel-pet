import SwiftUI

/// 一种主动互动。
///
/// **建这层的原因**：加一个互动（比如「梳毛」）原本要改 22 个编辑点、
/// 跨 10 个文件 —— 状态字段、Codable、计数、衰减周期、派生数值、
/// 需求枚举、Store 方法、台词分类、AI prompt、场景动画、emote 映射、
/// UI 图标、按钮、状态条、颜色、统计页、成就、通知、本地化。
///
/// 这张表把其中**纯数据的那部分**收在一处：按钮长什么样、点了改哪个
/// 时间戳、涨哪个计数、对应哪条台词。剩下的（动画、成就、通知）
/// 仍然各自实现，因为它们不是数据。
///
/// ⚠️ **刻意不做的事**：没有 `InteractionHandler` 协议、没有注册中心。
/// 现在只有 3 个互动，抽象的目的是**消除重复**而不是搭框架 ——
/// 引入协议会让「洗澡时宠物做什么」需要在协议、实现、注册表之间
/// 跳转才能看懂，而现在 `PetScene.triggerClean` 13 行一眼就懂。
struct Interaction: Identifiable {

    /// 互动动画的时长常量。
    ///
    /// **为什么要集中**：说台词的延迟必须和动画时长对得上，但两者原来
    /// 分别写在 `PetHomeView`（0.7/0.8/1.6）和 `PetScene`（各自的 SKAction）里，
    /// 跨文件的隐式依赖。实测发现喂食那条已经对不上：
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

    let id: String
    /// 按钮文案的本地化 key
    let titleKey: String
    /// 按钮图标
    let icon: PixelIcon
    /// 触发哪类台词
    let trigger: PetLineContext.Trigger
    /// 台词延迟（秒）。要等动画演到合适的节点再说话。
    let sayDelay: TimeInterval
    /// 应用到状态上：改时间戳 + 涨计数。
    ///
    /// 用闭包而非协议 —— 三个实现都是 2 行，协议的间接性不划算。
    let apply: (inout PetState, Date) -> Void

    // MARK: - 注册表

    /// 喂食单独处理，不在这张表里 —— 它要先弹选择器、按量计价、扣钱、
    /// 设 buff、记 foodCounts，和另两个「一键归满」不是同一种东西。
    static let all: [Interaction] = [play, clean]

    static let play = Interaction(
        id: "play",
        titleKey: "action.play",
        icon: .ball,
        trigger: .stroked,
        sayDelay: Duration.sayAfterHop,
        apply: { pet, now in
            pet.lastPlayedAt = now
            pet.totalPlayCount = (pet.totalPlayCount ?? 0) + 1
        })

    static let clean = Interaction(
        id: "clean",
        titleKey: "action.clean",
        icon: .bath,
        trigger: .cleaned,
        sayDelay: Duration.sayAfterSplash,
        apply: { pet, now in
            pet.lastCleanedAt = now
            pet.totalCleanCount = (pet.totalCleanCount ?? 0) + 1
        })
}

/// 状态维度的展示信息。
///
/// 原来 `statusBar` 里三个 `StatBar` 是手写展开的，加维度要改 UI；
/// 现在改成遍历这张表。
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
