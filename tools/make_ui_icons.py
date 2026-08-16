"""
生成 UI 像素图标 sheet。

**为什么自绘**：现有 Assets/ui/emotes.png (Tomcat94, CC0) 里只有抽象符号
（心/音符/水滴/感叹号），没有食物、球、浴缸这类具体道具图标 ——
见 RoomSpriteSheet.swift 的注释。而 UI 里原来一律用 Apple emoji，
emoji 自带高光渐变，紧贴像素猫时把像素感彻底压掉。

自绘的另一个好处是零授权负担：形状原创，配色取自 PixelStyle 的木色体系。

图标 16×16，横向排列。尺寸取 16 而非 12，因为 UI 里要显示到 24-32pt，
16px 在 2 倍整数放大下正好 32pt。

输出 Assets/ui/icons.png
"""
import sys
sys.path.insert(0, 'tools')
from pnglib import save, setpx

CELL = 16

# 调色板。键是图例字符，值是 RGBA。
# 与 Sources/Views/PixelStyle.swift 的配色保持一致。
PAL = {
    '.': (0, 0, 0, 0),
    # 通用描边（比任何填充色都暗，保证轮廓清晰）
    'K': (38, 26, 20, 255),
    # 肉/食物
    'm': (196, 88, 72, 255),      # 肉红
    'M': (232, 128, 104, 255),    # 肉红亮
    'b': (168, 124, 84, 255),     # 骨/褐
    'B': (232, 208, 170, 255),    # 骨白
    # 碗/罐
    'g': (110, 100, 96, 255),     # 灰
    'G': (158, 148, 142, 255),    # 灰亮
    'w': (152, 116, 80, 255),     # 木
    'W': (198, 158, 114, 255),    # 木亮
    # 球
    'r': (206, 78, 74, 255),      # 球红
    'R': (240, 130, 120, 255),
    'c': (86, 154, 168, 255),     # 球青
    'C': (140, 200, 210, 255),
    # 水
    'a': (92, 158, 186, 255),     # 水蓝
    'A': (150, 208, 228, 255),
    # 金币
    'o': (196, 148, 44, 255),     # 金暗
    'O': (246, 208, 96, 255),     # 金亮
    'y': (255, 240, 180, 255),    # 金高光
    # 鱼
    'f': (128, 148, 168, 255),    # 鱼身
    'F': (186, 204, 220, 255),
    # 谷物
    'n': (206, 172, 110, 255),
    'N': (240, 218, 164, 255),
    # 心
    'h': (198, 74, 96, 255),
    'H': (240, 130, 148, 255),
    # 星（成就）
    's': (200, 156, 40, 255),
    'S': (250, 214, 110, 255),
    # 爪印（宠物入口）—— 取猫毛的橙褐，和 LPC 素材同色系
    'p': (170, 112, 70, 255),
    'P': (214, 156, 106, 255),
    # 商店（雨棚条纹）
    't': (176, 74, 68, 255),      # 棚红
    'T': (226, 118, 108, 255),
}

# 每个图标 16 行 × 16 列
ICONS = {}

# 肉（喂食按钮）—— 带骨头的肉排
ICONS['meat'] = [
    "................",
    "................",
    "......KKKK......",
    ".....KmmmmK.....",
    "....KmMMmmmK....",
    "...KmMMmmmmmK...",
    "..KmmMmmmmmmmK..",
    "..KmmmmmmmmmmK..",
    "..KmmmmmmmmmmK..",
    "...KmmmmmmmmK...",
    "..KBKmmmmmmKBK..",
    ".KBBBKmmmmKBBBK.",
    ".KBbbBKmmKBbbBK.",
    "..KBBBKKKKBBBK..",
    "...KKK....KKK...",
    "................",
]

# 球（玩耍按钮）
ICONS['ball'] = [
    "................",
    "................",
    "....KKKKKKKK....",
    "..KKrrrrKcccKK..",
    ".KrrRRrrKcCCCcK.",
    ".KrRRrrrKcCCCcK.",
    "KrRrrrrrKccCCCcK",
    "KrrrrrrrKcCCCCcK",
    "KrrrrrrrKcCCCCcK",
    "KrrrrrrrKcCCCCcK",
    ".KrrrrrrKcCCCcK.",
    ".KrrrrrrKcCCCcK.",
    "..KKrrrrKcccKK..",
    "....KKKKKKKK....",
    "................",
    "................",
]

# 水滴（洗澡按钮）
ICONS['bath'] = [
    "................",
    ".......KK.......",
    ".......KK.......",
    "......KaaK......",
    "......KaaK......",
    ".....KaAaaK.....",
    ".....KaAaaK.....",
    "....KaaAaaaK....",
    "....KaAAaaaK....",
    "...KaaAAaaaaK...",
    "...KaaAaaaaaK...",
    "...KaaaaaaaaK...",
    "....KaaaaaaK....",
    ".....KaaaaK.....",
    "......KKKK......",
    "................",
]

# 金币
ICONS['coin'] = [
    "................",
    "................",
    "....KKKKKKKK....",
    "..KKooooooooKK..",
    ".KoOOOOOOOOOOoK.",
    ".KoOyyOOOOOOOoK.",
    "KoOyyOOOOOOOOoK.",
    "KoOyOOOOOOOOOoK.",
    "KoOOOOOOOOOOOoK.",
    "KoOOOOOOOOOOOoK.",
    ".KoOOOOOOOOOOoK.",
    ".KooOOOOOOOOooK.",
    "..KKooooooooKK..",
    "....KKKKKKKK....",
    "................",
    "................",
]

# 碗（剩饭）
ICONS['scraps'] = [
    "................",
    "................",
    "................",
    "................",
    "....nnn..nn.....",
    "...nNnnnnnn.....",
    "..KKKKKKKKKKKK..",
    ".KgGGGGGGGGGGgK.",
    ".KgGgggggggggGK.",
    "..KggggggggggK..",
    "...KgggggggggK..",
    "....KKggggKK....",
    "......KKKK......",
    "................",
    "................",
    "................",
]

# 谷物袋（普通粮）
ICONS['kibble'] = [
    "................",
    "................",
    "....KKKKKKK.....",
    "...KwWWWWWwK....",
    "...KwWnnnNWwK...",
    "..KwWnNnnnnWwK..",
    "..KwWnnnnnnNwK..",
    "..KwWnNnnnNnwK..",
    "..KwWnnnnnnnwK..",
    "..KwWnnNnnnnwK..",
    "..KwWnnnnnNnwK..",
    "..KwwWnnnnnwwK..",
    "..KKwwwwwwwwKK..",
    "....KKKKKKKK....",
    "................",
    "................",
]

# 罐头
ICONS['can'] = [
    "................",
    "................",
    "...KKKKKKKKKK...",
    "..KGGGGGGGGGGK..",
    "..KgGGGGGGGGgK..",
    "..KgKKKKKKKKgK..",
    "..KgGmmmmmmGgK..",
    "..KgGmMMmmmGgK..",
    "..KgGmmmmmmGgK..",
    "..KgGmmmmmmGgK..",
    "..KgKKKKKKKKgK..",
    "..KgGGGGGGGGgK..",
    "..KggggggggggK..",
    "...KKKKKKKKKK...",
    "................",
    "................",
]

# 小鱼干
ICONS['fish'] = [
    "................",
    "................",
    "................",
    "...........KK...",
    "....KKKKK.KffK..",
    "..KKfFFFFKfffK..",
    ".KfFFFFFFFffffK.",
    "KfFFKFFFFFfffffK",
    "KfFFFFFFFFFffffK",
    ".KfFFFFFFFffffK.",
    "..KKfFFFFKfffK..",
    "....KKKKK.KffK..",
    "...........KK...",
    "................",
    "................",
    "................",
]

# 心（成就·陪伴）
ICONS['heart'] = [
    "................",
    "................",
    "...KKK....KKK...",
    "..KhhhKKKhhhK...",
    ".KhHHhhhhhhhhK..",
    ".KhHHhhhhhhhhK..",
    ".KhHhhhhhhhhhK..",
    ".KhhhhhhhhhhhK..",
    "..KhhhhhhhhhK...",
    "...KhhhhhhhK....",
    "....KhhhhhK.....",
    ".....KhhhK......",
    "......KhK.......",
    ".......K........",
    "................",
    "................",
]

# 星（成就）
# 钱堆（收益明细入口）—— 三枚叠放的币。
# 刻意区别于单枚 `coin`：那个是 HUD 上的「当前余额」，
# 这个是「收支构成」，语义不同就该有不同形状。
ICONS['coins'] = [
    "................",
    "................",
    "................",
    "....KKKKKKKK....",
    "..KKoOOOOOOoKK..",
    "..KoOyOOOOOOoK..",
    "..KooOOOOOOooK..",
    "..KKKKKKKKKKKK..",
    ".KKoOOOOOOOOoKK.",
    ".KoOyOOOOOOOOoK.",
    ".KooOOOOOOOOooK.",
    ".KKKKKKKKKKKKKK.",
    "KKoOOOOOOOOOOoKK",
    "KoOyOOOOOOOOOOoK",
    "KooOOOOOOOOOOooK",
    ".KKKKKKKKKKKKKK.",
]

# 爪印（宠物入口）—— 三趾 + 水滴形掌垫。
# 掌垫上窄下宽，不是圆角矩形：矩形版本看起来像三个点加一块板。
ICONS['paw'] = [
    "................",
    "..KK...KK...KK..",
    ".KPPK.KPPK.KPPK.",
    ".KPPK.KPPK.KPPK.",
    ".KppK.KppK.KppK.",
    "..KK...KK...KK..",
    "................",
    "......KKKK......",
    "....KKPPPPKK....",
    "...KPPPPPPPPK...",
    "..KPPPPPPPPPPK..",
    "..KPPPPPPPPPPK..",
    "..KppPPPPPPppK..",
    "...KppppppppK...",
    "....KKKKKKKK....",
    "................",
]

# 商店（店铺雨棚 + 门）。
# 不复用 `coins` —— 那个已经是「收支明细」入口，
# 同一个图标指向两个地方会让人点错。
ICONS['shop'] = [
    "................",
    "................",
    "..KKKKKKKKKKKK..",
    ".KTTKttKTTKttKTK",
    ".KTTKttKTTKttKTK",
    ".KKKKKKKKKKKKKK.",
    ".KwwwwwwwwwwwwK.",
    ".KwKKKKKKKKKKwK.",
    ".KwKWWWWWWWWKwK.",
    ".KwKWKKKKKKWKwK.",
    ".KwKWKwwwwKWKwK.",
    ".KwKWKwwwwKWKwK.",
    ".KwKWKwwwwKWKwK.",
    ".KwKWKwwwwKWKwK.",
    ".KKKKKKKKKKKKKK.",
    "................",
]

ICONS['star'] = [
    "................",
    "................",
    ".......KK.......",
    "......KssK......",
    "......KSSK......",
    "..KKKKKSSKKKKK..",
    "..KsSSSSSSSSsK..",
    "...KsSSSSSSsK...",
    "....KsSSSSsK....",
    "....KsSSSSsK....",
    "...KsSSKKSSsK...",
    "..KsSSK..KSSsK..",
    "..KKKK....KKKK..",
    "................",
    "................",
    "................",
]

# 睡眠 zZ（需求指示）
ICONS['sleep'] = [
    "................",
    "................",
    "....KKKKKK......",
    "....KBBBBK......",
    "......KBBK......",
    ".....KBBK.......",
    "....KBBK........",
    "....KBBBBK......",
    "....KKKKKK......",
    "........KKKK....",
    "........KBBK....",
    ".........KBK....",
    "........KBBK....",
    "........KKKK....",
    "................",
    "................",
]

# ⚠️ 只能**追加到末尾** —— PixelIcon 的 case 用的是这里的索引，
# 中间插入会让所有后续图标错位。
ORDER = ['meat', 'ball', 'bath', 'coin', 'scraps', 'kibble',
         'can', 'fish', 'heart', 'star', 'sleep', 'coins', 'paw', 'shop']


def build():
    n = len(ORDER)
    W, H = CELL * n, CELL
    buf = bytearray(W * H * 4)

    for i, key in enumerate(ORDER):
        rows = ICONS[key]
        assert len(rows) == CELL, f"{key} 行数 {len(rows)} != {CELL}"
        for y, line in enumerate(rows):
            assert len(line) == CELL, f"{key} y={y} 列数 {len(line)} != {CELL}"
            for x, ch in enumerate(line):
                c = PAL.get(ch)
                if c is None:
                    raise SystemExit(f"{key} y={y} x={x} 未知图例 {ch!r}")
                if c[3] == 0:
                    continue
                setpx(buf, W, i * CELL + x, y, c)

    save('Assets/ui/icons.png', W, H, buf)
    print(f"Assets/ui/icons.png  {W}×{H}  {n} 个图标")
    print("顺序：" + " ".join(f"{i}:{k}" for i, k in enumerate(ORDER)))


if __name__ == '__main__':
    build()
