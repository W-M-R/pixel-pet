#!/usr/bin/env python3
"""
视觉断言：截图 + 扫像素，自动判定布局对不对。

## 为什么需要这层

吃饭站位这件事改了六轮才对，每轮都是「改一个猜测 → 看截图」。
截图只能告诉我「不对」，说不出「差多少、差在哪一步」。
而且 SpriteKit 场景对 XCUI 是**黑盒** —— 宠物、家具、碗都在
一个 SpriteView 里，XCUI 只看到一个容器，断言不了里面的位置。

## ⚠️ 颜色判定必须从素材取，不能靠「看起来是蓝的」猜

第一版我写了 `is_bowl_blue(r,g,b): b > r+25 ...`，理由是
「碗看起来是蓝的」。结果它匹配到**窗户的夜空**（35,48,91）——
那个每个场景都在同一位置，所以三个不同场景给出**完全相同**的
外接框和像素数（148662），而我还以为断言通过了。

真相是碗根本不是蓝的：`furniture.png` 格 1（`FurnitureItem.bowl`
的 `sheetIndex=1`）的调色板是**红棕系**。

所以这个脚本的所有颜色都从素材文件里**精确提取**，
并且验证过与其它素材零冲突（见 PALETTES 的注释）。
"""
import argparse
import glob
import os
import subprocess
import sys
import time

BUNDLE = "com.wmr.pixelpet"
PROBE = ".probe/visual"
ASSETS = "Assets"


# ---------------------------------------------------------------- 调色板

def _palette(path, x0=0, x1=None):
    """从 PNG 里提取不透明像素的颜色集合。"""
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    px = im.load()
    W, H = im.size
    x1 = W if x1 is None else x1
    out = set()
    for y in range(H):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a > 0:
                out.add((r, g, b))
    return out


def load_palettes():
    """
    取出各类物体的专属颜色。

    实测冲突情况（tools 里跑过对比）：
      碗的红棕系 与 icons/emotes/house_objects/cat/dog **零冲突**
      宠物的 22 色 与 房间/UI 素材 **零冲突**
    所以这两组都能当可靠锚点。
    """
    furn = os.path.join(ASSETS, "room", "furniture.png")
    # ⚠️ **格位宽度是 cell×2 = 64px，不是 cell。**
    #
    # 见 `RoomSpriteSheet.furnitureTexture`：`let slot = cell * 2`，
    # 取图用 `x = index * slot`。所以 sheetIndex=1 的碗在 x 64..96，
    # 而不是 32..64。
    #
    # 我第一版按 16px 一格取，拿到的是**床的布料红色**，
    # 于是「碗」在三个不同场景里都定位到同一个地方（床或窗）。
    bowl = _palette(furn, 64, 96)
    # 去掉全场共用的描边色，和碗里的食物色（喂食后才出现，会让框变大）
    shared = {(48, 32, 24)}
    food = {(240, 218, 164), (206, 172, 110)}
    bowl_only = bowl - shared - food

    # ⚠️ **必须收全部宠物素材**，不只 cat.png / dog.png。
    #
    # 屏幕上渲染的可能是睡姿帧（`*_sleep.png`）或某个生命阶段的
    # 派生帧（`*_young/growing/elder.png`，由 make_stages.py 生成，
    # 老年帧还向灰色混过 32%）。
    #
    # 我第一版只加载两张成年帧，结果两只宠物明明在屏幕上，
    # 检测器只找到 **1 个**像素 —— 因为它们正在睡觉。
    pets = set()
    for f in sorted(glob.glob(os.path.join(ASSETS, "pets", "*.png"))):
        pets |= _palette(f)

    # ⚠️ 有 4 个颜色必须剔掉 —— 它们同时出现在**墙裙木纹和按钮面板**上。
    #
    # 这 4 个来自 elder 帧：`make_stages.py` 给老年宠物混了 32% 灰，
    # 混出来的浅棕恰好和 UI 的木色系撞车。
    # 不剔的话「宠物压住按钮」这条会稳定误报 —— 我实测在 full-room
    # 场景拿到 5461 个命中，放大看全是墙裙和按钮边框。
    #
    # 剔掉后 elder 宠物少 4 个可识别色（还剩 40），
    # 对位置断言足够 —— 宠物身上不止这 4 个色。
    ui_collide = {
        (205, 182, 122),   # elder 灰化浅棕 ↔ 按钮面板高光
        (181, 152, 107),   # elder 灰化棕   ↔ 墙裙亮部
        (158, 121, 93),    # elder 灰化深棕 ↔ 按钮底色
        (56, 55, 55),      # elder 描边灰   ↔ 面板阴影
    }
    return {"bowl": bowl_only, "pet": pets - ui_collide}


PAL = None


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def shot(name):
    from PIL import Image
    os.makedirs(PROBE, exist_ok=True)
    p = os.path.join(PROBE, f"{name}.png")
    if os.path.exists(p):
        os.remove(p)
    sh(["xcrun", "simctl", "io", "booted", "screenshot", p])
    if not os.path.exists(p):
        sys.exit("截图失败，模拟器开着吗？")
    return Image.open(p).convert("RGB")


def relaunch(scene, wait=6.0):
    """
    注入存档 + 重启 app，并**确认它真的在前台**。

    ⚠️ `simctl launch` 返回成功不代表 app 到了前台 ——
    模拟器上别的 app 可能压在上面。我因此拿到过一张完全无关的
    截图（另一个 app 的界面），然后据此断言「碗不见了」。
    所以这里截完图要验证一下画面是不是这个 app 的。
    """
    sh(["xcrun", "simctl", "terminate", "booted", BUNDLE])
    r = sh(["python3", os.path.join("tools", "inject_save.py"),
            "--scene", scene])
    if r.returncode != 0:
        sys.exit(f"注入存档失败：{r.stderr}")
    sh(["xcrun", "simctl", "launch", "booted", BUNDLE])
    time.sleep(wait)


def maestro(commands, wait=0.0):
    """
    跑一小段 Maestro 流程来驱动交互。

    像素断言要检查「吃饭时围到碗边」，前提是**真的触发了喂食** ——
    只启动 app 是不会有人走向碗的（`triggerEat()` 才会派活）。
    我第一版漏了这步，量到的其实是宠物随机游荡的位置，
    于是同一套代码两次跑出 12/12 和 9/12。
    """
    import tempfile
    body = "appId: com.wmr.pixelpet\n---\n" + commands
    with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False) as f:
        f.write(body)
        path = f.name
    try:
        r = subprocess.run([os.path.expanduser("~/.maestro/bin/maestro"),
                            "test", path],
                           capture_output=True, text=True, timeout=180)
        if "FAILED" in r.stdout:
            print(r.stdout[-600:])
            sys.exit("Maestro 驱动失败")
    except subprocess.TimeoutExpired:
        sys.exit("Maestro 超时")
    finally:
        os.unlink(path)
    if wait:
        time.sleep(wait)


def feed_now():
    """
    点「喂食」→ 选「普通粮」，让所有宠物开始走向碗。

    用 accessibilityIdentifier 定位，不用文案 ——
    文案会随语言变，而「普通粮」那一行还带价格
    （实测 label 是「普通粮、约 6.3 小时、35」，价格随饱食度浮动）。
    id 见 `Sources/Core/Accessibility/A11y.swift`。
    """
    maestro('- tapOn:\n    id: "action.feed"\n'
            '- tapOn:\n    id: "food.kibble"\n')


def settle(name, colors, tries=14, interval=1.0, tol=6):
    """
    反复截图，等到目标物体**停止移动**再返回。

    宠物以 34pt/秒 走向碗，从屏幕一端过去要好几秒；而且中途
    可能被成就气泡挡住、可能刚被叫醒还在起身。
    固定 `sleep(6)` 抓到的是「正在路上」的一帧 —— 这就是
    我那两条断言忽绿忽红的原因。

    判据：质心连续两次的位移都在 tol 像素内，就认为稳定了。
    """
    prev = None
    stable = 0
    im = None
    for _ in range(tries):
        im = shot(name)
        p = find(im, colors, step=2)
        if p:
            cur = (p["cx"], p["cy"])
            if prev and abs(cur[0] - prev[0]) <= tol \
                    and abs(cur[1] - prev[1]) <= tol:
                stable += 1
                if stable >= 2:
                    return im
            else:
                stable = 0
            prev = cur
        time.sleep(interval)
    return im


def assert_our_app(im, scene):
    """
    确认截图确实是 PixelPet。

    判据：房间的墙色应当占据画面上半部相当大的比例。
    别的 app 不会长这样。

    ⚠️ **用容差匹配，不能用精确值。** `RoomPalette.wall` 是
    `RGB(0.85, 0.78, 0.68)` → 折算 (217,199,173)，
    但屏幕实测是 **(216,198,173)** —— 差 1。
    SpriteKit 渲染 + 屏幕色彩管线会带来 ±1 的偏移，
    我因此让这个校验误报过一次（明明 app 在前台，却说不是）。
    """
    px = im.load()
    W, H = im.size
    wall = [(216, 198, 173), (209, 192, 167)]
    n = 0
    for y in range(int(H * 0.10), int(H * 0.40), 4):
        for x in range(0, W, 4):
            r, g, b = px[x, y]
            if any(abs(r - wr) <= 2 and abs(g - wg) <= 2 and abs(b - wb) <= 2
                   for wr, wg, wb in wall):
                n += 1
    total = len(range(int(H * 0.10), int(H * 0.40), 4)) * len(range(0, W, 4))
    ratio = n / total if total else 0
    if ratio < 0.15:
        sys.exit(f"[{scene}] 截图不是 PixelPet 的界面"
                 f"（墙色只占 {ratio:.1%}）—— "
                 f"别的 app 在前台？看 {PROBE} 里的图")


# ---------------------------------------------------------------- 扫描

def find(im, colors, y0=0, y1=None, x0=0, x1=None, step=1):
    """
    找出属于 colors 的像素的外接框与质心。

    用**精确颜色集合**而非范围判定 —— 像素画的颜色是有限调色板，
    精确匹配比「r>x and b<y」这种范围条件可靠得多（后者会误吞背景）。
    """
    px = im.load()
    W, H = im.size
    y1 = H if y1 is None else y1
    x1 = W if x1 is None else x1
    minx, miny, maxx, maxy = W, H, -1, -1
    sx = sy = n = 0
    for y in range(y0, y1, step):
        for x in range(x0, x1, step):
            if px[x, y] in colors:
                n += 1
                sx += x
                sy += y
                if x < minx: minx = x
                if y < miny: miny = y
                if x > maxx: maxx = x
                if y > maxy: maxy = y
    if n == 0:
        return None
    return {"x0": minx, "y0": miny, "x1": maxx, "y1": maxy,
            "cx": sx // n, "cy": sy // n, "n": n}


RESULTS = []


def report(name, ok, detail):
    RESULTS.append((name, ok, detail))
    print(f"  {'OK ' if ok else 'BAD'} {name}: {detail}")


# ---------------------------------------------------------------- 检查项

def locate_bowl(im, label="认出碗", allow_occluded=False):
    """
    碗是所有位置断言的锚点，先确认能认出来。

    ⚠️ **碗可能被宠物挡住大半。** 宠物 z 序比碗高（碗 z=10.5，
    但宠物走到碗前方时会盖住它），实测 full-room 场景里
    一只猫正好站在碗前，只露出 61px（正常 161px）。
    那不是渲染错误，是正常遮挡。
    所以宽度只在「确定没有宠物挡着」时才严格要求，
    其余场景放宽到「能认出位置」即可。
    """
    H = im.size[1]
    # 只在地板区找（下半屏）—— 上半是墙，不该有家具
    b = find(im, PAL["bowl"], y0=int(H * 0.45))
    if not b or b["n"] < 300:
        report(label, False,
               f"地板区找不到碗（命中 {b['n'] if b else 0} 像素）")
        return None
    w = b["x1"] - b["x0"]
    # 碗身在 32px 格里只占约 18 源像素（不占满格），
    # × displayScale(3) × 屏幕缩放(3) ≈ 160px。实测 161px。
    lo = 110 if not allow_occluded else 45
    ok = lo < w < 240
    report(label, ok, f"x {b['x0']}..{b['x1']}（宽 {w}px，预期约 288）"
                      f" y {b['y0']}..{b['y1']}，{b['n']} 像素")
    return b if ok else None


# ⚠️ 这里曾有 `check_pets_gather_at_bowl` 和
# `check_pet_head_reaches_bowl` —— 已删，移到确定性层。
#
# 它们检查「喂食时宠物围到碗边」，而这件事**不适合用像素判定**：
#
#   1. 宠物以 34pt/秒 走过去，抓到哪一帧取决于时机
#   2. 宠物会挡住碗（实测碗只露 61px，正常 161px）
#   3. 成就气泡会盖住宠物
#   4. 没被派活的宠物在自由游荡，位置随机
#
# 我为此调了 5 轮阈值，每轮都冒出新的干扰源 ——
# 那是「方法不对」的信号，不是「参数没调好」。
#
# 排位公式本身已由 `BowlSlotLayoutTests` 确定性覆盖
# （左右对称 / 外圈更远 / 任意两只不重叠 / 嘴要对准碗）。
# 而「场景里真的按公式站好了」这件事，用 DEBUG 下导出的
# 布局快照来断言（见 PetScene.debugLayoutSnapshot 与
# PixelPetUITests），比数像素可靠得多。


# ⚠️ 这里曾有个 `check_pets_not_on_buttons` —— 已删。
#
# 它检查「宠物有没有走到操作栏上」，但这件事
# `FloorClearanceTests.testFloorClearsActionBar` 已经在几何层
# **确定性地**守住了（地板最近处必须在按钮顶边之上，纯算术）。
#
# 像素版反而不可靠：宠物走到哪由随机游荡决定，某一帧正好晃到
# 按钮附近就误报。我实测同一套代码两次跑出 0 和 2617 像素。
# 用不稳定的检查去重复一个确定性单测，比不做更糟 —— 只会制造噪音。


def check_bowl_at(im, bowl, expect_ratio, tol=0.16):
    """
    **碗要停在存档写的位置。**

    这是像素层最值得做的检查 —— 它验证的是
    「存档 → 解码 → 摆位」这条链路真的走通了，
    而这条链路曾经断过（`Slot` 的合成 Codable 缺 depth 就整份失败，
    静默退回 `.default`，玩家摆好的布局无声重置）。

    容差给得宽（±0.16）是因为宠物可能挡住碗的一侧，
    让质心偏移 —— 实测同一场景测到 0.69 和 0.75。
    但「被重置」的偏差是 0.35→0.22 这个量级，照样能抓到。
    """
    W = im.size[0]
    ratio = bowl["cx"] / W
    ok = abs(ratio - expect_ratio) < tol
    report(f"碗停在 {expect_ratio}", ok,
           f"实测 x={ratio:.2f}（容差 ±{tol}）")


def check_bowl_grounded(im, bowl):
    """
    **碗要贴地。**

    碗正下方一小段应该是地板色，不是墙色。
    墙比地板浅，用亮度区分。
    """
    px = im.load()
    H = im.size[1]
    y = min(H - 1, bowl["y1"] + 8)
    r, g, b = px[bowl["cx"], y]
    ok = r < 200
    report("碗贴着地板", ok,
           f"碗底下方 RGB=({r},{g},{b})，地板应偏暗（r<200）")


def check_legacy_layout_kept(im):
    """
    **旧存档的家具位置不该被重置。**

    legacy-room 写的是没有 depth 字段的旧格式，碗在 xRatio=0.7。
    如果 `Slot` 解码失败退回 `.default`，碗会跑到 0.22 ——
    那就是那个真 bug 复现了（合成 Codable 对有默认值的属性
    仍要求 key 存在，缺 depth 抛 keyNotFound）。
    """
    W, H = im.size
    b = find(im, PAL["bowl"], y0=int(H * 0.45))
    if not b or b["n"] < 300:
        report("旧存档布局保住", False, "找不到碗")
        return
    ratio = b["cx"] / W
    ok = abs(ratio - 0.70) < 0.16
    report("旧存档布局保住", ok,
           f"碗心在 x={ratio:.2f}（存档 0.70；退回默认会是 0.22）")


# ---------------------------------------------------------------- 场景

def run_eating():
    print("\n[bowl-two-pets] 碗摆在 0.35，喂食后碗该还在原位")
    relaunch("bowl-two-pets")
    im = shot("eating-before")
    assert_our_app(im, "bowl-two-pets")
    feed_now()
    im = settle("eating", PAL["bowl"])
    bowl = locate_bowl(im, allow_occluded=True)
    if bowl:
        check_bowl_at(im, bowl, 0.35)
        check_bowl_grounded(im, bowl)


def run_three():
    print("\n[bowl-three-pets] 碗摆在 0.5，三只宠物不该把它挤走")
    relaunch("bowl-three-pets")
    im = shot("three-before")
    assert_our_app(im, "bowl-three-pets")
    feed_now()
    im = settle("three", PAL["bowl"])
    bowl = locate_bowl(im, allow_occluded=True)
    if bowl:
        check_bowl_at(im, bowl, 0.50)


def run_full_room():
    print("\n[full-room] 全部家具 + 两只")
    relaunch("full-room")
    im = shot("full-room")
    assert_our_app(im, "full-room")
    # 这个场景宠物在自由游荡，可能正好站在碗前面
    bowl = locate_bowl(im, allow_occluded=True)
    if bowl:
        check_bowl_at(im, bowl, 0.55)
        check_bowl_grounded(im, bowl)


def run_legacy():
    print("\n[legacy-room] 旧格式 room.json（没有 depth）")
    relaunch("legacy-room")
    im = shot("legacy")
    assert_our_app(im, "legacy-room")
    check_legacy_layout_kept(im)


CHECKS = {
    "eating": run_eating,
    "three": run_three,
    "full-room": run_full_room,
    "legacy": run_legacy,
}


def main():
    global PAL
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", default="all",
                    choices=["all"] + sorted(CHECKS))
    a = ap.parse_args()

    PAL = load_palettes()
    print(f"调色板：碗 {len(PAL['bowl'])} 色，宠物 {len(PAL['pet'])} 色")

    for k in (sorted(CHECKS) if a.check == "all" else [a.check]):
        CHECKS[k]()

    bad = [r for r in RESULTS if not r[1]]
    print("\n" + "=" * 56)
    print(f"通过 {len(RESULTS) - len(bad)}/{len(RESULTS)}")
    if bad:
        for n, _, d in bad:
            print(f"  BAD {n} — {d}")
        sys.exit(1)
    print("视觉断言全部通过")


if __name__ == "__main__":
    main()
