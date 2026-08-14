"""
生成 App 图标 1024×1024。

素材来源：Assets/pets/cat.png 的侧视帧（实际下载到的文件）。
⚠️ 不使用 OGA 页面预览图 —— OGA FAQ 明确「assume the previews are
'All rights reserved'」，预览图不在授权范围内。

做法：取侧视朝右帧，最近邻整数倍放大，配圆角背景 + 地面色带。
"""
import sys
sys.path.insert(0, 'tools')
from pnglib import load, save, px, setpx

SIZE = 1024
CELL = 32

def build():
    w, h, d = load('Assets/pets/cat.png')

    out = bytearray(SIZE * SIZE * 4)

    # 背景：上下渐变（墙色 -> 地板色），和 app 内房间呼应
    wall_top = (72, 82, 118)
    wall_bot = (58, 64, 96)
    floor    = (115, 87, 69)
    floor_y  = int(SIZE * 0.74)

    for y in range(SIZE):
        if y < floor_y:
            t = y / floor_y
            c = tuple(int(wall_top[i] + (wall_bot[i] - wall_top[i]) * t) for i in range(3))
        else:
            c = floor
        for x in range(SIZE):
            setpx(out, SIZE, x, y, c + (255,))

    # 踢脚线
    for y in range(floor_y - 8, floor_y):
        for x in range(SIZE):
            setpx(out, SIZE, x, y, (40, 32, 28, 255))

    # 宠物：侧视帧 0，放大到占画面约 62%
    zoom = 20                      # 32 * 20 = 640
    px_w = CELL * zoom
    ox = (SIZE - px_w) // 2
    # 让脚正好落在地板线上。源图脚底在 y=26（含），
    # 所以第 27 行的顶边要对齐 floor_y。
    FOOT_ROW = 27
    oy = floor_y - FOOT_ROW * zoom

    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = px(d, w, x, y)
            if a < 8:
                continue
            for dy in range(zoom):
                for dx in range(zoom):
                    tx, ty = ox + x*zoom + dx, oy + y*zoom + dy
                    if 0 <= tx < SIZE and 0 <= ty < SIZE:
                        setpx(out, SIZE, tx, ty, (r, g, b, 255))

    save('Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png', SIZE, SIZE, out)
    print("wrote icon_1024.png")

build()
