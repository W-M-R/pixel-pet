# 架构

## 分层

```
Core/           基础设施：本地化、设计 token（Pixel）
Models/         值类型：状态、规则、配置表
Scenes/         SpriteKit 场景（房间、宠物、气泡）
Services/       有状态的协调者：存档、AI、通知
Views/          SwiftUI 界面
App/            组装
```

**依赖方向严格单向：**

```
Core → Models → {Scenes, Services} → Views → App
```

`Models` 不依赖任何上层，所以能脱离 UI 测试 —— 144 个测试里绝大多数在这一层。

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
| `AchievementRule` | 19 条成就是**同一类型的 19 个实例**，数据驱动 | 表里加一条，有 `streak()`/`counted()` 两个构造辅助 |
| `PetPersistence` | 存档方式可替换（文件/内存），测试不碰磁盘 | 实现协议，注入 `PetStore(storage:)` |
| `PetReminderScheduling` | 提醒实现可替换，测试不排真通知 | 实现协议，注入 `PetStore(reminders:)` |
| `BreedComponents` | 品种立绘/属性面板/毛色选择三处共用 | 直接用 `BreedPortrait` / `BreedStatPanel` / `CoatPicker` |
| `InteractionEffect`(Models) | 互动对状态的作用，纯数据 | 表里加一条 |
| `Interaction`(Views) | 互动的 UI 配置（图标/文案/延迟） | 表里加一条 + 动画 + 本地化 |
| `StatDimension` 表 | HUD 状态条从手写展开改成遍历 | 表里加一条 |
| `FoodItem` | 四档食物 + 按量计价 | `all` 加一条 + `PixelIcon` 加 case |
| `PetBreed` | 品种注册表，含 sheet 布局与几何参数 | `all` 加一条 + 跑素材脚本 |
| `PetStage` | 生命阶段的全部参数（额度、周期、体型、sheet 后缀） | 四档写死，加档要同时改帧派生脚本 |
| `StateThreshold` | 「多饿才算饿」原来散在 4 处，其中中英文 prompt 各一份必须手动同步 | 改一处 |
| `Pixel` + `PixelPanel` / `PixelBar` | UI 的网格、配色、字号、组件 | 用 token，不写字面量 |
| `PixelIcon` | 11 个自绘图标替代 emoji | 画点阵 + 加 case + 重跑脚本 |
| `RoomPalette` | 场景与 UI 共用配色（`Pixel.RGB` 同时给两层） | 加一个颜色 |
| `RoomRenderer` | 房间绘制，只依赖 size/wallBaseY/unit | 照 `block()` 的模式加几行 |
| `BubbleLayer` | 气泡，通过 `anchor` 闭包与宠物解耦 | 加一种气泡样式 |
| `FloorPlane` | 2.5D 深度数学，纯值类型零 SpriteKit 依赖 | 改透视参数 |
| `OpeningSequence` | 开场时序（顺序有硬约束） | 改延迟或消息编排 |
| `PetLineContext` | 台词系统的输入，AI 与预写台词共用 | 加状态字段 |

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

## 测试策略

144 个测试，分布：

| 文件 | 覆盖 |
|---|---|
| `EconomyTests` | 收益公式、额度、按量计价、平衡回归 |
| `CoinLedgerTests` | **账目恒等式**、原因分类、流水、旧存档迁移 |
| `PetStoreTests` | 互动通路、存档、结算、开局与商店 |
| `PetPersistenceTests` | 落盘、加载、内存与文件实现行为一致 |
| `ConfigTests` | 阶段/品种参数、**品种支配检验**、Fixture 自测 |
| `GeometryTests` | 2.5D 地板、精灵表帧布局 |
| `PetStateTests` | 衰减、作息、阈值一致性 |

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

### 仍不可测的部分

- `PetScene`（818 行）—— 需要 `SKView` 生命周期
- 4 个 View 文件 —— SwiftUI 视图
- `PetChatEngine` —— CoreML actor
- `PetState.ageInDays` 硬调 `Date()`，所以 `stage` 不可控 ——
  经济测试只能测幼年期

前两条是 iOS 的固有成本。第四条如果要修，得给 `ageInDays` 加
`at now:` 参数，会波及 `stage` 的所有调用方。

## 工具链

`tools/check_layers.sh` —— 分层依赖检查，接进 build phase。
自测过：注入一处越界会以退出码 1 失败并指出文件行号。


`tools/` 下 5 个绘图脚本共用 `pnglib.py`（68 行 PNG 编解码），
零重复。`econ_report.py` 是数值报表，不用 pnglib。

⚠️ `econ_report.py` 的参数必须和 `Sources/Models/` 手动同步。
它曾经严重脱同步（还在用被删掉的 `stateCoefficient`），
算出的所有数字都是错的。**真正的权威是 `EconomyTests` 的断言** ——
那些跑在 CI 里；脚本只用来看趋势和出 ASCII 表格。
