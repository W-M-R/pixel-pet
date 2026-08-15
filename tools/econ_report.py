#!/usr/bin/env python3
"""
金币收益全场景计算器。

参数与 Sources/Models/RewardRules.swift 严格一致 —— 改代码后重跑此脚本核对。
"""
CYCLE = dict(satiety=8.0, mood=18.0, hygiene=72.0)   # PetState.Decay (小时)
RATE, CAP = 9.0, 10.0                                 # OfflineCareReward
CHECKIN_COINS, CHECKIN_MIN_H = 10, 5.0                 # CheckInReward
W = dict(sB=0.70, sS=0.30, mB=0.45, mS=0.55, hB=0.85, hS=0.15, cB=0.30, cS=1.05)
BOOST, MIN_SETTLE_H = 1.3, 0.5
PRICE = dict(scraps=0, kibble=70, can=140, fish=320)

def avg(h, cycle):
    """RewardEngine.averageLevel"""
    if h <= 0 or cycle <= 0: return 1.0
    return 1.0 - h/(2*cycle) if h <= cycle else (cycle*0.5)/h

def coef(s, m, hy):
    """OfflineCareReward.stateCoefficient"""
    f = (W['sB']+W['sS']*s) * (W['mB']+W['mS']*m) * (W['hB']+W['hS']*hy)
    return W['cB'] + f*W['cS']

def care_coins(h, boost=False, mood=None):
    """一次离线的看家收益（含 Int(rounded) 取整）"""
    if h < MIN_SETTLE_H: return 0
    s  = avg(h, CYCLE['satiety'])
    m  = mood if mood is not None else avg(h, CYCLE['mood'])
    hy = avg(h, CYCLE['hygiene'])
    raw = min(h, CAP) * RATE * coef(s, m, hy) * (BOOST if boost else 1.0)
    return int(raw + 0.5)

def checkin(h): return CHECKIN_COINS if h >= CHECKIN_MIN_H else 0
def session(h, **kw): return care_coins(h, **kw) + checkin(h)

def bar(v, mx, w=22):
    return '█'*int(round(v/mx*w)) if mx > 0 else ''

print("="*72)
print(" 一、单次离线的收益（状态自然衰减）")
print("="*72)
print(f"{'离线':>6s} {'饱食':>6s} {'心情':>6s} {'清洁':>6s} {'系数':>6s} {'看家':>5s} {'上线':>5s} {'合计':>5s}")
print("-"*72)
rows=[]
for h in (0.5,1,2,3,4,5,6,7,8,9,10,11,12,14,16,20,24,36,48,72):
    s,m,hy = avg(h,CYCLE['satiety']), avg(h,CYCLE['mood']), avg(h,CYCLE['hygiene'])
    c, ci = care_coins(h), checkin(h)
    rows.append((h, c+ci))
    print(f"{h:5.1f}h {s:6.2f} {m:6.2f} {hy:6.2f} {coef(s,m,hy):6.2f} {c:5d} {ci:5d} {c+ci:5d}")
mx=max(t for _,t in rows)
print()
print(" 收益曲线：")
for h,t in rows:
    print(f"  {h:5.1f}h {t:3d} {bar(t,mx)}")
print(f"\n  峰值 {mx} 枚，出现在 {[h for h,t in rows if t==mx]} 小时")

print()
print("="*72)
print(" 二、状态对收益的影响（固定离线 10h = 收益峰值）")
print("="*72)
H=10.0
print("\n  单独调整某一维度，其余保持 0.9：")
print(f"  {'维度':<6s} {'0.0':>6s} {'0.2':>6s} {'0.4':>6s} {'0.6':>6s} {'0.8':>6s} {'1.0':>6s}  {'满→空跌幅':>10s}")
for axis in ('satiety','mood','hygiene'):
    line=[]
    for v in (0.0,0.2,0.4,0.6,0.8,1.0):
        d=dict(s=0.9,m=0.9,hy=0.9)
        d['s' if axis=='satiety' else ('m' if axis=='mood' else 'hy')]=v
        raw=min(H,CAP)*RATE*coef(d['s'],d['m'],d['hy'])
        line.append(int(raw+0.5))
    drop=(1-line[0]/line[-1])*100
    name={'satiety':'饱食','mood':'心情','hygiene':'清洁'}[axis]
    print(f"  {name:<6s} {line[0]:6d} {line[1]:6d} {line[2]:6d} {line[3]:6d} {line[4]:6d} {line[5]:6d}  {drop:9.0f}%")

print("\n  → 心情跌幅最大，符合「心情差要少赚」的设计")

print()
print("  综合状态档位：")
print(f"  {'状态':<6s} {'饱食':>5s} {'心情':>5s} {'清洁':>5s} {'系数':>6s} {'10h收益':>8s} {'相对满值':>9s}")
best=coef(1,1,1)
for label,(s,m,hy) in [("全满",(1,1,1)),("良好",(0.8,0.8,0.9)),("一般",(0.5,0.5,0.8)),
                        ("较差",(0.3,0.3,0.6)),("很差",(0.1,0.1,0.4)),("全空",(0,0,0))]:
    k=coef(s,m,hy); c=int(min(H,CAP)*RATE*k+0.5)
    print(f"  {label:<6s} {s:5.1f} {m:5.1f} {hy:5.1f} {k:6.2f} {c:8d} {k/best*100:8.0f}%")

print()
print("="*72)
print(" 三、日收益与收支平衡")
print("="*72)
patterns = [
    ("每 4h 一次 (6次/天)", [4]*6),
    ("每 5h 一次 (5次/天)", [5]*5),
    ("早中晚+睡前 (4次/天)", [8,5,5,6]),
    ("早中晚 (3次/天)",      [8,8,8]),
    ("早晚 (2次/天)",        [12,12]),
    ("一天 1 次",            [24]),
    ("两天 1 次",            [48]),
]
print(f"\n{'使用模式':<22s} {'次数':>4s} {'看家':>5s} {'上线':>5s} {'日收入':>7s}")
print("-"*72)
day_income={}
for name,segs in patterns:
    care=sum(care_coins(h) for h in segs)
    ci=sum(checkin(h) for h in segs)
    day_income[name]=(care+ci, len(segs))
    print(f"{name:<22s} {len(segs):4d} {care:5d} {ci:5d} {care+ci:7d}")

print()
print(" 全吃某档食物时的日结余：")
print(f"{'使用模式':<22s} {'收入':>5s} " + " ".join(f"{k:>8s}" for k in ('剩饭','普通粮','罐头','小鱼干')))
print("-"*72)
for name,(inc,n) in day_income.items():
    cells=[]
    for key in ('scraps','kibble','can','fish'):
        net = inc - PRICE[key]*n
        cells.append(f"{net:+8d}")
    print(f"{name:<22s} {inc:5d} " + " ".join(cells))

print()
print(" 说明：正数=有结余，负数=入不敷出（要么少喂，要么降档）")

print()
print("="*72)
print(" 四、极端与边界情况")
print("="*72)
cases = [
    ("刚关掉又打开 (10分钟)",  care_coins(1/6) + checkin(1/6),  "不足0.5h不结算，不足5h无上线奖励"),
    ("间隔 29 分钟",           care_coins(0.48) + checkin(0.48), "刚好卡在结算门槛下"),
    ("间隔 31 分钟",           care_coins(0.52) + checkin(0.52), "刚过门槛"),
    ("间隔 4h59m",             care_coins(4.98) + checkin(4.98), "上线奖励差一点"),
    ("间隔 5h",                care_coins(5.0)  + checkin(5.0),  "上线奖励到手"),
    ("离线 10h (峰值)",        care_coins(10)   + checkin(10),   "时长上限"),
    ("离线 100h",              care_coins(100)  + checkin(100),  "状态烂到底"),
    ("离线 1 年",              care_coins(8760) + checkin(8760), "防暴富上限生效"),
]
print(f"\n{'场景':<22s} {'收益':>5s}  说明")
print("-"*72)
for name,coins,note in cases:
    print(f"{name:<22s} {coins:5d}  {note}")

print()
print(" 刷币可行性检查（每 5 小时开一次是最优策略）：")
best_per_day = max(sum(care_coins(h)+checkin(h) for h in [24/n]*n) for n in range(1,25))
print(f"   理论日收益上限 = {best_per_day} 枚")
for n in (3,4,5,6,8,12,24):
    h=24/n
    tot=sum(care_coins(h)+checkin(h) for _ in range(n))
    print(f"   每 {h:4.1f}h 开一次 ({n:2d}次/天) = {tot:3d} 枚")
print("\n   → 频繁开关不会拿到更多（0.5h 门槛 + 5h 上线间隔已限制）")

print()
print("="*72)
print(" 五、小鱼干 buff 的实际回报")
print("="*72)
print("\n  32 枚买 24 小时 ×1.3 加成。按各使用模式算这 24h 多赚多少：")
print(f"\n{'使用模式':<22s} {'无buff':>7s} {'有buff':>7s} {'净赚':>6s} {'回本':>6s}")
print("-"*72)
for name,segs in patterns:
    plain=sum(care_coins(h) for h in segs)
    boost=sum(care_coins(h, boost=True) for h in segs)
    diff=boost-plain
    print(f"{name:<22s} {plain:7d} {boost:7d} {diff:+6d} {'是' if diff>=32 else '否':>6s}")
print("\n  → 单看 buff 收益不回本（刻意设计）。它的价值在心情+25% 带来的")
print("     系数提升，以及「经营选择」而非最优解。")
