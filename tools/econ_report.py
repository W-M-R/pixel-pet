#!/usr/bin/env python3
"""
金币收益全场景计算器。

⚠️ **参数必须与 Sources/Models/ 保持一致**，改 Swift 后重跑此脚本核对。
真正的权威是 Tests/EconomyTests.swift 的断言 —— 那些跑在 CI 里，
这个脚本只是用来看趋势和出表格（测试给不了 ASCII 曲线）。

上一版本已经和代码脱同步（还在用被删掉的 stateCoefficient 三维乘法、
按小时×速率的旧模型），算出的所有数字都是错的。这次重写对齐额度制。
"""

# ---- 与 Swift 对齐的参数 ----
# PetStage.hungerCycleHours / dailyCap
STAGE = {
    'young':   dict(cycle=12.0, cap=170),
    'growing': dict(cycle=10.0, cap=195),
    'adult':   dict(cycle=8.0,  cap=225),
    'elder':   dict(cycle=9.0,  cap=205),
}
# PetBreed —— 品种属性差异
# ⚠️ 这张表原来不存在，脚本没有 gold 参数，所以算不出它被引用的品种表。
BREED = {
    'cat': dict(mood=18.0, hygiene=72.0, gold=1.00),
    'dog': dict(mood=14.0, hygiene=72.0, gold=1.10),
}
DEFAULT_BREED = 'cat'
MOOD_CYCLE = BREED[DEFAULT_BREED]['mood']   # 兼容旧调用

# OfflineCareReward.Rate
RATE_FLOOR, RATE_SPAN = 0.05, 0.30
W_SATIETY, W_MOOD = 0.40, 0.60
MIN_SETTLE_H = 0.5

# CheckInReward
CHECKIN_COINS, CHECKIN_MIN_H = 10, 5.0

# FoodItem —— 价格 = max(最低价, 补上的饱食量×10×UNIT + 附加效果固定价)
UNIT = 5                   # coinsPer10Percent
RESTORE = dict(scraps=0.30, kibble=0.70, can=1.0, fish=1.0)
# 附加效果（心情/buff）按固定价 —— 它的价值和饱食无关。
# 曾经整个价格都按量算，导致饱食 99% 时小鱼干只要 3 枚却拿满额 buff。
EXTRA = dict(scraps=0, kibble=0, can=100, fish=200)
# 最低价 —— 防「满饱时全免费」可零成本刷 foodCounts 和成就
MIN_PRICE = dict(scraps=0, kibble=2, can=100, fish=200)
FREE = {'scraps'}          # 剩饭永久免费（防死锁兜底）
BOOST = 1.6                # boostMultiplier（抬达成率，不是乘收益）


def avg(h, cycle):
    """RewardEngine.averageLevel —— 线性衰减的梯形均值"""
    if h <= 0 or cycle <= 0:
        return 1.0
    return 1.0 - h / (2 * cycle) if h <= cycle else (cycle * 0.5) / h


def rate(satiety, mood, boost=False):
    """OfflineCareReward.achievementRate"""
    blend = W_SATIETY * satiety + W_MOOD * mood
    r = RATE_FLOOR + RATE_SPAN * blend * blend
    return r * (BOOST if boost else 1.0)


def food_cost(current_satiety, food='kibble'):
    """
    FoodItem.cost —— 饱食部分按量，附加效果固定价，再套最低价。

    与 Swift 的 FoodItem.cost(currentSatiety:) 保持一致。
    """
    if food in FREE:
        return 0
    gained = min(RESTORE[food], 1.0 - current_satiety)
    satiety_part = int(gained * 10 * UNIT + 0.5)
    return max(MIN_PRICE[food], satiety_part + EXTRA[food])


def simulate_day(stage, feeds_per_day, food='kibble', mood_override=None,
                 boost=False, breed=DEFAULT_BREED):
    """
    模拟一天。返回 (收入, 支出, 净结余)。

    ⚠️ 两个容易错的地方：
    1. 收入要走额度累加，否则每段都能拿满额度 —— 那正是刷币漏洞。
    2. **金币加成乘在 min() 之前**，和 Swift 一致
       （RewardRules.evaluate）。乘在之后会让加成不受额度限制，
        算出的数字偏高，也就看不出「加成被封顶吃掉」这个真实现象。
    """
    cfg = STAGE[stage]
    cycle, cap = cfg['cycle'], cfg['cap']
    b = BREED[breed]
    mood_cycle, gold = b['mood'], b['gold']
    gap = 24.0 / feeds_per_day
    remain = cap
    income = 0
    cost = 0

    for _ in range(feeds_per_day):
        if gap >= MIN_SETTLE_H and remain > 0:
            s = avg(gap, cycle)
            m = mood_override if mood_override is not None else avg(gap, mood_cycle)
            want = int(cap * rate(s, m, boost) * gold + 0.5)
            pay = min(remain, want)
            income += pay
            remain -= pay
        if gap >= CHECKIN_MIN_H:
            income += CHECKIN_COINS
        # 喂食：从「离线后的饱食」补回，逐餐单独取整
        after = max(0.0, 1 - gap / cycle)
        cost += food_cost(after, food)

    return income, cost, income - cost


# ---- 配平求解与支配检验 ----

def net_for(stage, mood_cycle, gold, feeds):
    """给定任意 (心情周期, 金币) 算日净结余。用于反解配平系数。"""
    cfg = STAGE[stage]
    cycle, cap = cfg['cycle'], cfg['cap']
    gap = 24.0 / feeds
    remain = cap
    income = 0
    cost = 0
    for _ in range(feeds):
        if gap >= MIN_SETTLE_H and remain > 0:
            s = avg(gap, cycle)
            m = avg(gap, mood_cycle)
            pay = min(remain, int(cap * rate(s, m) * gold + 0.5))
            income += pay
            remain -= pay
        if gap >= CHECKIN_MIN_H:
            income += CHECKIN_COINS
        cost += food_cost(max(0.0, 1 - gap / cycle))
    return income - cost


def solve_gold(mood_cycle, target, stage='adult', feeds=4,
               lo=0.85, hi=1.25, step=0.01):
    """
    反解让日净结余等于 target 的 goldMultiplier。

    ⚠️ **用枚举而不是二分。**

    目标函数含取整（`int(x+0.5)`），是分段常数函数 —— 数学上**没有根**，
    它直接跳过目标值。所以：
      · scipy.brentq 的前置条件 "f must be continuous" 不满足
      · fsolve 需要导数，而这里梯度几乎处处为 0
      · 手写二分会收敛到平台的**左边缘**，零余量：
        再减 1e-6 就掉到下一档。取整到两位小数时很容易掉下去。

    实际后果：docs/07-shop.md 的配平表曾有 4 行（16/18/19/20h）
    取整后落到 92 而不是 96。

    参数只有两位小数、区间也，所以候选只有约 40 个 —— 直接枚举，
    取命中平台的**中点**（双向余量最大）。无解时明确报错。
    """
    n = int(round((hi - lo) / step))
    cands = [round(lo + i * step, 2) for i in range(n + 1)]
    hits = [g for g in cands
            if net_for(stage, mood_cycle, g, feeds) == target]
    if not hits:
        raise ValueError(
            f"心情 {mood_cycle}h 没有两位小数的金币值能让 "
            f"{stage} {feeds}次/天 的净结余等于 {target}")
    return hits[len(hits) // 2]


def dominates(a, b):
    """a 支配 b：每项都不差，且至少一项更好。"""
    return all(x >= y for x, y in zip(a, b)) and any(x > y for x, y in zip(a, b))


def find_dominance(stage, feeds_range=(1, 2, 3, 4)):
    """
    找出支配其它品种的品种。返回 [(强者, 弱者), ...]，空 = 没有最优解。

    设计目标是「没有哪个品种明显最优」，这就是它的可执行版本。
    曾经漏掉这个检查：狗的金币 1.05 时猫在全部四阶段都支配它。
    """
    prof = {name: tuple(simulate_day(stage, f, breed=name)[2]
                        for f in feeds_range)
            for name in BREED}
    return [(x, y) for x in prof for y in prof
            if x != y and dominates(prof[x], prof[y])], prof


def bar(v, mx, w=22):
    return '#' * int(round(v / mx * w)) if mx > 0 else ''


def main():
    print("=" * 74)
    print(" 一、达成率随离线时长变化（成年，8h 饱食周期）")
    print("=" * 74)
    print(f"{'离线':>6s} {'饱食':>6s} {'心情':>6s} {'达成率':>7s} {'单次收益':>9s}")
    print("-" * 74)
    cap = STAGE['adult']['cap']
    for h in (1, 2, 4, 6, 8, 12, 24, 48):
        s = avg(h, STAGE['adult']['cycle'])
        m = avg(h, MOOD_CYCLE)
        r = rate(s, m)
        print(f"{h:5.0f}h {s:6.2f} {m:6.2f} {r:7.3f} {int(cap*r+0.5):9d}")

    print()
    print("=" * 74)
    print(" 二、日收支（全吃普通粮）")
    print("=" * 74)
    for stage in ('young', 'adult'):
        cfg = STAGE[stage]
        print(f"\n--- {stage}  周期 {cfg['cycle']:.0f}h  额度 {cfg['cap']} ---")
        print(f"  {'次/天':>5s} {'收入':>5s} {'粮钱':>5s} {'净':>6s}  趋势")
        nets = []
        for n in (1, 2, 3, 4, 5, 6, 8, 12):
            inc, cost, net = simulate_day(stage, n)
            nets.append((n, inc, cost, net))
        peak = max(net for _, _, _, net in nets)
        for n, inc, cost, net in nets:
            print(f"  {n:5d} {inc:5d} {cost:5d} {net:+6d}  {bar(max(net,0), peak)}")
        print(f"   峰值 +{peak}/天"
              f"   罐头(150) {150/peak:.1f}天"
              f"   鱼干(250) {250/peak:.1f}天")

    print()
    print("=" * 74)
    print(" 三、设计目标校验（照顾越勤越赚）")
    print("=" * 74)
    print(" 「照顾好宠物=赚得多」的可执行版本：从放养到目标节奏严格递增。")
    print()
    print(" ⚠️ 含上线奖励时峰值在 4 次/天（间隔 6h ≥ 5h 门槛），")
    print("    5 次/天（间隔 4.8h）反而拿不到上线奖励。所以只断言 1→4 递增，")
    print("    4 次/天之后要求「不暴跌」而非继续增长。")
    print("    Tests/EconomyTests.swift 的 netDaily 不含上线奖励，")
    print("    所以那边能断言 1→5 递增 —— 两种口径都对，但这里更接近玩家实感。")
    print()
    for stage in STAGE:
        nets = [simulate_day(stage, n)[2] for n in (1, 2, 3, 4)]
        mono = all(nets[i] < nets[i+1] for i in range(len(nets) - 1))
        peak = simulate_day(stage, 4)[2]
        tail = [simulate_day(stage, n)[2] for n in (5, 6, 8, 12)]
        # 阈值 0.65：young 从 104 掉到 70 是 -33%，这是真实现象
        # （4次/天间隔 6h 刚好卡在上线奖励门槛上，5次/天就拿不到），
        # 不为了让检查通过而放宽 —— 记录下来供后续调参参考。
        no_crash = all(t > peak * 0.65 for t in tail)
        print(f"  {stage:<8s} 1→4次/天 {nets}"
              f"  {'✅ 递增' if mono else '❌ 不递增'}"
              f"   之后 {tail}"
              f"  {'✅ 不暴跌' if no_crash else '❌ 暴跌'}")

    print()
    print("  不陪玩（心情钉 0.15，成年）：")
    for n in (3, 5):
        inc, cost, net = simulate_day('adult', n, mood_override=0.15)
        print(f"    {n}次/天  收{inc} 支{cost} 净{net:+d}"
              f"  {'✅ 倒亏' if net < 0 else '❌ 应该倒亏'}")

    print()
    print("  小鱼干 buff（达成率 ×1.6，成年）：")
    for n in (2, 3, 4, 5, 6):
        plain = simulate_day('adult', n)[0]
        boosted = simulate_day('adult', n, boost=True)[0]
        print(f"    {n}次/天  普通 {plain:3d}  有buff {boosted:3d}"
              f"  多赚 {boosted-plain:+4d}")

    print()
    print("=" * 74)
    print(" 四、品种差异与支配检验")
    print("=" * 74)
    print(" 设计目标：没有哪个品种明显最优。")
    print(" 检验方式：支配关系 —— 若某品种在【所有频次】都不差且至少一项更好，")
    print("           它就支配了对手，设计目标不成立。")
    print()
    print(f" {'品种':<6s} {'心情':>5s} {'金币':>6s}  1-4 次/天的净结余")
    print("-" * 74)
    for name, b in BREED.items():
        row = [simulate_day('adult', f, breed=name)[2] for f in (1, 2, 3, 4)]
        print(f" {name:<6s} {b['mood']:4.0f}h {b['gold']:6.2f}  {row}")
    print()
    for stage in STAGE:
        pairs, prof = find_dominance(stage)
        mark = "✅ 无支配" if not pairs else f"❌ {pairs}"
        print(f"  {stage:<8s} {mark}")
    print()
    print(" 反解配平系数（让「成年 4 次/天」等于猫的基准）:")
    target = simulate_day('adult', 4, breed='cat')[2]
    cells = []
    for mc in (13, 14, 15, 16, 17, 18, 19, 20, 21, 22):
        try:
            cells.append(f"{mc}h→{solve_gold(mc, target):.2f}")
        except ValueError:
            cells.append(f"{mc}h→无解")
    for i in range(0, len(cells), 5):
        print("   " + "  ".join(cells[i:i+5]))

    print()
    print("=" * 74)
    print(" 五、单次喂食花费（按当前饱食，成年）")
    print("=" * 74)
    print(f" {'饱食':>6s} {'剩饭':>6s} {'普通粮':>7s} {'罐头':>6s} {'小鱼干':>7s}")
    for cur in (0.0, 0.3, 0.6, 0.9, 0.95, 1.0):
        cells = " ".join(f"{food_cost(cur, f):6d}"
                         for f in ('scraps', 'kibble', 'can', 'fish'))
        print(f" {cur*100:5.0f}% {cells}")


if __name__ == '__main__':
    main()
