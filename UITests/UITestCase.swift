import XCTest

/// UI 测试的共用底座。
///
/// ## 为什么用 launchArguments 传场景
///
/// 深层场景（有碗、多宠、有钱）靠点击玩到那一步既慢又脆 ——
/// 要攒 800 买碗、攒 4000 买第二只。`tools/inject_save.py` 能直接写
/// 存档，但那是**外部脚本**，XCUI 跑在设备上碰不到宿主机的文件系统。
///
/// 所以改成 app 自己认参数：`-uitest-scene bowl-two-pets` 启动时
/// 就把存档铺好（见 `PixelPetApp` 的 `applyUITestScene`）。
/// 这样测试是自包含的，不依赖外部工具。
class UITestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        // 一个断言失败就停 —— 后面的步骤基本都会连带失败，
        // 让报错停在第一个真问题上，读日志省事得多。
        continueAfterFailure = false
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// 启动 app。
    ///
    /// - Parameter scene: 预置场景名，nil 表示全新存档（走开局引导）
    @discardableResult
    func launch(scene: String? = nil) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchArguments += ["-uitest"]
        if let scene {
            a.launchArguments += ["-uitest-scene", scene]
        }
        a.launch()
        app = a
        return a
    }

    // MARK: - 常用查询

    /// 按 identifier 找元素。
    ///
    /// 不限定类型 —— `Button { PixelIconView(...) }` 这种自绘按钮在
    /// XCUI 里的类型不稳定（可能是 button，也可能是 other），
    /// 按类型查会莫名找不到。`descendants` 全找最省事。
    func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 等元素出现，超时就失败并说清等的是谁。
    @discardableResult
    func waitFor(_ id: String, timeout: TimeInterval = 8,
                 file: StaticString = #filePath,
                 line: UInt = #line) -> XCUIElement {
        let e = el(id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout),
                      "等不到元素「\(id)」", file: file, line: line)
        return e
    }

    /// 点一个元素。
    ///
    /// ⚠️ **要等「可点」，不能只等「存在」。**
    /// sheet 弹出有动画，元素在动画开始时就已经 `exists`，
    /// 但要等动画结束才 `isHittable`。
    /// 我第一版在 `waitForExistence` 之后立刻断言 `isHittable`，
    /// 于是 `food.kibble` 报「存在但点不到」——
    /// 诊断时发现等 2 秒后完全正常，纯粹是抢跑。
    func tap(_ id: String, timeout: TimeInterval = 8,
             file: StaticString = #filePath, line: UInt = #line) {
        let e = waitFor(id, timeout: timeout, file: file, line: line)
        let deadline = Date().addingTimeInterval(timeout)
        while !e.isHittable, Date() < deadline { usleep(100_000) }
        XCTAssertTrue(e.isHittable,
                      "元素「\(id)」\(Int(timeout)) 秒内都点不到"
                      + "（frame=\(e.frame)）", file: file, line: line)
        e.tap()
    }
}
