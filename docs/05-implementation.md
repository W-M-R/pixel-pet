# 实施计划

## 已知 bug

### 底部按钮的 emoji 不显示

**现象**：喂食/玩耍/洗澡三个按钮只有文字，🍖🎾🛁 是空白的。

**根因**：`ActionButton` 里写的是

```swift
Text(emoji)          // ❌ 走 LocalizedStringKey 初始化器
```

SwiftUI 把 `"🍖"` 当成本地化 key 去 catalog 里查，查不到就返回空字符串。

**为什么以前没发现**：这是做应用内语言切换时引入的副作用。
SpriteKit 的气泡用 `SKLabelNode(text:)`，不经过本地化，
所以**气泡里的 emoji 一直正常**，只有 SwiftUI 按钮的消失了。

**修法**：

```swift
Text(verbatim: emoji)    // ✅
```

这是 `app-i18n` skill 警告过的 `Text(变量)` 陷阱的变体。
实施时顺手扫一遍其他 `Text(非字面量)` 的地方。

## 数据结构变更

### PetState 新增（全部可选，旧存档兼容）

```swift
/// 养过的品种（收藏成就）
var triedBreeds: Set<String>?
/// 试过的毛色（收藏成就）
var triedColors: Set<Int>?
/// 各档食物喂食次数，key = Food.id（美食成就）
var foodCounts: [String: Int]?
```

⚠️ `PetState` 已经有自定义 `init(from:)` / `encode(to:)`
（为兼容旧的 `species` 字段），新字段要加进 `CodingKeys` 并用
`decodeIfPresent`，否则旧存档会解码失败、宠物被重置。

### 新文件 PetWallet

```swift
struct PetWallet: Codable {
    var coins: Int
    var lastCollectedAt: Date
    var boostUntil: Date?
    var totalEarned: Int
    var claimedRewards: Set<String>
}
```

独立存 `wallet.json`，不塞进 `pet.json`——换宠物不该清空钱包。

### 参数改动

```swift
// PetState.Decay
static let hunger: TimeInterval = 8 * 3600     // 原 12
```

心情（18h）和清洁（72h）不变。

## 实施顺序

按依赖关系排，每步都能独立构建通过。

**1. 修 emoji bug**（5 分钟）
`Text(verbatim:)`。独立于其他改动，先做掉。

**2. PetWallet + 存档**
新文件、读写、旧档缺失时的初始化。这一步没有 UI，靠测试验证。

**3. RewardRule 协议 + RewardEngine**
只有抽象层和引擎，规则表为空。写测试确认"空规则表返回零收益"。

**4. 三类规则**
`CheckInReward` / `OfflineCareReward` / `AchievementRule`（19 条数据）。
这一步的重点是**平均状态的计算**，要单独写测试。

**5. 饱食周期 12h → 8h**
一行改动，但会影响现有测试的断言，一起改。

**6. 食物四档 + 选择器 UI**
`Food` 模型 + 喂食选择器 sheet。
显示"能管多久"要用动态计算（按当前饱食值），不是静态文案。

**7. 结算接入台词气泡**
复用 `PetScene.showSpeech()`。低于 1 枚不说话。

**8. 硬币显示**
主界面状态栏加硬币数。

**9. 成就页面**
独立页面，五组 Section，显示进度与已领标记。

## 测试清单

### 经济

- [ ] 离线 5/8/10/12/24 小时的收益符合平衡表
- [ ] 时长上限 10 小时生效（离线 24h 不等于 24 枚）
- [ ] 状态系数边界：平均状态 0 → 0.4×，1.0 → 1.5×
- [ ] 平均状态公式：离线 ≤ 周期用梯形，> 周期用面积法
- [ ] buff 生效期内 ×1.3，过期后 ×1.0
- [ ] 上线奖励：间隔 <5h 不发，≥5h 发 1 枚

### 食物

- [ ] 剩饭免费且无限
- [ ] 硬币不足时买不了（但按钮可点，给提示）
- [ ] 饱食封顶 100%，不会超出
- [ ] 半饱时吃罐头只补到 100%（不浪费成负数）
- [ ] 小鱼干设置 `boostUntil` 为 24 小时后

### 成就

- [ ] 每条成就的触发条件正确
- [ ] 一次性奖励不重复发放（`claimedRewards` 去重）
- [ ] 条件达成但已领取 → 不再发
- [ ] 19 条全部触发后总额 = 1335 枚

### 兼容

- [ ] 旧 `pet.json`（无新字段）能正常解码
- [ ] 无 `wallet.json` 时初始化为 0 枚
- [ ] 旧的 `species` 字段仍能读（已有测试，确认不回归）

### 平衡回归

- [ ] 4 次/天模式结余在 ±5 枚内
- [ ] 1 次/天模式结余在 ±5 枚内

平衡测试要用固定的模拟时间序列，不能依赖 `Date()`。

## 模拟器验证

代码测试过不了的部分，要实际跑一遍：

- 四档食物的选择器视觉
- 结算台词是否正常显示
- 硬币数变化
- 成就页面的分组与进度
- **emoji 图标是否显示**（这是本轮起因）

截图存 `.probe/`，不入 git。

## 风险

**1. 8 小时周期可能太缠人**
4.3 次/天在实测中可能让人烦。如果是，退回 10 小时。
这个只能靠真实体验判断，文档里的数字判断不了。

**2. app 复杂度上升**
现在是"点三个按钮"，之后变成"看收益 → 选食物 → 花钱 → 看成就"。
对留存是双刃剑。如果上线后数据不好，**离线收益 + 结算台词**是最值得
保留的部分（钩子最直接），食物和成就可以砍。

**3. 成就页面 19 条可能显得空洞**
如果前期只解锁 2-3 条，剩下 16 条全是灰的，可能有挫败感。
可以考虑只显示"已解锁 + 下一个目标"，而非全部列出。

## 相关文档

- 总览与设计原则 → [00-overview.md](00-overview.md)
- 经济公式 → [01-economy.md](01-economy.md)
- 食物 → [02-food.md](02-food.md)
- 奖励与成就 → [03-rewards.md](03-rewards.md)
- 平衡推导 → [04-balance.md](04-balance.md)
