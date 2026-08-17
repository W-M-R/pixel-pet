# 奖励系统

## 设计目标

**加新奖励不改核心逻辑。**

现在能想到的奖励有三类（上线、看家、成就），但以后可能加"节日奖励"、
"喂食连击"、"集齐所有毛色"之类。所以做成可注册的规则表，
而不是在结算函数里堆 if-else。

## 抽象层

```swift
/// 一条奖励规则
protocol RewardRule {
    /// 存档去重用的稳定 ID。**改了会导致一次性奖励重复发放**，
    /// 所以定下来就不要动。
    var id: String { get }
    var nameKey: String { get }
    /// 一次性奖励（成就）发过就不再发；周期性奖励（上线/看家）每次都算
    var isOneTime: Bool { get }

    /// 返回 nil = 本次不触发
    func evaluate(_ ctx: RewardContext) -> RewardOutcome?
}

/// 结算时的上下文快照
struct RewardContext {
    let pet: PetState
    let wallet: PetWallet
    let now: Date
    /// 距上次结算的小时数
    let offlineHours: Double
    /// 离线期间的平均饱食与心情（各 0...1），见 01-economy.md。
    /// 分开传而不是先合成一个数 —— 合成规则属于奖励规则的职责。
    /// 清洁不在这里：72h 周期让它长期接近 1.0，只会稀释另两维。
    let avgSatiety: Double
    let avgMood: Double
    /// 今日剩余收益额度
    let remainingCap: Int
    /// 已领取的一次性奖励 ID
    let claimed: Set<String>
}

struct RewardOutcome {
    let coins: Int
    /// 宠物说什么（走台词气泡）
    let messageKey: String
    /// 消息里的格式化参数，如硬币数
    let messageArgs: [CVarArg]
}
```

## 引擎

```swift
struct RewardEngine {
    let rules: [RewardRule]

    /// 结算一次。返回总硬币与要展示的消息。
    func settle(_ ctx: RewardContext) -> RewardSettlement
}

struct RewardSettlement {
    let totalCoins: Int
    /// 新解锁的一次性奖励 ID，调用方要写进存档
    let newlyClaimed: [String]
    /// 按优先级排好的消息（通常只展示第一条）
    let messages: [(key: String, args: [CVarArg])]
}
```

引擎只做三件事：遍历规则、跳过已领的一次性奖励、汇总结果。
**不包含任何具体奖励的逻辑。**

## 首批三类规则

### 1. CheckInReward（上线）

```
每次打开 +10 枚，要求距上次结算 ≥ 5 小时
```

`isOneTime = false`，`countsTowardDailyCap = false` —— **不占额度**，
否则「领了上线奖励反而少赚看家钱」。5 小时限制防无脑开关刷币。

### 2. OfflineCareReward（看家）

```
min(今日剩余额度, 每日额度 × 达成率 × buff倍率)

每日额度 = PetStage.dailyCap                      // 幼170 → 成年225
达成率   = 0.05 + 0.30 × (0.40×饱食 + 0.60×心情)²   // 0.05 ~ 0.35
```

`countsTowardDailyCap = true` —— 唯一占额度的规则。

`isOneTime = false`。详细推导见 [01-economy.md](01-economy.md)。

### 3. AchievementRule（成就）

**29 条成就用同一个类型的 29 个实例**，数据驱动，不是 19 个 class：

```swift
struct AchievementRule: RewardRule {
    let id: String
    let nameKey: String
    let coins: Int
    /// 条件判定
    let condition: (PetState, PetWallet) -> Bool
    var isOneTime: Bool { true }
}
```

## 成就表（29 条，共 22830 枚）

### 陪伴（5 条，3800 枚）—— **看照顾质量，不看打开天数**

| ID | 名称 | 条件 | 奖励 |
|---|---|---|---|
| `first_feed` | 初次见面 | 首次喂食 | 100 |
| `streak_3` | 三日之交 | 连续 3 天 | 200 |
| `streak_7` | 一周之约 | 连续 7 天 | 500 |
| `streak_15` | 半月同行 | 连续 15 天 | 1000 |
| `streak_30` | 满月 | 连续 30 天 | 2000 |

### 成长（4 条，4450 枚）

| ID | 名称 | 条件 | 奖励 |
|---|---|---|---|
| `stage_growing` | 长大了 | 到成长期（3 天） | 150 |
| `stage_adult` | 成年礼 | 到成年期（7 天） | 300 |
| `stage_elder` | 老伙计 | 到老年期（30 天） | 1000 |
| `age_100` | 百日 | 相伴 100 天 | 3000 |

### 照料（5 条，3200 枚）

| ID | 名称 | 条件 | 奖励 |
|---|---|---|---|
| `feed_50` | 勤劳饲主 | 累计喂食 50 次 | 400 |
| `feed_200` | 大厨 | 累计喂食 200 次 | 1200 |
| `play_30` | 玩伴 | 累计玩耍 30 次 | 300 |
| `clean_20` | 爱干净 | 累计洗澡 20 次 | 300 |
| `clean_100` | 洁癖 | 累计洗澡 100 次 | 1000 |

### 美食（3 条，1200 枚）

| ID | 名称 | 条件 | 奖励 |
|---|---|---|---|
| `food_can` | 尝鲜 | 首次喂罐头 | 150 |
| `food_fish` | 奢侈 | 首次喂小鱼干 | 250 |
| `food_fish_20` | 小鱼干爱好者 | 喂小鱼干 20 次 | 800 |

### 收藏（2 条，700 枚）

| ID | 名称 | 条件 | 奖励 |
|---|---|---|---|
| `breed_2` | 换个伙伴 | 养过 2 种品种 | 300 |
| `color_4` | 配色师 | 试过 4 种毛色 | 400 |

## 成就总量的意义

**22830 枚 ≈ 82 天的日常开销**（按 280 枚/天算）。

这是长期激励的主要来源。日常收支基本打平（见 [04-balance.md](04-balance.md)），
所以想吃小鱼干、想攒钱，得靠成就。

## 为什么时间型成就要压价

早期版本里时间型成就（`streak_*` + `stage_*` + `age_100`）占全部
成就金额的 **61%**，而且 `streak_*` 只看「打开 app 的天数」——
每天点开一次就 +1，不管宠物什么状态。

后果是可量化的：**放养 30 天能买第二只宠物（4000 枚），
而认真照顾只要 13 天** —— 差距仅 2.3 倍，而放养是每天亏钱的。
这直接违反 docs/00-overview.md 第 5 条「照顾好宠物 = 赚得多」。

两处修改：

1. **`streak_*` 改看 `wellCaredDays`**（当天三维平均 ≥ 0.6 才算一天），
   放养再也拿不到。这是最关键的一刀。
2. **`stage_*` / `age_100` 压价**：150/300/1000/3000 → 80/150/400/800。
   它们纯粹是时间流逝的产物 —— 装着不管也会到成年，不该给大钱。
   省下的 3020 枚挪到要真互动的照料型。

效果：

| 频次 | 修复前 | 修复后 |
|---|---|---|
| 1 次/天（放养，每天亏钱） | 30 天 | **300 天** |
| 2 次/天 | 25 天 | 60 天 |
| 3 次/天 | 15 天 | 15 天 |
| 4 次/天（目标节奏） | 13 天 | **12 天** |

**认真玩的人没被惩罚**（13 → 12 天），只是放养不再能靠时间白拿钱。
放养/目标的倍数从 2.3x 变成 25x。

由 `AchievementBalanceTests` 守着：连续型必须看照顾质量、
纯时间型占比 < 25%、照料型必须是最大的一组。

## 两个「用初始值当条件」的坑

新加成就时踩到两次，都是白送钱：

- `all_high`（三维 ≥90%）—— **新宠物三维是满的**，开局第一秒就达成。
  修法：要求喂/玩/洗各做过一次，那才说明状态是维持出来的。
- `rich_5000`（存款 5000）—— **启动资金正好是 5000**。
  修法：改用 `totalEarned`（累计赚取）且门槛降到 3000，启动金不算。

第二个是 `OpeningSequenceTests` 抓到的 —— 它断言「刚建的 store
不该有收益播报」，结果冒出一条成就。现在
`testNoAchievementUnlocksAtOnboarding` 专门扫这类问题。

## 需要新增的数据

现有 `PetState` 缺三样，都用可选类型保证旧存档兼容：

```swift
/// 养过的品种（收藏成就用）
var triedBreeds: Set<String>?
/// 试过的毛色（收藏成就用）
var triedColors: Set<Int>?
/// 各档食物的喂食次数（美食成就用）。key = Food.id
var foodCounts: [String: Int]?
```

`PetWallet` 里加：

```swift
/// 已领取的一次性奖励 ID
var claimedRewards: Set<String>
```

## UI

成就做**独立页面**，从设置页 `NavigationLink` 进去。
29 条全塞设置里会让那一页太长。

页面按五组分 `Section`，每条显示：
- 名称 + 奖励硬币数
- 已领取：打勾 + 置灰
- 未领取：显示进度（如"喂食 32 / 50"）

进度条比单纯的"未完成"更有推动力。

## 相关文档

- 收益公式 → [01-economy.md](01-economy.md)
- 实施顺序与测试清单 → [05-implementation.md](05-implementation.md)
