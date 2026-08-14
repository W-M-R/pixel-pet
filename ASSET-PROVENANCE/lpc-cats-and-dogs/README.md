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
每 4 列为一个动画循环，横向重复 4 次 = 4 种毛色。

| 行 | 内容 | 判定依据 |
|---|---|---|
| r0 | 侧视朝右 walk | 高度剖面 x=18..22 最高(17-18px)=头部 |
| r1 | 正视(面向镜头) walk | bbox 窄(13×25) |
| r2 | 背视 walk | bbox 窄，尾部朝上 |
| r3 | 侧视朝左 walk | 高度剖面 x=10..12 最高(18-19px)=头部 |
| r4 | 吃东西(咀嚼) | bbox 窄且帧间头部有上下位移 |

## ⚠️ 待办：Wayback Machine 存档
需手动提交页面 URL 到 https://web.archive.org/save/
理由：OGA 允许作者事后改授权(FAQ: "an artist may change their license
requirements, at any time")，而 Apple 审核指南 5.2.1 要求证明有权使用。
第三方时间戳的证明力高于自存快照。

## ⚠️ 注意：预览图不可用于商店素材
OGA FAQ：「Unless otherwise noted, assume the previews are 'All rights reserved'」
App 图标与 App Store 截图只能使用实际下载到的 cat.png / dog.png。
