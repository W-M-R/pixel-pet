# [LPC] Cats and Dogs — 素材凭证

## 来源
- 页面：https://opengameart.org/content/lpc-cats-and-dogs
- 作者：bluecarrot16
- 下载日期：2026-08-14

## 页面 License 字段原文（逐字）
```
License(s): CC-BY 3.0  CC-BY-SA 3.0  GPL 3.0  GPL 2.0  OGA-BY 3.0
```

## Copyright/Attribution Notice 原文（逐字）
```
"[LPC] Cats and Dogs"
Artist: bluecarrot16
License: CC-BY 3.0 / GPL 3.0 / GPL 2.0 / OGA-BY 3.0
Please link to opengameart: http://opengameart.org/content/lpc-cats-and-dogs
```

## 本项目采用的许可：OGA-BY 3.0

依据 OGA FAQ 原文「You must follow only one of the licenses」，多授权中只需遵守其一。
选 OGA-BY 3.0 的理由：它是专为移除 CC-BY 的技术措施(ETM/DRM)限制而创建的变体，
FAQ 原文：「OGA-BY 3.0 is a license based on CC-BY 3.0 that removes that license's
restriction on technical measures that prevent redistribution of a work.」
App Store 对所有 app 施加 FairPlay DRM，选 OGA-BY 可避开 CC-BY 的 ETM 条款争议，
同时绕开 CC-BY-SA 的传染性。

## 文件
| 文件 | 原始 URL | SHA-256 |
| Assets/pets/cat.png | https://opengameart.org/sites/default/files/cat_0.png | `914bae85486052a70d29b26d881bfce3dcaa987f6f95cab08e4a65e30fa13f97` |
| Assets/pets/dog.png | https://opengameart.org/sites/default/files/dog_2.png | `77f4667ab3f681408a8afa528f3fff0bea3e3cd7d0e28d5c11f2d09c7729b891` |

## 修改说明（署名时必须声明）
未修改原始像素数据。仅在运行时按 32×32 网格切分帧。

## 实测帧布局
512×256，帧 32×32，16 列 × 8 行，仅前 5 行有内容。
每 4 列为一组，横向重复 4 次 = 4 种毛色。

| 行 | 内容 | 判定依据 |
|---|---|---|
| r0 | 侧视朝右 | 高度剖面 x=18..22 最高(17-18px)=头部 |
| r1 | 正视(面向镜头) | bbox 窄(13×25) |
| r2 | 背视 | bbox 窄，尾部朝上 |
| r3 | 侧视朝左 | 高度剖面 x=10..12 最高(18-19px)=头部 |
| r4 | 吃东西(咀嚼) | bbox 窄且帧间头部有上下位移 |

### ⚠️⚠️ 走路只有 3 帧，第 4 格是坐/趴姿 —— 不是走路帧

**这条曾导致「走路一顿一顿」，绕了很多弯才定位，务必看清。**

每组 4 列里 **只有 col0/col1/col2 是走路帧**，col3 是静止的坐/趴姿：

```
逐格不透明像素数（第一个毛色）
cat  r0(右): [275, 257, 269, 252]   ← col3 趴卧（无腿、身体贴地）
cat  r1(正): [232, 240, 241,   0]   ← col3 完全空白
cat  r2(背): [191, 190, 191,   0]   ← col3 完全空白
cat  r3(左): [269, 257, 275, 252]   ← col3 趴卧
dog  r0(右): [326, 304, 321, 259]   ← col3 趴卧
```

按 4 帧循环播的后果：左右走每周期「抽」一下趴下，
正/背向走每周期闪一帧空白。

**正确帧序：`col0 → col1 → col2 → col1`（ping-pong，每帧 ~150ms）**

col1 是 passing pose（中间姿），往复时出现两次，视觉上即左右腿交替。
不要用 `0→1→2` 硬循环 —— 从 col2 跳回 col0 是同侧腿突然换边，会跳。

三条独立证据：

1. **像素统计**：如上表，cat 的 r1/r2 第 4 格是 0 像素
2. **作者预览 GIF 逐帧解码**：walk 预览用的是 col0→col1→col2→col1，
   col3 从未出现，每帧 150ms
3. **OpenGameArt 官方分类**：该资源收录于
   [3 Frame Walk Cycles](https://opengameart.org/content/3-frame-walk-cycles)
   合集（描述 "Walk cycles with only three frames"）；
   [Cats Rework](https://opengameart.org/content/cats-rework) 写明
   "3 tiles per direction (frames)"

代码见 `PetSpriteSheet.walkFrameSequence`，由
`PetSpriteSheetTests.testWalkUsesThreeFramePingPong` 等 3 条测试锁住。

**col3 的正确用途**：拿去做 idle（停下来时坐着），白捡一个状态。
注意 cat 的 r1/r2 col3 是空白，正/背向要回退到 col0。

### 加新宠物 sheet 时的检查清单

- [ ] 逐格统计不透明像素数，确认 col3 是坐姿还是走路帧
- [ ] 若某个 sheet 真有 4 帧走路，需让 `walkFrameSequence` 按品种可配，
      而不是当前的全局常量
- [ ] 跑 `tools/make_stages.py`，其 `verify_cycle` 会校验派生帧的
      帧间体型一致性（防止某帧没被抽行）

## ⚠️ 待办：Wayback Machine 存档
需手动提交页面 URL 到 https://web.archive.org/save/
理由：OGA 允许作者事后改授权(FAQ: "an artist may change their license
requirements, at any time")，而 Apple 审核指南 5.2.1 要求证明有权使用。
第三方时间戳的证明力高于自存快照。

## ⚠️ 注意：预览图不可用于商店素材
OGA FAQ：「Unless otherwise noted, assume the previews are 'All rights reserved'」
App 图标与 App Store 截图只能使用实际下载到的 cat.png / dog.png。

## 衍生素材：cat_sleep.png / dog_sleep.png

主 sheet 里**没有** sleep 帧（r4 经放大核对确认是咀嚼动画）。
趴卧帧由 `tools/make_sleep.py` 生成：

- 形状为**手绘点阵**（不是从原帧几何变形——试过压缩躯干，
  像素画形状信息太密，算法变形会切断轮廓）
- **调色板从主 sheet 自动提取**：读该毛色侧视帧的高频色，
  按亮度分出 亮/中/暗，保证 4 种毛色与走路帧一致
- 底边对齐 y=26，与走路帧一致，否则趴下时会悬空偏小
- 布局 4 列(毛色) × 2 行(呼气/吸气)，每格 32×32

授权归属：形状为本项目原创，仅调色板取自 OGA-BY 素材。
按 OGA-BY 3.0 已在 Credits 声明修改。
