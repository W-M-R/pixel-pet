import Foundation

/// 一次互动对状态的**作用**。纯数据，不含任何 UI。
///
/// **为什么和 `Interaction` 分开**：原来两者是一个结构体，
/// 里面既有 `apply`（改时间戳）也有 `icon: PixelIcon`（UI）——
/// 导致 `Models` 层依赖 `Views` 和 `Scenes`，形成模块级循环：
///
/// ```
/// Models/Interaction ──► Views/PixelIcon ──► Models/PetNeed
/// Models/Interaction ──► Scenes/PetSpriteSheet
/// ```
///
/// 现在按「谁需要它」切开：
/// - `PetStore` 只需要 `apply` 和 `id` → 用这个
/// - 按钮需要图标和文案 → 用 `Interaction`（在 Views 层）
///
/// ⚠️ **刻意不做协议**。只有 2 个互动，抽象的目的是消除重复而不是搭框架。
/// 引入 `InteractionHandler` 协议会让「洗澡时宠物做什么」需要在协议、
/// 实现、注册表之间跳转才能看懂，而现在 `PetScene.triggerClean` 13 行一眼就懂。
struct InteractionEffect: Identifiable {

    let id: String
    /// 触发哪类台词
    let trigger: PetLineContext.Trigger
    /// 应用到状态上：改时间戳 + 涨计数。
    ///
    /// 用闭包而非协议 —— 两个实现都是 2 行，协议的间接性不划算。
    let apply: (inout PetState, Date) -> Void

    // MARK: - 注册表

    /// 喂食不在这张表里 —— 它要先弹选择器、按量计价、扣钱、设 buff、
    /// 记 foodCounts，和另两个「一键归满」不是同一种东西。
    static let all: [InteractionEffect] = [play, clean]

    static let play = InteractionEffect(
        id: "play",
        trigger: .stroked,
        apply: { pet, now in
            pet.lastPlayedAt = now
            pet.totalPlayCount = (pet.totalPlayCount ?? 0) + 1
        })

    static let clean = InteractionEffect(
        id: "clean",
        trigger: .cleaned,
        apply: { pet, now in
            pet.lastCleanedAt = now
            pet.totalCleanCount = (pet.totalCleanCount ?? 0) + 1
        })

    static func byID(_ id: String) -> InteractionEffect? {
        all.first { $0.id == id }
    }
}
