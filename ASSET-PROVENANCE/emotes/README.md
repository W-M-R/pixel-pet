# 16x16 Emotes for RPGs and Digital Pets — 素材凭证

## 来源
- 页面：https://opengameart.org/content/16x16-emotes-for-rpgs-and-digital-pets
- 作者：Tomcat94
- 下载日期：2026-08-14

## 页面 License 字段原文（逐字）
```
License(s): CC0
```

## Copyright/Attribution Notice 原文（逐字）
```
Credit is not necessary.
```

## 文件
| 文件 | 原始 URL | SHA-256 |
|---|---|---|
| Assets/ui/emotes.png | https://opengameart.org/sites/default/files/emotes.png | `db58556e5bff1badd854ae43328a985c5cd5d11104e5ae331ae67c2fb6d7434b` |

## 修改说明
未修改。运行时按网格切分。

## ⚠️ 实测网格：不是 16×16
文件名叫「16x16」，但实际是 **140×120，图标 12×12，间距 20px**，
左边距 4、上边距 3，共 **7 列 × 6 行**。
按 16×16 或 20×20 切都会错位。参数是扫空行/空列反推的：
- 空列区间：(0,3) (16,23) (36,43) (56,63) (76,83) (96,103) (116,123) (136,139)
- 空行区间：(0,2) (15,22) (35,42) (57,62) (77,82) (95,102) (115,119)

## 实测图标内容（放大逐格核对）
- r0: `!` `?` `…` `♥` 心碎 `♪` 汗滴
- r1: `zZ` `✱` `↑` `↓` `✦` `☁` `☂`
- r2: `✿` `☠` 💧 `⚡` `☀` `✚` `✖`

**注意**：包里没有食物/球/浴缸这类具体道具图标，只有抽象符号。
所以「饿」这个需求没有对应图标，代码里回退到 emoji。

## ⚠️ 待办：Wayback Machine 存档
提交页面 URL 到 https://web.archive.org/save/
