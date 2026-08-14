# Home Objects — 素材凭证

## 来源
- 页面：https://opengameart.org/content/home-objects
- 作者：Jannax
- 下载日期：2026-08-14

## 页面 License 字段原文（逐字）
```
License(s): CC0
```
纯 CC0，无混杂授权。无 Copyright/Attribution Notice 字段（CC0 不要求署名）。

## 文件
| 文件 | 原始 URL | SHA-256 |
|---|---|---|
| Assets/room/house_objects.png | https://opengameart.org/sites/default/files/House%20Objects%201%20Revised_2.png | `e1ba391f0dfac8b5ebd085a901826ee3da570373f7da9150aa5f0e77003b5272` |

## 修改说明
未修改。运行时按像素矩形切分。

## ⚠️ 实测：不是「一格一件家具」
作者说「already set up in 32x32 spaces」，但实际**多件家具跨多格**，
按单格切会切出半截家具。且有空格子。实测有效矩形（左上原点）：

| 名称 | x | y | w | h |
|---|---|---|---|---|
| bed（双人床） | 0 | 0 | 64 | 64 |
| bookshelf（书架） | 64 | 0 | 32 | 64 |
| sofa（沙发） | 96 | 0 | 64 | 32 |
| nightstand（床头柜） | 160 | 0 | 32 | 32 |
| plant（盆栽） | 160 | 32 | 32 | 32 |
| rug（地毯） | 0 | 128 | 64 | 64 |

**空格子（不要取）**：(96,32)、(128,32)

## ⚠️ 待办：Wayback Machine 存档
提交 https://opengameart.org/content/home-objects 到 https://web.archive.org/save/
