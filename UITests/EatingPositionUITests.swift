import XCTest

/// 吃饭站位的**确定性**断言。
///
/// ## 为什么要有这组测试
///
/// 吃饭站位这件事我改了六轮才对。每轮都是「改一个猜测 → 看截图 →
/// 还是不对」，因为截图只能告诉我「不对」，说不出「差多少、差在哪」。
///
/// 中间试过扫屏幕像素来判断，为它调了 5 轮阈值都不稳：
/// 宠物会挡住碗（实测只露 61px，正常 161px）、成就气泡会盖住宠物、
/// 没被派活的宠物在自由游荡。那是**方法不对**的信号 ——
/// 位置这种精确的事该问场景本身，不该靠数像素反推。
///
/// 所以改成读 `PetScene.debugLayoutSnapshot`（DEBUG 下导出的
/// 归一化坐标文本）。同一件事，从「猜」变成「量」。
///
/// ## 和单元测试的分工
///
/// `BowlSlotLayoutTests` 测的是**排位公式的性质**（左右对称、
/// 外圈更远、任意两只不重叠、嘴要对准碗）—— 纯算术，不需要跑 app。
///
/// 这里测的是**公式在真实场景里生效了** —— 碗按存档摆到了正确位置、
/// 宠物真的走过去了、真的进入了吃饭状态。这两层缺一不可：
/// 公式对但场景没调用它，或者调用了但被地板 clamp 拦住，
/// 单元测试都发现不了（后者就是真实发生过的 bug）。
final class EatingPositionUITests: UITestCase {

    /// 解析 `debugLayoutSnapshot` 的输出。
    ///
    /// 格式：`size=440x956 bowl=0.350,0.302 bowlW=0.121 pet[A1B2]=0.31,0.29:eat`
    private struct Snapshot {
        var bowl: CGPoint?
        var bowlWidth: Double = 0
        /// petID 前缀 → (位置, 行为标签)
        var pets: [(id: String, pos: CGPoint, tag: String)] = []

        init?(_ raw: String) {
            guard !raw.isEmpty, raw != "size=0" else { return nil }
            for field in raw.split(separator: " ") {
                let kv = field.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let key = String(kv[0]), val = String(kv[1])

                if key == "bowl" {
                    if val == "none" { continue }
                    bowl = Self.point(val)
                } else if key == "bowlW" {
                    bowlWidth = Double(val) ?? 0
                } else if key.hasPrefix("pet[") {
                    let id = String(key.dropFirst(4).dropLast())
                    let parts = val.split(separator: ":")
                    guard parts.count == 2,
                          let p = Self.point(String(parts[0])) else { continue }
                    pets.append((id, p, String(parts[1])))
                }
            }
            if bowl == nil && pets.isEmpty { return nil }
        }

        private static func point(_ s: String) -> CGPoint? {
            let c = s.split(separator: ",")
            guard c.count == 2, let x = Double(c[0]), let y = Double(c[1])
            else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    /// 读一次快照。
    private func snapshot() -> Snapshot? {
        let e = el(A11y.sceneSnapshot)
        guard e.exists else { return nil }
        // 快照挂在 accessibilityLabel 上
        return Snapshot(e.label)
    }

    /// 等到所有宠物都进入某个状态（或超时）。
    ///
    /// 宠物以 34pt/秒 走向碗，从屏幕一端过去要好几秒；
    /// 而且睡着的要先被叫醒、起身。固定 sleep 抓到的是「正在路上」
    /// 的一帧 —— 那正是像素方案忽绿忽红的原因。
    @discardableResult
    private func waitUntil(timeout: TimeInterval = 20,
                           _ check: (Snapshot) -> Bool) -> Snapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: Snapshot?
        while Date() < deadline {
            if let s = snapshot() {
                last = s
                if check(s) { return s }
            }
            usleep(300_000)
        }
        return last
    }

    /// 持续采样，记录**每只宠物曾经出现过的行为标签**。
    ///
    /// ⚠️ **不能断言「所有宠物同时在吃」** —— 那个窗口可能根本不存在。
    ///
    /// 吃饭动画只有 3.52 秒（4 帧 × 0.22s × repeat 4，
    /// 见 `PetActor.applyEatAnimation`），而两只宠物走的距离不同、
    /// 到达时间不同：先到的吃完回 idle 时，后到的可能才刚开始。
    ///
    /// 我第一版要求 `allSatisfy { $0.tag == "eat" }`，结果 25 秒超时，
    /// 报「卡在 toBowl」—— 但真正的原因是我又犯了和像素方案同一个
    /// 错误：**把一个过程当成了瞬时状态**。
    ///
    /// - Returns: petID 前缀 → 观察到的标签集合
    private func observeBehaviors(seconds: TimeInterval,
                                  stopWhen: ((Set<String>) -> Bool)? = nil)
        -> [String: Set<String>] {
        var seen: [String: Set<String>] = [:]
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let s = snapshot() {
                for p in s.pets {
                    seen[p.id, default: []].insert(p.tag)
                }
                if let stopWhen {
                    // 已经收集到想看的了，提前退出省时间
                    let ate = Set(seen.filter { $0.value.contains("eat") }.keys)
                    if stopWhen(ate) { break }
                }
            }
            usleep(250_000)
        }
        return seen
    }

    /// 喂一次，并**确认喂食真的生效了**。
    ///
    /// ⚠️ 不能点完就往下走。`PetHomeView` 里是
    /// `guard store.feed(food) else { return }` 才调 `triggerEat()` ——
    /// 点击一旦被吞掉（成就 toast 会盖在按钮上，实测见过
    /// 「达成『照顾三天』，+200 枚！」的横幅），
    /// 宠物根本不会被派活，快照里就是 `idle/walk`。
    ///
    /// 那次失败我一开始以为是「走不到碗边」，但标签对不上：
    /// `toBowl` 才是走不到，`idle/walk` 是**没派活**。
    /// 两者根因完全不同，测试必须能区分。
    ///
    /// 判据：食物 sheet 关掉了就说明选中生效了（`row` 里直接 `dismiss()`）。
    private func feedKibble(file: StaticString = #filePath,
                            line: UInt = #line) {
        tap(A11y.feed, file: file, line: line)
        tap(A11y.food("kibble"), file: file, line: line)

        // sheet 必须关掉。还开着 = 那一下没点中，
        // 后面所有断言都会以「宠物没在吃」失败，而那是假象。
        let sheet = el(A11y.food("kibble"))
        let deadline = Date().addingTimeInterval(6)
        while sheet.exists, Date() < deadline { usleep(150_000) }
        XCTAssertFalse(sheet.exists,
                       "食物弹窗没关 —— 选中没生效（点击被 toast 吞了？），"
                       + "此时宠物不会被派活，别把它误读成「走不到碗边」",
                       file: file, line: line)
    }

    // MARK: - 测试

    /// **碗要摆在存档写的位置。**
    ///
    /// 这条验证「存档 → 解码 → 摆位」这条链路真的通 ——
    /// 而它曾经断过：`RoomLayout.Slot` 的合成 Codable 对有默认值的
    /// 属性仍要求 key 存在，旧存档缺 `depth` 就整份解码失败，
    /// 静默退回 `.default`，玩家摆好的布局无声重置。
    func testBowlIsPlacedWhereSaveSaid() {
        launch(scene: "bowl-two-pets")     // 存档里碗在 xRatio 0.35

        guard let s = waitUntil(timeout: 12, { $0.bowl != nil }),
              let bowl = s.bowl else {
            return XCTFail("拿不到碗的位置，快照：\(el(A11y.sceneSnapshot).label)")
        }
        XCTAssertEqual(bowl.x, 0.35, accuracy: 0.06,
                       "碗没摆在存档写的 0.35 —— 布局被重置了？")
        XCTAssertGreaterThan(s.bowlWidth, 0.05, "碗宽异常，可能没渲染出来")
    }

    /// **喂食后所有宠物都要进入吃饭状态。**
    ///
    /// 曾经的 bug：走路目标用了「头埋进碗」的位置，但那个 y 在地板
    /// 范围之上，`moveToward` 里的 `floor.clamp` 会把它夹回地板，
    /// 距离永远大于到达阈值 —— **永远到不了**，一直停在
    /// `.walkingToBowl`，播的是走路动画而不是吃饭。
    /// 表现就是「宠物站在碗旁边用走路姿态」。
    ///
    /// 这条测试直接盯 behavior 标签，那个 bug 会让它超时失败。
    func testAllPetsReachBowlAndEat() {
        launch(scene: "bowl-two-pets")

        feedKibble()

        // 累计观察 —— 每只都**曾经**吃过就算通过（见 observeBehaviors 的注释）
        let seen = observeBehaviors(seconds: 30) { $0.count >= 2 }

        XCTAssertGreaterThanOrEqual(seen.count, 2,
                                    "只看到 \(seen.count) 只宠物，场景没起来？")

        let ate = seen.filter { $0.value.contains("eat") }
        let never = seen.filter { !$0.value.contains("eat") }
        XCTAssertEqual(ate.count, seen.count,
                       "这些宠物从没进入吃饭状态："
                       + never.map { "\($0.key)=\($0.value.sorted().joined(separator: "/"))" }
                              .joined(separator: " ")
                       + "（只见 toBowl 说明被地板 clamp 拦住了，走不到）")
    }

    /// **吃饭时宠物要在碗附近，不能站在屏幕另一头。**
    ///
    /// 这是最初那个「站位不对」的直接断言。
    /// 容差按碗宽给 —— 多只会往两边铺开（`gatherToBowl` 里
    /// `spread = bowlRect.width * 0.32`）。
    func testEatingPetsStayNearBowl() {
        launch(scene: "bowl-two-pets")

        feedKibble()

        guard let s = waitUntil(timeout: 25, { snap in
            snap.bowl != nil && snap.pets.contains { $0.tag == "eat" }
        }), let bowl = s.bowl else {
            return XCTFail("等不到宠物开吃")
        }

        let eating = s.pets.filter { $0.tag == "eat" }
        XCTAssertFalse(eating.isEmpty, "没有宠物在吃")

        // 允许的横向偏差：碗宽的 1.5 倍（够侧站开，又不至于跑到别处）
        let limit = max(0.12, s.bowlWidth * 1.5)
        for p in eating {
            XCTAssertEqual(p.pos.x, bowl.x, accuracy: limit,
                           "宠物 \(p.id) 在 x=\(p.pos.x)，"
                           + "碗在 x=\(bowl.x)，差太多了")
        }
    }

    /// **多只不能叠在同一个点。**
    ///
    /// `BowlSlotLayoutTests.testNoTwoPetsShareASlot` 测的是公式，
    /// 这条测的是场景里真的排开了 —— 公式对但调用时传错 index
    /// 也会让它们重叠，那种错单元测试看不见。
    func testThreePetsDoNotOverlap() {
        launch(scene: "bowl-three-pets")

        feedKibble()

        guard let s = waitUntil(timeout: 25, { snap in
            snap.pets.count >= 3
                && snap.pets.filter({ $0.tag == "eat" }).count >= 2
        }) else {
            return XCTFail("等不到多只开吃")
        }

        let eating = s.pets.filter { $0.tag == "eat" }

        // ⚠️ **先断言样本量，再比距离。**
        //
        // 反向验证时发现的缺陷：我注入历史 bug（走路目标在地板之上，
        // 被 `floor.clamp` 拦住，宠物永远到不了碗边）后，
        // 另外两条测试都正确失败了，**这条却照样通过** ——
        // 因为没有宠物在吃，`eating` 是空数组，
        // 两层循环直接空转，断言一次都没执行。
        //
        // 「循环里的断言」必须配一个「循环真的跑了」的前提，
        // 否则它在最该报警的时候恰好静默。
        XCTAssertGreaterThanOrEqual(
            eating.count, 2,
            "只有 \(eating.count) 只在吃，比不出重叠 —— "
            + "这条断言会退化成空断言")

        for i in eating.indices {
            for j in eating.indices where j > i {
                let dx = abs(eating[i].pos.x - eating[j].pos.x)
                let dy = abs(eating[i].pos.y - eating[j].pos.y)
                XCTAssertGreaterThan(dx + dy, 0.015,
                                     "\(eating[i].id) 和 \(eating[j].id) "
                                     + "几乎站在同一点，视觉上会叠在一起")
            }
        }
    }

    /// **没买碗时也不能崩，回退到脚边食盆。**
    ///
    /// `triggerEat()` 里有 `if let bowl ... else feedInPlace`，
    /// 这条走 else 分支。
    func testFeedWithoutBowlStillWorks() {
        launch(scene: "no-bowl")

        guard let before = waitUntil(timeout: 12, { $0.pets.count >= 1 }) else {
            return XCTFail("场景没起来")
        }
        XCTAssertNil(before.bowl, "no-bowl 场景不该有碗")

        feedKibble()

        let s = waitUntil(timeout: 20) { $0.pets.contains { $0.tag == "eat" } }
        XCTAssertTrue(s?.pets.contains { $0.tag == "eat" } ?? false,
                      "没碗时也该能吃（回退到脚边食盆）")
    }
}
