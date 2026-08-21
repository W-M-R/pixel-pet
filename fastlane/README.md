fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios preflight

```sh
[bundle exec] fastlane ios preflight
```

Maestro 冒烟：启动/主路径/截图/崩溃检查

### ios compliance

```sh
[bundle exec] fastlane ios compliance
```

precheck 扫 ASC 元数据（出海红线）

### ios register

```sh
[bundle exec] fastlane ios register
```

produce：注册 App ID + 创建 ASC app 记录（半自动，需 Apple ID 登录）

### ios upload_meta

```sh
[bundle exec] fastlane ios upload_meta
```

deliver：上传元数据/截图/海报（不传二进制、不提审）

### ios upload_screens

```sh
[bundle exec] fastlane ios upload_screens
```

deliver：只上传截图/海报（跳过元数据，绕开首版本 No data bug）

### ios privacy

```sh
[bundle exec] fastlane ios privacy
```

隐私营养标签（半自动：仅校验 JSON，写入走 ASC 网页）

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
