import Foundation

/// 无障碍标识常量。
///
/// ## 为什么需要这个
///
/// 主页状态栏那五个入口（金币/成就/商店/宠物/设置）是**纯图标按钮**，
/// 没有文字。实测 `maestro hierarchy` 里它们的 `accessibilityText`
/// 全是空字符串 —— 意思是：
///
/// 1. **VoiceOver 用户听不出这些按钮是什么**，只会读到「按钮」
/// 2. UI 测试定位不到它们，只能用屏幕坐标点，换机型就失效
///
/// 第 1 条本身就是该修的无障碍缺陷，不只是为了测试方便。
///
/// ## 为什么放在 Core
///
/// 这里只有字符串常量，不碰任何业务类型，符合
/// `check_layers.sh` 对 Core 的约束（Core 不得引用业务类型）。
/// UI 测试 target 也要引用同一份常量 —— 两边各抄一份字符串
/// 是最容易腐烂的做法，改一处忘一处，测试会以「找不到元素」失败，
/// 而那个报错完全不提示真正的原因。
enum A11y {

    // MARK: - 主页状态栏

    /// 金币数字 → 收支明细
    static let coins = "home.coins"
    /// 星星 → 成就页
    static let achievements = "home.achievements"
    /// 店铺 → 商店
    static let shop = "home.shop"
    /// 爪印 → 宠物页
    static let pets = "home.pets"
    /// 齿轮 → 设置页
    static let settings = "home.settings"

    /// 当前最紧急的需求图标。**不是按钮**，但要能被读出来 ——
    /// 它是玩家判断「该做什么」的主要依据。
    static let dominantNeed = "home.need"

    // MARK: - 操作栏

    /// 三个交互按钮。`action.feed` / `action.play` / `action.clean`
    /// 与 `Interaction.all` 的 id 对齐，所以直接用前缀拼。
    static func action(_ id: String) -> String { "action.\(id)" }

    /// 喂食按钮的 id（它不在 `Interaction.all` 里 ——
    /// 喂食要先弹食物选择，不是直接生效）
    static let feed = "action.feed"

    // MARK: - 开局引导

    /// 起名输入框。
    ///
    /// ⚠️ 这个尤其必要：输入框的占位符和页面标题**是同一句文案**
    /// （`settings.name.placeholder`），Maestro 用文案定位会命中标题，
    /// 结果键盘没打开、输入落空、名字存成空字符串。
    static let nameField = "onboard.nameField"
    /// 「下一步 / 开始养育」
    static let onboardNext = "onboard.next"
    /// 「返回」
    static let onboardBack = "onboard.back"
    /// 品种卡片，参数是 `PetBreed.id`
    static func breedCard(_ id: String) -> String { "onboard.breed.\(id)" }

    // MARK: - 食物选择

    /// 食物行，参数是 `FoodItem.id`。
    /// 价格随饱食度变化，所以行文案不稳定 —— 用 id 定位才可靠。
    static func food(_ id: String) -> String { "food.\(id)" }

    // MARK: - 测试用

    /// 场景布局快照的载体（仅 DEBUG）。
    ///
    /// SpriteKit 场景对 XCUI 是黑盒，所以把关键位置导出成文本
    /// 挂在一个隐藏元素的 label 上，让 UI 测试能读到。
    /// 见 `PetScene.debugLayoutSnapshot`。
    static let sceneSnapshot = "debug.sceneSnapshot"

    // MARK: - 通用

    /// sheet 右上角的「完成」
    static let done = "common.done"
}
