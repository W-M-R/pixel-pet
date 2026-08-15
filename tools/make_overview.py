#!/usr/bin/env python3
"""
生成「全宠物 × 全阶段」总览图，供肉眼验收。

两张图：
  overview-stages.png  每个宠物的 4 阶段 × 4 毛色（侧视静态帧）
  overview-anim.png    每个宠物 × 每阶段的 walk 4 帧（看动画连续性）
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from pnglib import load, save, px, setpx

CELL = 32
# (id, 标签, bodyScale) —— bodyScale 必须与 Swift 侧 PetStage.bodyScale 一致
STAGES = [("young", "YOUNG", 0.75), ("growing", "GROWING", 0.875),
          ("adult", "ADULT", 1.0), ("elder", "ELDER", 0.94)]
PETS = ["cat", "dog"]
BG = (176, 192, 164, 255)
HOLE = (162, 178, 150, 255)


def sheet(pet, stage):
    p = f"Assets/pets/{pet}.png" if stage == "adult" else f"Assets/pets/{pet}_{stage}.png"
    return load(p)


def blit(out, ow, buf, bw, scol, srow, ox, oy, z, body=1.0):
    """body = 生命阶段体型缩放，底部对齐（脚踩同一条线）"""
    zz = z * body
    cell_px = int(CELL * z)
    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = px(buf, bw, scol * CELL + x, srow * CELL + y)
            if a <= 8:
                continue
            for dy in range(int(zz) + 1):
                for dx in range(int(zz) + 1):
                    tx = ox + int(x * zz) + dx + int(cell_px * (1 - body) / 2)
                    ty = oy + int(y * zz) + dy + int(cell_px * (1 - body))
                    setpx(out, ow, tx, ty, (r, g, b, 255))


def build_stages():
    """4 毛色 × (2 宠物 × 4 阶段)"""
    Z, PAD = 5, 6
    cols, rows = 4, len(PETS) * len(STAGES)
    ow = cols * (CELL * Z + PAD) + PAD
    oh = rows * (CELL * Z + PAD) + PAD
    out = bytearray(BG * (ow * oh))
    r = 0
    for pet in PETS:
        for stage, _, body in STAGES:
            w, h, d = sheet(pet, stage)
            for color in range(4):
                blit(out, ow, d, w, color * 4, 0,
                     PAD + color * (CELL * Z + PAD),
                     PAD + r * (CELL * Z + PAD), Z, body)
            r += 1
    save(".probe/overview-stages.png", ow, oh, out)
    print(f"  .probe/overview-stages.png  {ow}x{oh}")
    print("    行(上→下): " + " / ".join(f"{p} {s[1]}" for p in PETS for s in STAGES))
    print("    列(左→右): 毛色1..4")


def build_anim():
    """每行 = 一个宠物的一个阶段的 walk 4 帧（第一个毛色）"""
    Z, PAD = 5, 6
    cols, rows = 4, len(PETS) * len(STAGES)
    ow = cols * (CELL * Z + PAD) + PAD
    oh = rows * (CELL * Z + PAD) + PAD
    out = bytearray(BG * (ow * oh))
    r = 0
    for pet in PETS:
        for stage, _, body in STAGES:
            w, h, d = sheet(pet, stage)
            for f in range(4):
                blit(out, ow, d, w, f, 0,
                     PAD + f * (CELL * Z + PAD),
                     PAD + r * (CELL * Z + PAD), Z, body)
            r += 1
    save(".probe/overview-anim.png", ow, oh, out)
    print(f"  .probe/overview-anim.png  {ow}x{oh}")
    print("    行同上，列 = walk 帧 0..3")


if __name__ == "__main__":
    os.makedirs(".probe", exist_ok=True)
    print("生成总览图:")
    build_stages()
    build_anim()
