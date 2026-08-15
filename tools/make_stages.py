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


def pick_drop_rows(grid, count):
    """在躯干区里均匀选 count 行来抽"""
    zone = torso_zone(grid)
    if not zone:
        return set()
    lo, hi = zone
    span = hi - lo + 1
    if span <= count:
        return set()
    # 均匀取样，避开区间端点（端点是过渡行）
    step = span / (count + 1)
    return {int(lo + step * (i + 1)) for i in range(count)}


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


def build(name, stage, cfg):
    src = f"Assets/pets/{name}.png"
    w, h, buf = load(src)
    ow, oh = COLS * CELL, ROWS * CELL
    out = bytearray(ow * oh * 4)

    ok = True
    for row in range(ROWS):
        for col in range(COLS):
            g = cell_of(buf, w, col, row)
            t = transform(g, cfg["drop"], cfg["gray"])
            if not verify(t, f"{name}_{stage} r{row}c{col}"):
                ok = False
            for y in range(CELL):
                for x in range(CELL):
                    setpx(out, ow, col * CELL + x, row * CELL + y, t[y][x])

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
    ap = argparse.ArgumentParser()
    ap.add_argument("--pets", nargs="*", default=["cat", "dog"])
    args = ap.parse_args()

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
