#!/usr/bin/env python3
"""
从 LPC 成年帧派生四个生命阶段的 sprite sheet。

阶段与做法（全部程序化，不手绘）：
  young  幼年   躯干抽 4 行 → 头身比变大（幼体特征）
  growing 成长期 躯干抽 2 行
  adult  成年   原图不变
  elder  老年   躯干抽 1 行（背部下沉）+ 向灰色混 32%（褪色）

为什么抽行而不是整体缩放：
  整体缩放会让头也变小，看起来只是「同一只宠物远了一点」，
  而真正的幼体特征是**头身比更大**。抽躯干行能保留头部尺寸。

⚠️ 上一次做 sleep 帧时试过几何变形并失败（躯干被切断），
   所以这里的抽行规则很保守：
   1. 只在「躯干区」抽 —— 从最宽行往下、且保底留 3 行给脚
   2. 抽行后底边对齐 y=26（与成年帧一致），否则宠物会悬空
   3. 生成后逐行扫 alpha 校验轮廓连续，有断裂就报错

输出：Assets/pets/<name>_<stage>.png，与源图同布局（16 列 × 8 行）。
adult 不生成文件，直接用源图。
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from pnglib import load, save, px, setpx

# 布局默认值 = LPC「Cats and Dogs」。
# 布局不同的素材用 --cell/--cols/--rows/--foot-y 覆盖 ——
# Swift 侧对应 PetSheetLayout（见 Sources/Models/PetSheetLayout.swift），
# 两边要一致，否则派生帧的脚底对不上 footPadding。
CELL = 32
COLS = 16
ROWS = 8
FOOT_Y = 26          # 成年帧的脚底行，所有阶段对齐到这里

# 每个阶段：抽多少躯干行、灰度混合比例
#
# ⚠️ 幅度调过一次：最初 drop=4/2/1，实际差异只有 2-4px，
# 在 pixelScale=4 下肉眼几乎不可辨。现在加到 6/3/1，
# 并配合 PetStage.bodyScale 做整体缩放（见 Swift 侧），
# 双管才能让四个阶段一眼看出区别。
STAGES = {
    "young":   dict(drop=6, gray=0.0),
    "growing": dict(drop=3, gray=0.0),
    "elder":   dict(drop=1, gray=0.34),
}


def cell_of(buf, w, col, row):
    """取出一格 32×32"""
    return [[px(buf, w, col * CELL + x, row * CELL + y) for x in range(CELL)]
            for y in range(CELL)]


def occupied_rows(grid):
    return [y for y in range(CELL) if any(grid[y][x][3] > 8 for x in range(CELL))]


def row_widths(grid, ys):
    return [sum(1 for x in range(CELL) if grid[y][x][3] > 8) for y in ys]


def torso_zone(grid):
    """
    躯干可抽区间 [lo, hi]（绝对行号）。

    规则：从最宽行（躯干中心）开始往下，到「保底留 3 行给脚」为止。
    避开头/颈过渡行和脚部 —— 那里抽行会破坏轮廓。
    """
    ys = occupied_rows(grid)
    if len(ys) < 8:
        return None
    ws = row_widths(grid, ys)
    peak_i = ws.index(max(ws))
    lo = ys[peak_i]
    hi = ys[max(peak_i, len(ys) - 3)]      # 底部保留 2 行
    if hi <= lo:
        return None
    return lo, hi


def droppable_count(grid, count):
    """该帧最多能抽几行（不实际抽）。躯干区至少留 1 行。"""
    zone = torso_zone(grid)
    if not zone:
        return 0
    lo, hi = zone
    return max(0, min(count, hi - lo))


def pick_drop_rows(grid, count):
    """
    在躯干区里均匀选 count 行来抽。

    ⚠️ **`count` 必须由调用方按整个动画循环统一决定**，见 `build()`。

    两次踩坑都记在这里：

    1. 最初 `span <= count` 时直接返回空集 —— 走路第 4 帧是抬腿姿态，
       躯干区恰好只有 6 行，young 要抽 6 行就一行没抽，该帧原样保留
       成年尺寸（面积 252 vs 其余帧 164）。走路每循环到第 4 帧就胀大，
       表现为「一闪一闪」。

    2. 改成「各帧独立降级抽 span-1 行」后，同一循环里各帧躯干区宽度不同
       （进食行是 7/6/5/4），抽的行数就不同，派生后体型依然不齐。

    所以正解是：**同一循环所有帧抽相同行数**，取该循环的最小可抽数。
    """
    zone = torso_zone(grid)
    if not zone or count <= 0:
        return set()
    lo, hi = zone
    span = hi - lo + 1
    n = min(count, span - 1)
    if n <= 0:
        return set()

    # 均匀取样，避开区间端点（端点是过渡行）
    step = span / (n + 1)
    return {int(lo + step * (i + 1)) for i in range(n)}


def transform(grid, drop_count, gray):
    """抽行 + 可选褪色，底边对齐 FOOT_Y"""
    if not occupied_rows(grid):
        return grid                     # 空格子原样返回

    drop = pick_drop_rows(grid, drop_count)
    kept = [y for y in occupied_rows(grid) if y not in drop]
    if not kept:
        return grid

    out = [[(0, 0, 0, 0)] * CELL for _ in range(CELL)]
    start = FOOT_Y - len(kept) + 1
    for i, sy in enumerate(kept):
        ty = start + i
        if not (0 <= ty < CELL):
            continue
        if gray <= 0:
            out[ty] = list(grid[sy])
            continue
        row = []
        for p in grid[sy]:
            if p[3] <= 8:
                row.append(p)
                continue
            r, g, b, a = p
            lum = (r * 299 + g * 587 + b * 114) // 1000
            k = 1 - gray
            row.append((int(r * k + lum * gray),
                        int(g * k + lum * gray),
                        int(b * k + lum * gray), a))
        out[ty] = row
    return out


def verify(grid, label):
    """轮廓连续性校验：内容区间里不该有空行"""
    ys = occupied_rows(grid)
    if not ys:
        return True                     # 空格子合法
    gaps = [y for y in range(ys[0], ys[-1] + 1)
            if not any(grid[y][x][3] > 8 for x in range(CELL))]
    if gaps:
        print(f"    ✗ {label} 轮廓断裂，空行={gaps}")
        return False
    return True


def verify_cycle(cells, src_cells, label):
    """
    走路循环的帧间一致性校验。

    ⚠️ **这条是为了防「一闪一闪」回归。**

    同一动画循环里各帧的体型必须接近。曾经 young 的第 4 帧（抬腿姿态，
    躯干区只有 6 行）因为 `span <= count` 被跳过抽行，原样保留成年尺寸 ——
    面积 252 vs 其余帧 164，大了 54%，播放到该帧时宠物突然胀大。

    判据用**不透明像素面积**而不是内容行数：
    实测那次事故里行数比值只有 1.14（13/14/13 → 16），
    用行数配 1.15 阈值恰好漏掉；面积比值是 1.54，信号清晰得多。

    而且比的是「该帧 vs **其余帧**均值」，不是含它自己的总均值 ——
    把异常值算进基准会稀释掉它自己的偏差。

    只查上界：抬腿帧本该更小，偏小是正常的。

    ⚠️ 判据是**相对源图**的，不是绝对阈值。LPC 源素材本身帧间就有差异
    （dog r0c0 比其余帧大 10.6%），用绝对阈值会把正常素材判成缺陷。
    真正该拦的是「派生后比源图更不一致」。
    """
    def frame_areas(cs):
        return [sum(1 for y in range(CELL) for x in range(CELL) if c[y][x][3] > 8)
                for c in cs]

    def worst_ratio(areas):
        """最大的「某帧 / 其余帧均值」比值"""
        worst, idx = 0.0, -1
        for i, a in enumerate(areas):
            others = [v for j, v in enumerate(areas) if j != i and v > 0]
            if not others or a == 0:
                continue
            r = a / (sum(others) / len(others))
            if r > worst:
                worst, idx = r, i
        return worst, idx

    derived = frame_areas(cells)
    if len([a for a in derived if a > 0]) < 2:
        return True

    src_worst, _ = worst_ratio(frame_areas(src_cells)) if src_cells else (1.0, -1)
    got_worst, got_i = worst_ratio(derived)

    # 允许比源图差一点（抽行本身会引入少量不均），但不能明显更差
    limit = max(src_worst * 1.05, 1.12)
    if got_worst > limit:
        print(f"    ✗ {label} c{got_i} 体型突变：面积 {derived[got_i]}，"
              f"帧间比值 {got_worst:.2f} > 允许 {limit:.2f}（源图 {src_worst:.2f}）")
        print(f"      -> 走路播到这帧会「胀大一下」，"
              f"检查 pick_drop_rows 的降级逻辑")
        return False
    return True


def build(name, stage, cfg):
    src = f"Assets/pets/{name}.png"
    w, h, buf = load(src)
    ow, oh = COLS * CELL, ROWS * CELL
    out = bytearray(ow * oh * 4)

    ok = True
    for row in range(ROWS):
        # 每 4 列是一个完整动画循环（横向重复 4 次 = 4 种毛色）。
        # ⚠️ 同一循环必须抽【相同行数】，否则帧间体型不齐 -> 走路时忽大忽小。
        # 所以先扫一遍该循环各帧能抽多少，取最小值统一使用。
        for base in range(0, COLS, 4):
            src_cycle = [cell_of(buf, w, base + i, row) for i in range(4)]
            drops = [droppable_count(g, cfg["drop"]) for g in src_cycle
                     if occupied_rows(g)]
            uniform = min(drops) if drops else 0

            cycle = []
            for i, g in enumerate(src_cycle):
                col = base + i
                t = transform(g, uniform, cfg["gray"])
                if not verify(t, f"{name}_{stage} r{row}c{col}"):
                    ok = False
                cycle.append(t)
                for y in range(CELL):
                    for x in range(CELL):
                        setpx(out, ow, col * CELL + x, row * CELL + y, t[y][x])

            if not verify_cycle(cycle, src_cycle,
                                f"{name}_{stage} r{row}c{base}..{base+3}"):
                ok = False

    dst = f"Assets/pets/{name}_{stage}.png"
    save(dst, ow, oh, out)
    size = os.path.getsize(dst)
    # 报告高度变化（用 r0c0 侧视帧）
    g0 = cell_of(buf, w, 0, 0)
    t0 = transform(g0, cfg["drop"], cfg["gray"])
    h0 = occupied_rows(g0)
    h1 = occupied_rows(t0)
    print(f"  {dst}  {size/1024:.1f} KB  "
          f"侧视高 {len(h0)}→{len(h1)} px  {'✅' if ok else '⚠️ 有断裂'}")
    return ok


def main():
    global CELL, COLS, ROWS, FOOT_Y

    ap = argparse.ArgumentParser()
    ap.add_argument("--pets", nargs="*", default=["cat", "dog"])
    ap.add_argument("--cell", type=int, default=CELL,
                    help="单格边长（源像素），默认 32")
    ap.add_argument("--cols", type=int, default=COLS,
                    help="sheet 总列数，默认 16")
    ap.add_argument("--rows", type=int, default=ROWS,
                    help="sheet 总行数，默认 8")
    ap.add_argument("--foot-y", type=int, default=FOOT_Y,
                    help="成年帧脚底行，默认 26")
    args = ap.parse_args()

    # 覆盖模块级常量 —— build/pick_drop_rows 都读它们
    CELL, COLS, ROWS, FOOT_Y = args.cell, args.cols, args.rows, args.foot_y
    if (CELL, COLS, ROWS, FOOT_Y) != (32, 16, 8, 26):
        print(f"⚠️  非默认布局：cell={CELL} cols={COLS} rows={ROWS} foot_y={FOOT_Y}")
        print("   记得 Swift 侧 PetSheetLayout 用同样的值。")

    all_ok = True
    for name in args.pets:
        print(f"\n=== {name} ===")
        for stage, cfg in STAGES.items():
            if not build(name, stage, cfg):
                all_ok = False
    print()
    print("adult 阶段直接用源图，不生成文件。")
    if not all_ok:
        sys.exit("有帧轮廓断裂，需调整抽行规则")


if __name__ == "__main__":
    main()
