# App Store 截图 / 海报（iPhone-only）

deliver 从本目录按语言子目录读取截图并自动上传到 App Store Connect。

## 规格
- 只做 iPhone：一组 **6.9"** 截图即可覆盖全部现代 iPhone
  - 尺寸：**1290×2796** 或 **1320×2868**（竖屏）
  - 机型：iPhone 16 Pro Max / 15 Pro Max
- 语言目录：`zh-Hans/`（简体中文）
- 文件名决定上架顺序，用序号前缀：`01_...png`、`02_...png` …（最多 10 张）

## 两个来源
1. **Maestro 自动截图**：阶段1 跑 `maestro/smoke.yaml` 时 `takeScreenshot` 落到这里，
   文件名即上架顺序（真实界面，首选）。
2. **手工海报/精修图**：直接把图放进 `zh-Hans/`，与自动截图一起被 deliver 上传。

## 校验
- 非 6.9" 规格会被 deliver 或 overseas_check.py 警告，避免 ASC 退回。
- App 预览视频（可选）放同目录，命名 `*.mov/.m4v`。
