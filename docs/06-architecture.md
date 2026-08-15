# 架构

## 分层

```
Views/          SwiftUI 界面 + 像素风设计 token
Scenes/         SpriteKit 场景（房间、宠物、气泡）
Models/         值类型：状态、规则、配置表
Services/       有状态的协调者：存档、AI、通知、本地化
Core/           基础设施（本地化）
```

依赖方向单一：`Views → Services → Models`，`Scenes → Models`。
`Models` 不依赖任何上层，所以能脱离 UI 测试 —— 96 个测试里绝大多数在这一层。

## 抽象层清单

按「加新 feature 时会碰到哪些」组织。

| 抽象 | 解决什么 | 加东西时怎么做 |
|---|---|---|
| `RewardRule` 协议 + `RewardEngine` | 加奖励规则不改核心逻辑 | 实现协议 + 注册进 `RewardEngine.default` |
| `AchievementRule` | 19 条成就是**同一类型的 19 个实例**，数据驱动 | 表里加一条，有 `streak()`/`counted()` 两个构造辅助 |
| `Interaction` 表 | 加互动从 22 个编辑点降到 3-4 个 | 表里加一条 + 动画 + 本地化 |
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

96 个测试，分布：

| 文件 | 数量 | 覆盖 |
|---|---|---|
| `EconomyTests` | 28 | 收益公式、额度、计价、平衡回归 |
| `PetStoreTests` + `OpeningSequenceTests` | 26 | 互动通路、存档、结算、开场时序 |
| `PetStateTests` 等 | 42 | 衰减、阈值、几何、帧序、品种参数 |

两条原则：

**大量测试是有据可查的回归测试**，注释写明曾经的 bug。
`testStrokingDoesNotCauseSleep`（「一点它就睡觉」）、
`testWalkUsesThreeFramePingPong`（「走路一顿一顿」）、
`testPetScaleIsContinuous`（「走动时一闪一闪」）、
`testDailyCapCannotBeFarmedByRelaunching`（刷币面）。
这些的价值远高于覆盖率数字。

**表驱动的抽象自带测试收益。**
`testEveryInteractionMutatesState` 遍历 `Interaction.all`，
加新互动时自动覆盖。

### 仍不可测的部分

- `PetScene`（818 行）—— 需要 `SKView` 生命周期
- 4 个 View 文件 —— SwiftUI 视图
- `PetChatEngine` —— CoreML actor
- `PetState.ageInDays` 硬调 `Date()`，所以 `stage` 不可控 ——
  经济测试只能测幼年期

前两条是 iOS 的固有成本。第四条如果要修，得给 `ageInDays` 加
`at now:` 参数，会波及 `stage` 的所有调用方。

## 工具链

`tools/` 下 5 个绘图脚本共用 `pnglib.py`（68 行 PNG 编解码），
零重复。`econ_report.py` 是数值报表，不用 pnglib。

⚠️ `econ_report.py` 的参数必须和 `Sources/Models/` 手动同步。
它曾经严重脱同步（还在用被删掉的 `stateCoefficient`），
算出的所有数字都是错的。**真正的权威是 `EconomyTests` 的断言** ——
那些跑在 CI 里；脚本只用来看趋势和出 ASCII 表格。
