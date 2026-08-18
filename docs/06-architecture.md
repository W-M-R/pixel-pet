# 架构

## 分层

```
Core/           基础设施：本地化、设计 token（Pixel）
Models/         值类型：状态、规则、配置表
Scenes/         SpriteKit 场景（房间、宠物、气泡）
Services/       有状态的协调者：存档、通知、台词调度
Views/          SwiftUI 界面
App/            组装
```

**依赖方向严格单向：**

```
Core → Models → {Scenes, Services} → Views → App
```

`Models` 不依赖任何上层，所以能脱离 UI 测试 —— 235 个单元测试里绝大多数在这一层。

### 由脚本强制，不靠自觉

`tools/check_layers.sh` 接进了 build phase，越界会**直接编译失败**。

它防的是实际发生过的三种越界：

| 越界 | 修法 |
|---|---|
| `Models/Interaction` → `Views/PixelIcon` | 拆成 `InteractionEffect`(Models) + `Interaction`(Views) |
| `Models/Interaction` → `Scenes/PetSpriteSheet` | `Duration` 跟着 `Interaction` 去 Views |
| `Scenes/RoomPalette` → `Views/Pixel` | `PixelStyle.swift` 移到 `Core/Design/` |

脚本会剥掉注释再匹配 —— 注释里提到上层类型是合理的（解释为什么这么分层）。

### 为什么不拆 SPM 模块

调研过完整方案，结论是**不值得**：

| 成本 | 数量 |
|---|---|
| `public` 标注 | 约 350-370 处 |
| 手写 `public init` | 10 个（memberwise init 不跨模块） |
| `SKScene` override 加 public | 8 个 |
| 新增 `Package.swift` | 6 个 |
| 补 import | 39 个文件 |

而收益在当前条件下全部不成立或有更便宜的替代：

- **无第二个 consumer** —— 单 app target，没有 widget / watch / App Clip。
  「以后要嵌入」如果指 WidgetKit，需要的是抽 `PetCore` **一个**包，不是六个。
- **规模不匹配** —— 6200 行生产代码，SPM 的收支平衡点在数万行 / 多人并行。
- **可能更慢** —— 6 个包改一个 public 签名触发下游全重编；
  单 target 有 whole-module-optimization 和更好的增量粒度。
- **资源是硬约束** —— 7 处 `Bundle.main` 调用，加上 `L()` 的
  `object_setClass(Bundle.main, ...)` 重定向 hack。资源移进 SPM 包会让
  `L()` 彻底失效（那个 hack 只 patch `Bundle.main`），
  要么改 `L()` 签名（波及 8 个文件），要么资源留 app target
  （那模块就不是自包含的）。
- **`@Observable` 静默失败** —— 类型标 public 后，漏标某个属性
  **不报错，只是 SwiftUI 不刷新**。3 个 `@Observable` 类几十个属性，
  这类 bug 的调试成本远超收益。

**等真要做 widget 时再抽 `PetCore` 一个包**（12 个 Models 文件，约 170 个
public，是全方案的一半成本、80% 的实际收益）。上面修循环的工作正好是前置
条件，不会白做。

### 「各模块出一个对象」已经做到了

这个诉求不需要 SPM。现有形态：

| 组件 | 入口 |
|---|---|
| `RoomRenderer` | `build(into:size:wallBaseY:unit:)` |
| `BubbleLayer` | 对象 + `speak`/`emote`/`sync`，依赖用 `anchor` 闭包注入 |
| `OpeningSequence` | `plan(store:)` → 值 → `announce(_:speak:fallback:)` |
| `PetStore` / `PetTalkCoordinator` | `@Observable` + 语义方法 |
| `PetScene` | `configure(...)` + `trigger*` + 两个回调 |
| `RewardEngine` | `rules` 注入 + `settle(_:)` 纯函数 |

`PetHomeView` 顶部那四行 `@State` 就是组装点。

## 抽象层清单

按「加新 feature 时会碰到哪些」组织。

| 抽象 | 解决什么 | 加东西时怎么做 |
|---|---|---|
| `RewardRule` 协议 + `RewardEngine` | 加奖励规则不改核心逻辑 | 实现协议 + 注册进 `RewardEngine.default` |
| `CoinLedger` + `CoinReason` | **金币变动的唯一入口**，账目可自检、流水可追溯 | 加玩法时加一个 `CoinReason` case，编译器强迫你归类收/支与额度 |
| `AchievementRule` | 29 条成就是**同一类型的 29 个实例**，数据驱动 | 表里加一条，有 `cared()`/`counted()` 两个构造辅助 |
| `PetPersistence` | 存档方式可替换（文件/内存），测试不碰磁盘 | 实现协议，注入 `PetStore(storage:)` |
| `PetReminderScheduling` | 提醒实现可替换，测试不排真通知 | 实现协议，注入 `PetStore(reminders:)` |
| `BreedComponents` | 品种立绘/属性面板/毛色选择三处共用 | 直接用 `BreedPortrait` / `BreedStatPanel` / `CoatPicker` |
| `InteractionEffect`(Models) | 互动对状态的作用，纯数据 | 表里加一条 |
| `Interaction`(Views) | 互动的 UI 配置（图标/文案/延迟） | 表里加一条 + 动画 + 本地化 |
| `StatDimension` 表 | HUD 状态条从手写展开改成遍历 | 表里加一条 |
| `FoodItem` | 四档食物 + 按量计价 | `all` 加一条 + `PixelIcon` 加 case |
| `PetBreed` | 品种注册表（属性、经济、布局引用） | `all` 加一条 + 跑素材脚本 |
| `PetSheetLayout` | **帧布局 per-breed**：格尺寸、毛色数、走路帧序、行语义、footPadding | 加一个 `static let`，不改渲染代码 |
| `PetActor` | **一只宠物在场景里的全部表现**：节点、影子、食盆、朝向、行为状态机 | 不用改 —— 场景按存档 diff 自动增删 |
| `FurnitureItem` + `ShopCategory` | 家具注册表（价格、sheet 索引、吃饭位）与商店分类 | 表里加一条 + 跑 `make_furniture.py` |
| `PetStage` | 生命阶段的全部参数（额度、周期、体型、sheet 后缀） | 四档写死，加档要同时改帧派生脚本 |
| `StateThreshold` | 「多饿才算饿」原来散在 4 处，其中中英文 prompt 各一份必须手动同步 | 改一处 |
| `Pixel` + `PixelPanel` / `PixelBar` | UI 的网格、配色、字号、组件 | 用 token，不写字面量 |
| `PixelIcon` | 11 个自绘图标替代 emoji | 画点阵 + 加 case + 重跑脚本 |
| `RoomPalette` | 场景与 UI 共用配色（`Pixel.RGB` 同时给两层） | 加一个颜色 |
| `RoomRenderer` | 房间绘制，只依赖 size/wallBaseY/unit | 照 `block()` 的模式加几行 |
| `BubbleLayer` | 气泡，通过 `anchor` 闭包与宠物解耦 | 加一种气泡样式 |
| `FloorPlane` | 2.5D 深度数学，纯值类型零 SpriteKit 依赖 | 改透视参数 |
| `OpeningSequence` | 开场时序（顺序有硬约束） | 改延迟或消息编排 |
| `PetLineContext` | 台词系统的输入（纯语义，不含时间戳） | 加状态字段 |

## 刻意没做的抽象

记录理由，避免以后「看起来该抽」时重复讨论。

**`PetScene` 不再拆分（818 行）。**
41 个 func 平均 13 行，最长 43 行，MARK 分区清晰。剩下的职责
（行为状态机 / 深度缩放 / 输入 / 动画）互相耦合很紧 ——
`moveToward` 要读 `floor.scaleFactor`，`applyDepthScale` 被动画和
状态机同时调用，输入层直接改 `touchPoint`/`behavior`。
强行拆开会让 `PetScene` 变成转发层，且打散大量记录「为什么不那样做」
的注释（120fps 像素吸附会卡住、`moveTo` vs `moveBy` 被打断、
缩放量化的失败尝试）—— **那些注释是资产**。

**互动动画不做策略协议。**
`triggerEat`/`triggerPlay`/`triggerClean` 的实现方式完全不同
（帧序列 / `moveTo` 序列 / `fadeAlpha` 序列），抽成协议只能消掉
几行 emote 调用，却让「洗澡时宠物做什么」需要在协议、3 个实现、
注册表之间跳转。现在 13 行的 `triggerClean` 一眼就懂。
只留了一个 `playAnimation(for:)` 做 id 分发。

**`PetState` 的 Codable 样板（56 行）保持手写。**
它处理 `species` → `breedID` 的旧存档迁移，并双写 `species` 支持降级。
改成合成 Codable 能省 40 行，但风险是存档兼容 —— 现有样板是正确的、
有测试的（`testDecodesLegacySpeciesField` / `testEncodeRoundTrip`）。

**`PetSettingsView` 不拆（270 行）。**
已按 6 个 section 分好，每段 20-40 行。拆成 6 个文件只增加跳转成本。

**Store 层不做仓储协议。**
只有 2 个 store，各 6 行 JSON 读写。泛型约束和类型擦除的复杂度
大于消除 12 行重复的收益。构造器参数（`init(directory:)`）就够了。

**导航不做路由层。**
6 个页面、最深 2 层。`.sheet` + `NavigationLink` 是 SwiftUI 惯用法，
加路由枚举会让「点设置进哪」变成间接查表。等有深链接再说。

**房间装饰不做数据驱动配置。**
`RoomRenderer.buildWallDecor` 画的是一幅固定构图的像素画。
把坐标抽成 JSON 会让「月牙是亮圆叠一个天空色圆」这类绘画技巧不可读。
可移动家具已由 `RoomLayout.Slot` 提供数据驱动，静态装饰不需要同一套。

**动画时长不做统一 token。**
25 处裸 duration 大多是一次性手感值（0.16 的蹦跳、0.05 的抖动），
集中起来只是换个地方写数字。**例外**是台词延迟与动画时长的跨文件依赖，
那三个值已收进 `Interaction.Duration`。

试过「延迟 = 动画时长 × 60%」的公式，**放弃了** —— 算出蹦跳 0.38s、
洗澡 0.43s，比手调的 0.7/0.8 更急，观感变差。这些值是按「动作演到
哪一拍最适合插话」调的，和总长不成固定比例。

## 界面信息架构

主页顶栏五个入口，各自一页：

| 图标 | 页面 | 内容 |
|---|---|---|
| 钱堆 | `EarningsView` | 余额、今日额度、收支构成、流水 |
| ♥ 需求 | （只读） | 当前最紧急的需求，不可点 |
| ★ | `AchievementsView` | 29 条成就与进度，点一条看解锁条件 |
| 店铺 | `ShopView` | 三个分类：宠物 / 用品（碗）/ 装饰（床、盆栽） |
| 爪印 | `PetsView` | 状态、起名、品种毛色、成长、陪伴记录 |
| 齿轮 | `PetSettingsView` | **只有应用级偏好**：通知、语言、素材授权 |

早期版本把这些全塞在设置页（七个 section），是「没想清楚放哪
就先扔设置里」的产物：给宠物起名要先点齿轮，成就要先点齿轮
再滚到底部 —— 而成就是主要金币来源。

分界线：**关于这只宠物的都在宠物页，关于 app 的才在设置页。**
由 `ViewStructureTests.testSettingsHasNoPetSpecificContent` 守着。

### sheet 页必须自带 NavigationStack

从 `NavigationLink` 目标改成 `.sheet` 时踩过：`ShopView` 和
`AchievementsView` 依赖外层导航容器提供标题栏，作为 sheet 弹出后
**整页没有标题栏也没有关闭按钮**，只能靠下滑手势。
编译通过、测试全绿，只有真机点进去才发现。

现在由 `ViewStructureTests.testSheetPresentedViewsAreDismissable`
扫源码断言三件事：有 `dismiss`、有 `NavigationStack`、有「完成」按钮。

这个测试自身也有个教训：第一版直接 `src.contains("NavigationStack")`，
注入回归自测时没抓到 —— 因为注释里就写着「自带 NavigationStack」。
剥掉注释再匹配才有效，和 `tools/check_layers.sh` 同一个坑。

## 图标全部自绘

**不用 SF Symbol，不用 emoji。** 两者都依赖系统字体 ——
字体缺失、旧系统没有那个符号名、模拟器字体没装全时，
整个图标会渲染成问号或豆腐块。像素风 app 里这种破图最扎眼。

所有图标来自 `Assets/ui/icons.png`（16 格 × 16px），
由 `tools/make_ui_icons.py` 以 ASCII 点阵自绘，
形状原创、配色取自 `Pixel` 色板、零授权负担。

清理掉的：
- `Image(systemName: "gearshape.fill")` → 自绘齿轮（4 齿 + 大孔，
  8 齿在 16px 下会糊成圆）
- `Image(systemName: "checkmark")` → 自绘对勾（语言页）
- `Text("✓")` → 同上（成就页）；字符也要字体里有那个字形
- 喂食气泡的 `🍖` → `icons.png` 第 0 格（这条是活路径，每次喂食都冒）
- `BubbleLayer.fallbackEmoji`（9 个）与 `PetNeed.emoji`（5 个）整表删除

`≠` 也换成了 `!=` —— DEBUG-only 文本，但没必要为一个符号留例外。

### 跨层的索引一致性

`Scenes` 和 `Models` 都要用图标，但**都不能引用 Views 层的 `PixelIcon`**
（分层规则）。所以它们用裸索引：`RoomSpriteSheet.uiIconTexture(index:)`、
`PetNeed.iconIndex`。三处顺序都由 `make_ui_icons.py` 的 ORDER 定义，
由 `IconSourceTests.testNeedIconIndicesMatchPixelIcon` 和
`testIconSheetMatchesEnumCount` 锁住。

**加图标只能追加到 ORDER 末尾** —— 中间插入会让所有后续索引错位。

## 测试策略

235 个单元测试 + 5 个 UI 测试，分布：

| 文件 | 覆盖 |
|---|---|
| `EconomyTests` | 收益公式、额度、按量计价、平衡回归 |
| `CoinLedgerTests` | **账目恒等式**、原因分类、分项汇总、流水、旧存档迁移 |
| `ViewStructureTests` | 扫源码：sheet 页能否关掉、设置页不含宠物内容、无 AI 残留 |
| `IconSourceTests` | 扫源码：**禁止 SF Symbol / emoji**、图标索引与 sheet 格数一致 |
| `PlaythroughTests` | 真实开局→互动→结算→买第二只，含**反复重启不能刷额度** |
| `SheetLayoutFlexibilityTests` | 换布局（48×48/2 色/4 帧走路）不改渲染代码 |
| `PetStoreTests` | 互动通路、存档、结算、开局与商店 |
| `PetPersistenceTests` | 落盘、加载、内存与文件实现行为一致 |
| `ConfigTests` | 阶段/品种参数、**品种支配检验**、Fixture 自测 |
| `GeometryTests` | 2.5D 地板、精灵表帧布局 |
| `PetStateTests` | 衰减、作息、阈值一致性 |
| `OnboardingNoFreeAchievementTests` | 开局不能白送成就，且**选猫选狗余额必须相同** |
| `CollectionAchievementReachableTests` | 收藏类成就真做到了要给（防止改成不可达） |
| `EatingPositionUITests`（UI） | 碗按存档摆位、宠物真的走到碗边吃、多只不重叠 |

三条原则：

**大量测试是有据可查的回归测试**，注释写明曾经的 bug。
`testStrokingDoesNotCauseSleep`（「一点它就睡觉」）、
`testWalkUsesThreeFramePingPong`（「走路一顿一顿」）、
`testPetScaleIsContinuous`（「走动时一闪一闪」）、
`testDailyCapCannotBeFarmedByRelaunching`（刷币面）。
这些的价值远高于覆盖率数字。

**表驱动的抽象自带测试收益。**
`testEveryInteractionMutatesState` 遍历 `InteractionEffect.all`，
加新互动时自动覆盖。`testInteractionTablesAreAligned` 则保证
拆开的两张表（Models 的作用表、Views 的 UI 表）不漂移。

**设计目标写成断言，而不是只写在文档里。**
「没有哪个品种明显最优」= `testNoBreedDominatesAnother` 遍历
四阶段 × 四频次做支配检验。这条曾经只写在文档里，
结果狗的金币定 1.05 时猫在全部阶段都支配它，没人发现
（因为只对齐了 4 次/天一个工作点，而那个点双方都撞额度上限）。

### 视图层怎么测

单元测试到 `Models` / `Services` 为止，SwiftUI 视图和 SpriteKit
场景由三层工具覆盖，各管一段：

| 层 | 工具 | 管什么 | 不管什么 |
|---|---|---|---|
| 冒烟 | `.maestro/smoke.yml` | 崩溃、白屏、点了没反应（61 步走完主路径） | 位置对不对 |
| 视觉 | `tools/verify_visual.py` | 家具按存档摆位、碗贴地（扫像素） | 宠物位置（不稳定，见下） |
| 行为 | `UITests/EatingPositionUITests` | 宠物真的走到碗边、进入吃饭状态、多只不重叠 | 画面好不好看 |

**为什么位置断言从像素挪到了 UI 测试。** SpriteKit 场景对 XCUI 是
黑盒（宠物家具都在一个 `SpriteView` 里），最初只能扫屏幕像素。
但那个方案为「宠物围到碗边」调了 5 轮阈值都不稳：宠物会挡住碗
（实测只露 61px，正常 161px）、成就气泡会盖住宠物、没被派活的
宠物在自由游荡。5 轮还没稳是**方法不对**的信号 ——
位置这种精确的事该问场景本身，不该靠数像素反推。

改法：`PetScene.debugLayoutSnapshot`（仅 DEBUG）把关键坐标导出成
归一化文本，挂在一个 1×1 透明元素的 `accessibilityLabel` 上，
UI 测试直接读。像素层则收窄到只做**稳定且不重复**的检查。

**深层场景靠启动参数铺存档**（`UITestScene`，仅 DEBUG）：
`-uitest-scene bowl-two-pets` 直接写好「两只宠物 + 碗在 0.35」，
不用点着玩到那一步（要攒 800 买碗、4000 买第二只）。

### 仍不可测的部分

- `PetState.ageInDays` 硬调 `Date()`，所以 `stage` 不可控 ——
  经济测试只能测幼年期。要修得给 `ageInDays` 加 `at now:` 参数，
  会波及 `stage` 的所有调用方。
- 视觉层只断言「位置对」，**不断言「好看」** —— 配色、动画节奏、
  像素抖动这些还是得看截图。`.probe/` 下的图就是为这个留的。

## 工具链

`tools/check_layers.sh` —— 分层依赖检查，接进 build phase。
自测过：注入一处越界会以退出码 1 失败并指出文件行号。

`tools/inject_save.py` —— 往模拟器写存档，给视觉脚本铺场景。
时间戳是**倒推**的：这个 app 的状态全由「距上次喂食多久」算出来，
不存数值，所以造「快饿了的猫」是把 `lastFedAt` 往前挪。

`tools/verify_visual.py` —— 截图 + 扫像素做断言。
⚠️ **颜色必须从素材精确提取，不能靠「看起来是蓝的」猜。**
第一版按颜色范围判定，结果匹配到窗户的夜空，三个不同场景给出
完全相同的外接框（148662 像素），而我以为断言通过了。


`tools/` 下 5 个绘图脚本共用 `pnglib.py`（68 行 PNG 编解码），
零重复。`econ_report.py` 是数值报表，不用 pnglib。

⚠️ `econ_report.py` 的参数必须和 `Sources/Models/` 手动同步。
它曾经严重脱同步（还在用被删掉的 `stateCoefficient`），
算出的所有数字都是错的。**真正的权威是 `EconomyTests` 的断言** ——
那些跑在 CI 里；脚本只用来看趋势和出 ASCII 表格。
