import XCTest
@testable import PixelPet

/// 配置表：生命阶段、品种、互动时长。
///
/// 这些表是「加新 feature 时改的地方」，测试保证新增项不破坏约束
/// （比如每个阶段的额度必须大于该阶段的日常粮钱）。

final class PetStageTests: XCTestCase {

    func testStageBoundaries() {
        XCTAssertEqual(PetStage.forAge(days: 0), .young)
        XCTAssertEqual(PetStage.forAge(days: 2), .young)
        XCTAssertEqual(PetStage.forAge(days: 3), .growing)
        XCTAssertEqual(PetStage.forAge(days: 6), .growing)
        XCTAssertEqual(PetStage.forAge(days: 7), .adult)
        XCTAssertEqual(PetStage.forAge(days: 29), .adult)
        XCTAssertEqual(PetStage.forAge(days: 30), .elder)
    }

    func testDaysToNext() {
        XCTAssertEqual(PetStage.young.daysToNext(from: 0), 3)
        XCTAssertEqual(PetStage.growing.daysToNext(from: 3), 4)
        XCTAssertEqual(PetStage.adult.daysToNext(from: 7), 23)
        XCTAssertNil(PetStage.elder.daysToNext(from: 30), "老年是最终阶段")
    }

    /// 成年用源图（无后缀），其余用派生 sheet
    func testSheetNaming() {
        XCTAssertEqual(PetBreed.cat.sheetName(for: .adult), "cat")
        XCTAssertEqual(PetBreed.cat.sheetName(for: .young), "cat_young")
        XCTAssertEqual(PetBreed.cat.sheetName(for: .elder), "cat_elder")
        XCTAssertEqual(PetBreed.dog.sleepSheetName, "dog_sleep")
    }

    func testBreedRegistry() {
        XCTAssertEqual(PetBreed.all.count, 2)
        XCTAssertEqual(PetBreed.byID("dog").id, "dog")
        XCTAssertEqual(PetBreed.byID("nope").id, "cat", "未知 ID 回退到猫")
    }

    /// 回归测试：旧存档存 `species`，新代码读 `breedID`。
    /// 不兼容会让老用户的宠物被重置。
    func testDecodesLegacySpeciesField() throws {
        let legacy = """
        {"species":"dog","colorIndex":2,"name":"旺财",
         "bornAt":0,"lastFedAt":0,"lastPlayedAt":0,"lastCleanedAt":0}
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(PetState.self, from: legacy)
        XCTAssertEqual(d.breedID, "dog")
        XCTAssertEqual(d.colorIndex, 2)
        XCTAssertEqual(d.name, "旺财")
    }

    func testEncodeRoundTrip() throws {
        var s = PetState(breedID: "dog", colorIndex: 1, name: "小黑")
        s.totalFeedCount = 5
        s.streakDays = 3
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PetState.self, from: data)
        XCTAssertEqual(back.breedID, "dog")
        XCTAssertEqual(back.totalFeedCount, 5)
        XCTAssertEqual(back.streakDays, 3)
    }

    /// 体型缩放必须单调递增到成年，且幼年差异足够明显。
    /// 最初只靠抽行（差 2-4px），实测肉眼不可辨，所以叠了 bodyScale。
    func testBodyScaleGivesVisibleDifference() {
        XCTAssertLessThan(PetStage.young.bodyScale, PetStage.growing.bodyScale)
        XCTAssertLessThan(PetStage.growing.bodyScale, PetStage.adult.bodyScale)
        XCTAssertEqual(PetStage.adult.bodyScale, 1.0)
        // 老年比成年小但比成长期大
        XCTAssertLessThan(PetStage.elder.bodyScale, PetStage.adult.bodyScale)
        XCTAssertGreaterThan(PetStage.elder.bodyScale, PetStage.growing.bodyScale)
        // 幼年应明显小于成年（至少差 20%）
        XCTAssertLessThanOrEqual(PetStage.young.bodyScale, 0.8)
    }
}

// MARK: - 解耦后的模块边界

/// 阈值集中层。
///
/// 原来「多饿才算饿」散在 4 处：`dominantNeed`(0.35)、
/// `PetLines.pickCategory`(0.15/0.4)、以及 AI prompt 的中英文各一份(0.25/0.5)。
/// 最后两处必须手动同步，改一边忘一边会让两种语言描述出不同状态。

final class PetBreedGeometryTests: XCTestCase {

    /// `footPadding` 决定影子/食盆/气泡挂在哪。
    ///
    /// 原来 `PetScene` 硬编码 5（按猫实测），狗的内容底边在 y=28，
    /// 所以狗的影子和食盆一直偏 2 源像素。这个测试锁住按品种取值。
    func testFootPaddingDiffersByBreed() {
        XCTAssertEqual(PetBreed.cat.footPadding, 5)
        XCTAssertEqual(PetBreed.dog.footPadding, 3)
    }

    /// 每个品种都要有合理的 footPadding（不能为 0 或超过高一半）
    func testAllBreedsHaveSaneFootPadding() {
        for b in PetBreed.all {
            XCTAssertGreaterThan(b.footPadding, 0, "\(b.id) 的 footPadding 应大于 0")
            XCTAssertLessThan(b.footPadding, b.layout.cell / 2,
                              "\(b.id) 的 footPadding 过大")
        }
    }

    /// 每个品种的本地化必须齐全。
    ///
    /// 原来这个测试的循环体是**空的** —— 名字叫 testEveryBreedHasBothNouns，
    /// 但里面什么都没断言（那两个 noun 字段随 AI 台词一起删了，
    /// 删的时候把断言掏空却留了个空壳）。加品种忘补文案不会被抓到，
    /// 界面上会直接显示 raw key。
    func testEveryBreedHasLocalizedText() {
        for b in PetBreed.all {
            for key in [b.nameKey, b.traitKey] {
                XCTAssertFalse(key.isEmpty, "\(b.id) 缺 key")
                XCTAssertNotEqual(L(key), key,
                                  "\(b.id) 的 \(key) 没有译文 —— 界面会显示 key 本身")
                XCTAssertFalse(L(key).isEmpty)
            }
        }
    }
}

/// 互动动画时长与台词延迟的关系。

final class InteractionDurationTests: XCTestCase {

    /// 咀嚼动画时长应由帧数据算出，不是写死的数字
    func testEatDurationDerivedFromFrameData() {
        // 4 帧 × 0.22s × 重复 4 轮
        XCTAssertEqual(Interaction.Duration.eat, 0.22 * 4 * 4, accuracy: 0.001)
    }

    /// **台词延迟不能超过动画时长** —— 否则台词在动画结束后才冒出来，
    /// 显得反应迟钝。也不能太短（原来喂食是 1.6s vs 动画 3.52s，
    /// 台词在演到一半时就出现了）。
    func testSayDelaysFallWithinAnimation() {
        XCTAssertLessThan(Interaction.Duration.sayAfterEat,
                          Interaction.Duration.eat,
                          "台词不该在咀嚼结束后才说")
        XCTAssertGreaterThan(Interaction.Duration.sayAfterEat,
                             Interaction.Duration.eat * 0.5,
                             "台词不该在咀嚼刚开始就说")
    }
}

/// Fixture 自身的正确性。
///
/// 它反推时间戳来造指定状态，算错的话所有用它的测试都会基于错误前提 ——
/// 所以它本身需要被测。
final class FixtureTests: XCTestCase {

    /// 造出来的状态要和请求的比例吻合
    func testPetSatietyMatchesRequested() {
        for target in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let p = Fixture.pet(satiety: target)
            XCTAssertEqual(p.satiety(), target, accuracy: 0.02,
                           "请求 satiety=\(target) 但实际 \(p.satiety())")
        }
    }

    func testPetMoodAndHygieneMatchRequested() {
        let p = Fixture.pet(satiety: 1.0, mood: 0.3, hygiene: 0.6)
        XCTAssertEqual(p.mood(), 0.3, accuracy: 0.02)
        XCTAssertEqual(p.hygiene(), 0.6, accuracy: 0.02)
        XCTAssertEqual(p.satiety(), 1.0, accuracy: 0.02)
    }

    /// aged 要真的改变生命阶段
    func testAgedChangesStage() {
        let young = Fixture.pet()
        XCTAssertEqual(young.stage, .young)

        XCTAssertEqual(Fixture.aged(young, days: 3).stage, .growing)
        XCTAssertEqual(Fixture.aged(young, days: 7).stage, .adult)
        XCTAssertEqual(Fixture.aged(young, days: 30).stage, .elder)
    }

    /// awake 要能压过深夜作息 —— 否则夜里跑测试结果会变
    func testAwakeOverridesNightSchedule() {
        let p = Fixture.awake(Fixture.pet())
        XCTAssertFalse(p.isDrowsy(), "给了清醒宽限就不该困")
    }

    /// 默认满状态
    func testDefaultPetIsFullyCaredFor() {
        let p = Fixture.pet()
        XCTAssertEqual(p.satiety(), 1.0, accuracy: 0.01)
        XCTAssertEqual(p.mood(), 1.0, accuracy: 0.01)
        XCTAssertEqual(p.hygiene(), 1.0, accuracy: 0.01)
    }
}

/// 品种配平。
///
/// 设计目标是「没有哪个品种明显最优」，这里把它写成可执行的断言。
final class BreedBalanceTests: XCTestCase {

    /// 模拟一天的净结余（与 tools/econ_report.py 同一模型）
    private func netDaily(breed: PetBreed, stage: PetStage,
                          feedsPerDay n: Int) -> Int {
        let cap = stage.dailyCap
        let cycle = stage.hungerCycleHours
        let gap = 24.0 / Double(n)
        var remain = cap
        var income = 0
        var cost = 0

        for _ in 0..<n {
            if gap >= 0.5 && remain > 0 {
                let s = RewardEngine.averageLevel(offlineHours: gap,
                                                  cycleHours: cycle)
                let m = RewardEngine.averageLevel(offlineHours: gap,
                                                  cycleHours: breed.moodCycleHours)
                let rate = OfflineCareReward.achievementRate(satiety: s, mood: m)
                // ⚠️ 加成乘在 min 之前，和 RewardRules.evaluate 一致
                let want = Int((Double(cap) * rate * breed.goldMultiplier).rounded())
                let pay = min(remain, want)
                income += pay
                remain -= pay
            }
            if gap >= CheckInReward.minIntervalHours {
                income += CheckInReward.coins
            }
            let after = max(0, 1 - gap / cycle)
            cost += FoodItem.kibble.cost(currentSatiety: after)
        }
        return income - cost
    }

    /// a 支配 b：每项都不差，且至少一项更好
    private func dominates(_ a: [Int], _ b: [Int]) -> Bool {
        zip(a, b).allSatisfy { $0 >= $1 } && zip(a, b).contains { $0 > $1 }
    }

    /// **核心断言：没有品种支配其他品种。**
    ///
    /// 曾经狗的金币是 1.05，那时猫在全部四个阶段都支配狗 ——
    /// 4 次/天打平，但 1-3 次/天猫都更高，狗没有任何频次占优。
    ///
    /// 根因：1.05 是按「4 次/天相等」反解的，而那个点双方都撞额度上限、
    /// 加成被 min() 吃掉，所以「打平」是假象。
    func testNoBreedDominatesAnother() {
        let paces = [1, 2, 3, 4]
        for stage in PetStage.allCases {
            let profiles = PetBreed.all.map { breed in
                (breed.id, paces.map { netDaily(breed: breed, stage: stage,
                                                feedsPerDay: $0) })
            }
            for (nameA, a) in profiles {
                for (nameB, b) in profiles where nameA != nameB {
                    XCTAssertFalse(dominates(a, b),
                        "\(stage) 阶段 \(nameA)\(a) 支配了 \(nameB)\(b) —— "
                        + "设计目标是没有品种明显最优")
                }
            }
        }
    }

    /// 每个品种都要在某个频次占优 —— 否则它没有存在理由
    func testEveryBreedWinsSomewhere() {
        let paces = [1, 2, 3, 4]
        for stage in PetStage.allCases {
            for breed in PetBreed.all {
                let mine = paces.map { netDaily(breed: breed, stage: stage,
                                                feedsPerDay: $0) }
                let others = PetBreed.all.filter { $0.id != breed.id }
                guard !others.isEmpty else { continue }

                let winsSomewhere = paces.indices.contains { i in
                    others.allSatisfy { other in
                        mine[i] >= netDaily(breed: other, stage: stage,
                                            feedsPerDay: paces[i])
                    }
                }
                XCTAssertTrue(winsSomewhere,
                    "\(breed.id) 在 \(stage) 的任何频次都不占优")
            }
        }
    }

    /// 金币加成必须是两位小数。
    ///
    /// 配平系数是从枚举网格里取的（见 econ_report.solve_gold），
    /// 三位小数取整到两位后可能掉档 —— 文档里曾有 4 行踩这个坑。
    func testGoldMultipliersAreTwoDecimals() {
        for breed in PetBreed.all {
            let scaled = breed.goldMultiplier * 100
            XCTAssertEqual(scaled, scaled.rounded(), accuracy: 0.0001,
                           "\(breed.id) 的金币 \(breed.goldMultiplier) 不是两位小数")
        }
    }

    /// 加成要在合理区间 —— 过大会让品种选择变成「必须选某只」
    func testGoldMultipliersAreInSaneRange() {
        for breed in PetBreed.all {
            XCTAssertGreaterThanOrEqual(breed.goldMultiplier, 0.85)
            XCTAssertLessThanOrEqual(breed.goldMultiplier, 1.25)
        }
    }

    /// 心情周期要在合理区间
    func testMoodCyclesAreInSaneRange() {
        for breed in PetBreed.all {
            XCTAssertGreaterThanOrEqual(breed.moodCycleHours, 12)
            XCTAssertLessThanOrEqual(breed.moodCycleHours, 24)
        }
    }

    /// 清洁周期不影响收益 —— 改它不该让净结余变化。
    ///
    /// 这条锁住「清洁不在达成率公式里」这个设计（72h 周期让它长期接近
    /// 1.0，放进公式只会稀释另两维）。所以它只能做体验差异。
    func testHygieneCycleDoesNotAffectEarnings() {
        let base = PetBreed.cat
        let variant = PetBreed(
            id: "variant", nameKey: base.nameKey, layout: base.layout,
            price: base.price,
            traitKey: base.traitKey,
            moodCycleHours: base.moodCycleHours,
            hygieneCycleHours: 96,          // 只改这个
            goldMultiplier: base.goldMultiplier)

        for n in [1, 2, 3, 4] {
            XCTAssertEqual(netDaily(breed: base, stage: .adult, feedsPerDay: n),
                           netDaily(breed: variant, stage: .adult, feedsPerDay: n),
                           "清洁周期不该影响收益")
        }
    }
}

/// 界面结构的静态检查。
///
/// 这类"不看运行时、只扫源码"的测试很少写，但这次值得：
/// 我把 `ShopView` / `AchievementsView` 从 NavigationLink 目标改成 sheet 时，
/// 它们没有自己的 `NavigationStack` —— 结果**整页没有标题栏也没法关掉**。
/// 编译能过、测试全绿，只有真机点进去才发现。
final class ViewStructureTests: XCTestCase {

    /// 剥掉注释的源码。
    ///
    /// **必须剥注释再匹配。** 第一版 `testSheetPresentedViewsAreDismissable`
    /// 直接 `src.contains("NavigationStack")`，我注入回归自测时它没抓到 ——
    /// 因为那行注释里就写着「自带 NavigationStack」，字符串照样命中。
    /// 讽刺的是 `tools/check_layers.sh` 早就踩过同一个坑并剥了注释。
    private func code(_ name: String) throws -> String {
        try source(name).split(separator: "\n").map { line -> String in
            guard let i = line.range(of: "//") else { return String(line) }
            return String(line[line.startIndex..<i.lowerBound])
        }.joined(separator: "\n")
    }

    private func source(_ name: String) throws -> String {
        // 从测试 bundle 回溯到源码目录。
        // #filePath 指向本文件，Tests 与 Sources 同级。
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/
            .deletingLastPathComponent()      // 项目根
        let url = here.appendingPathComponent("Sources/Views/\(name).swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 以 sheet 形式出现的页面必须能关掉。
    ///
    /// 判据：有 `dismiss` 环境变量 + 有 `NavigationStack`（提供标题栏容器）。
    /// 缺任何一个，用户就会卡在那一页 —— 除了下滑手势没有出路，
    /// 而 sheet 的下滑并不总是明显。
    func testSheetPresentedViewsAreDismissable() throws {
        // 这五个都由 PetHomeView / PetsView 以 .sheet 弹出
        for name in ["ShopView", "AchievementsView", "PetsView",
                     "EarningsView", "PetSettingsView"] {
            let src = try code(name)
            XCTAssertTrue(src.contains("Environment(\\.dismiss)"),
                          "\(name) 是 sheet，但没有 dismiss —— 关不掉")
            XCTAssertTrue(src.contains("NavigationStack"),
                          "\(name) 是 sheet，但没有 NavigationStack —— 没有标题栏放关闭按钮")
            XCTAssertTrue(src.contains("common.done"),
                          "\(name) 缺「完成」按钮")
        }
    }

    /// 设置页只该有应用级偏好。
    ///
    /// 宠物相关的东西已经全部搬到宠物页 —— 这条断言防止以后又
    /// 「没想清楚放哪就先扔设置里」。
    func testSettingsHasNoPetSpecificContent() throws {
        let src = try code("PetSettingsView")
        for banned in ["BreedPortrait", "CoatPicker", "stageProgress",
                       "totalFeedCount", "store.rename"] {
            XCTAssertFalse(src.contains(banned),
                           "设置页出现了宠物相关内容 \(banned) —— 该放宠物页")
        }
    }

    /// AI 台词功能已整个移除，不该有残留引用。
    func testNoAIReferencesRemain() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources,
                                                   includingPropertiesForKeys: nil)!
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            // **剥掉注释再匹配。** 注释里的「曾经有过 AI，为什么删」
            // 是有意保留的历史说明 —— 那是这个项目记录决策的方式，
            // 不该被当成残留。只有真的代码引用才算。
            let code = src.split(separator: "\n")
                .map { line -> String in
                    guard let i = line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<i.lowerBound])
                }
                .joined(separator: "\n")
            for sym in ["PetChatEngine", "BPETokenizer", "aiEnabled",
                        "englishStateDescription", "chineseStateDescription"] {
                if code.contains(sym) {
                    offenders.append("\(url.lastPathComponent): \(sym)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "AI 残留：\(offenders)")
    }
}

/// 图标来源的静态检查。
///
/// **为什么需要**：SF Symbol 和 emoji 都依赖系统字体。字体缺失、
/// 旧系统没有那个符号名、或模拟器字体没装全时，整个图标会渲染成
/// 问号或豆腐块 —— 而这是像素风 app 里最扎眼的破图。
///
/// 项目的所有图标都来自自绘的 `Assets/ui/icons.png`
/// （`tools/make_ui_icons.py`，形状原创、零授权负担）。
final class IconSourceTests: XCTestCase {

    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    /// 遍历 Sources 下所有 swift 文件的**代码部分**（剥掉注释）
    private func eachCodeLine(_ body: (String, Int, String) -> Void) throws {
        let files = FileManager.default.enumerator(at: sourcesRoot,
                                                   includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            for (i, raw) in src.split(separator: "\n",
                                      omittingEmptySubsequences: false).enumerated() {
                // 剥注释 —— 注释里写"曾经用 SF Symbol"是有意保留的历史说明
                let line = raw.range(of: "//").map { String(raw[raw.startIndex..<$0.lowerBound]) }
                    ?? String(raw)
                body(url.lastPathComponent, i + 1, line)
            }
        }
    }

    /// **不得使用 SF Symbol。**
    func testNoSystemSymbols() throws {
        var offenders: [String] = []
        try eachCodeLine { file, line, code in
            for api in ["systemName:", "systemImage:"] where code.contains(api) {
                offenders.append("\(file):\(line) \(api)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "用了 SF Symbol，缺字体会变问号：\(offenders)")
    }

    /// **代码里不得出现 emoji 或其它需要字体支持的符号字形。**
    ///
    /// 允许 CJK（台词、注释里的中文）和全角标点，
    /// 拦的是 emoji、装饰符号、几何图形这些字形。
    func testNoEmojiOrSymbolGlyphsInCode() throws {
        var offenders: [String] = []
        try eachCodeLine { file, line, code in
            for ch in code {
                let v = ch.unicodeScalars.first!.value
                guard v > 0x2000 else { continue }            // ASCII 与常见空白
                if (0x3000...0x9FFF).contains(v) { continue } // CJK
                if (0xFF00...0xFFEF).contains(v) { continue } // 全角
                offenders.append("\(file):\(line) \(ch) U+\(String(v, radix: 16))")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "代码里有依赖字体的符号字形：\(offenders)")
    }

    /// `PetNeed.iconIndex` 必须和 Views 层 `PixelIcon` 的顺序对得上。
    ///
    /// 两边是**同一张 sheet 的索引**，但因为分层规则不能互相引用
    /// （Models 不得引用 Views），只能靠测试锁住。
    func testNeedIconIndicesMatchPixelIcon() {
        let expected: [PetNeed: PixelIcon] = [
            .hungry: .meat, .bored: .ball, .dirty: .bath,
            .sleepy: .sleep, .content: .heart,
        ]
        for (need, icon) in expected {
            XCTAssertEqual(need.iconIndex, icon.rawValue,
                           "\(need) 的图标索引对不上 \(icon)")
        }
        // 顺带确认 forNeed 也一致
        for (need, icon) in expected {
            XCTAssertEqual(PixelIcon.forNeed(need), icon)
        }
    }

    /// sheet 里的图标数量要和枚举 case 数一致。
    ///
    /// 加图标时忘了跑 `make_ui_icons.py`（或反之）会错位 ——
    /// 索引 13 本该是店铺，结果画出个爪印。
    func testIconSheetMatchesEnumCount() throws {
        let url = Bundle.main.url(forResource: PixelIcon.sheetName,
                                  withExtension: "png")
        let path = try XCTUnwrap(url, "找不到 icons.png")
        let img = try XCTUnwrap(UIImage(contentsOfFile: path.path))
        let cells = Int((img.size.width / PixelIcon.cell).rounded())
        XCTAssertEqual(cells, PixelIcon.allCases.count,
                       "sheet 有 \(cells) 格，但枚举有 \(PixelIcon.allCases.count) 个 case")
        XCTAssertEqual(img.size.height, PixelIcon.cell)
    }
}

/// 隐私声明必须与代码事实一致。
///
/// 「关于」页写着「完全离线，不发起任何网络请求」——
/// 这是对用户的承诺，也可能被 App Store 审核核对。
/// 万一将来有人加了网络请求（哪怕只是拉个更新检查），
/// 那句话就变成谎话了。用测试守住它，而不是靠记性。
final class PrivacyClaimTests: XCTestCase {

    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func allCode() throws -> [(file: String, code: String)] {
        let files = FileManager.default.enumerator(at: sourcesRoot,
                                                  includingPropertiesForKeys: nil)!
        var out: [(String, String)] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            // 剥注释 —— 注释里提到 URLSession 是说明性文字，不是真的用了
            let code = src.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let i = line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<i.lowerBound])
                }
                .joined(separator: "\n")
            out.append((url.lastPathComponent, code))
        }
        return out
    }

    /// **不得有任何网络请求。**
    func testNoNetworkingAPIs() throws {
        let banned = ["URLSession", "URLRequest", "NWConnection",
                      "CFSocket", "Network.framework"]
        var offenders: [String] = []
        for (file, code) in try allCode() {
            for api in banned where code.contains(api) {
                offenders.append("\(file): \(api)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "「关于」页声明完全离线，但发现网络 API：\(offenders)")
    }

    /// 不得引入统计/广告 SDK
    func testNoAnalyticsOrAds() throws {
        let banned = ["FirebaseAnalytics", "GoogleMobileAds", "AppsFlyer",
                      "Adjust", "Mixpanel", "Sentry", "Bugsnag",
                      "ATTrackingManager", "ASIdentifierManager"]
        var offenders: [String] = []
        for (file, code) in try allCode() {
            for sdk in banned where code.contains(sdk) {
                offenders.append("\(file): \(sdk)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "「关于」页声明无统计无广告，但发现：\(offenders)")
    }

    /// 不得读取通讯录/相册/定位这类敏感数据
    func testNoSensitiveDataAccess() throws {
        let banned = ["CNContactStore", "PHPhotoLibrary", "CLLocationManager",
                      "HKHealthStore", "AVCaptureDevice", "EKEventStore"]
        var offenders: [String] = []
        for (file, code) in try allCode() {
            for api in banned where code.contains(api) {
                offenders.append("\(file): \(api)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, "发现敏感数据访问：\(offenders)")
    }

    /// 「关于」页的每条文案都要有译文
    func testAboutTextIsLocalized() {
        let keys = ["about.title", "about.app_name", "about.tagline",
                    "about.what.title", "about.what.body",
                    "about.how.title", "about.how.body",
                    "about.privacy.title", "about.privacy.offline",
                    "about.privacy.local", "about.privacy.no_account",
                    "about.privacy.notify", "about.privacy.delete",
                    "about.assets.title", "about.assets.body"]
        for k in keys {
            XCTAssertNotEqual(L(k), k, "\(k) 缺译文 —— 关于页会显示 key 本身")
            XCTAssertFalse(L(k).isEmpty)
        }
    }
}

/// 提醒阈值。
final class ReminderThresholdTests: XCTestCase {

    /// 档位要包含「关闭」，且都在合理范围
    func testOptionsAreSane() {
        let opts = PetNotifications.Threshold.options
        XCTAssertTrue(opts.contains(0), "要有关闭档")
        for o in opts {
            XCTAssertGreaterThanOrEqual(o, 0)
            XCTAssertLessThanOrEqual(o, 0.5, "提醒线高于 50% 会太吵")
        }
        XCTAssertEqual(opts, opts.sorted(), "档位应升序，UI 直接按顺序渲染")
    }

    /// 默认值：饱食和心情开，清洁关（72h 周期，提醒会显得多余）
    func testDefaultsAreReasonable() {
        // 清掉可能残留的用户设置再读默认
        for k in ["notifyThresholdSatiety", "notifyThresholdMood",
                  "notifyThresholdHygiene"] {
            UserDefaults.standard.removeObject(forKey: k)
        }
        XCTAssertEqual(PetNotifications.Threshold.satiety, 0.15, accuracy: 0.001)
        XCTAssertEqual(PetNotifications.Threshold.mood, 0.20, accuracy: 0.001)
        XCTAssertEqual(PetNotifications.Threshold.hygiene, 0, accuracy: 0.001,
                       "清洁默认不提醒")
    }

    /// 存取能往返，且 0 表示关闭
    func testPersistsAndZeroMeansOff() {
        PetNotifications.Threshold.satiety = 0.3
        XCTAssertEqual(PetNotifications.Threshold.satiety, 0.3, accuracy: 0.001)

        PetNotifications.Threshold.satiety = 0
        XCTAssertEqual(PetNotifications.Threshold.satiety, 0, accuracy: 0.001)

        // 还原默认，别影响别的测试
        UserDefaults.standard.removeObject(forKey: "notifyThresholdSatiety")
    }
}

/// 家具与商店分类。
final class FurnitureTests: XCTestCase {

    /// sheet 索引必须和生成脚本的 ORDER 一致。
    ///
    /// 两边是**同一张图的格位**，脚本改了顺序而 Swift 没跟着改，
    /// 就会「买了床摆出个碗」。加家具只能追加到末尾。
    func testSheetIndicesMatchScript() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(
            contentsOf: root.appendingPathComponent("tools/make_furniture.py"),
            encoding: .utf8)

        // 从脚本里抓 ORDER = [...]
        guard let r = script.range(of: "ORDER = ["),
              let end = script.range(of: "]", range: r.upperBound..<script.endIndex)
        else { return XCTFail("脚本里找不到 ORDER") }
        let ids = script[r.upperBound..<end.lowerBound]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\"\n")) }
            .filter { !$0.isEmpty }

        for item in FurnitureItem.all {
            guard item.sheetIndex < ids.count else {
                return XCTFail("\(item.id) 的 sheetIndex \(item.sheetIndex) 超出脚本 ORDER")
            }
            XCTAssertEqual(ids[item.sheetIndex], item.id,
                           "索引 \(item.sheetIndex) 脚本里是 \(ids[item.sheetIndex])，"
                           + "Swift 里是 \(item.id)")
        }
    }

    /// sheet 实际尺寸要能放下所有家具
    func testSheetIsBigEnough() throws {
        let url = Bundle.main.url(forResource: "furniture", withExtension: "png")
        let path = try XCTUnwrap(url, "找不到 furniture.png")
        let img = try XCTUnwrap(UIImage(contentsOfFile: path.path))

        let slot = FurnitureItem.cell * 2
        let needed = slot * CGFloat(FurnitureItem.all.count)
        XCTAssertGreaterThanOrEqual(img.size.width, needed,
                                    "sheet 宽 \(img.size.width) 放不下 "
                                    + "\(FurnitureItem.all.count) 件")
        XCTAssertEqual(img.size.height, FurnitureItem.cell)
    }

    /// 碗的容量按侧视定 —— 只排左右两侧，不排上下
    func testBowlCapacities() {
        XCTAssertEqual(FurnitureItem.bowl.feedSlots, 2, "圆碗左右各一")
        XCTAssertEqual(FurnitureItem.longBowl.feedSlots, 4, "长碗左右各两")
        XCTAssertTrue(FurnitureItem.bowl.isBowl)
        XCTAssertFalse(FurnitureItem.bed.isBowl, "床是装饰，没有吃饭位")
        XCTAssertFalse(FurnitureItem.plant.isBowl)
    }

    /// 装饰品不该有吃饭位，用品才有
    func testCategoriesMatchFunction() {
        for item in FurnitureItem.all {
            switch item.category {
            case .supply:
                XCTAssertTrue(item.isBowl, "\(item.id) 在用品分类却没有功能")
            case .decor:
                XCTAssertFalse(item.isBowl, "\(item.id) 是装饰却有吃饭位")
            case .pet:
                XCTFail("家具不该归到宠物分类")
            }
        }
    }

    /// 每件家具与每个分类都要有译文
    func testFurnitureIsLocalized() {
        for item in FurnitureItem.all {
            XCTAssertNotEqual(L(item.nameKey), item.nameKey,
                              "\(item.id) 缺译文")
        }
        for c in ShopCategory.allCases {
            XCTAssertNotEqual(L(c.nameKey), c.nameKey, "\(c.rawValue) 缺译文")
        }
    }

    /// id 与索引都不能重复
    func testNoDuplicates() {
        let ids = FurnitureItem.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id 重复")
        let idx = FurnitureItem.all.map(\.sheetIndex)
        XCTAssertEqual(Set(idx).count, idx.count, "sheetIndex 重复 —— 会取到同一张图")
    }

    /// 家具尺寸不能占掉半个屏幕
    func testDisplayScaleKeepsFurnitureReasonable() {
        // iPhone 15 Pro Max 逻辑宽 440pt
        let screenW: CGFloat = 440
        for item in FurnitureItem.all {
            let w = FurnitureItem.cell * CGFloat(item.cellWidth)
                * FurnitureItem.displayScale
            XCTAssertLessThan(w / screenW, 0.5,
                              "\(item.id) 宽 \(w)pt，占了屏宽一半以上")
        }
    }
}

/// 家具的购买与摆放。
@MainActor
final class FurniturePurchaseTests: StoreTestCase {

    func testBuyingFurnitureDeductsAndUnlocks() {
        let s = makeStore()
        var w = s.wallet
        w.debugSetCoins(5000)
        s.debugSet(wallet: w)

        XCTAssertFalse(s.owns(FurnitureItem.bowl))
        XCTAssertTrue(s.purchase(FurnitureItem.bowl))
        XCTAssertTrue(s.owns(FurnitureItem.bowl))
        XCTAssertEqual(s.wallet.coins, 5000 - FurnitureItem.bowl.price)
        XCTAssertTrue(s.wallet.ledger.isBalanced)
        XCTAssertEqual(s.wallet.ledger.recent.last?.reason, .furniture)
    }

    /// **家具是一次性解锁** —— 买过再买该失败（否则白扣钱）
    func testCannotBuyTwice() {
        let s = makeStore()
        var w = s.wallet
        w.debugSetCoins(5000)
        s.debugSet(wallet: w)

        XCTAssertTrue(s.purchase(FurnitureItem.plant))
        let after = s.wallet.coins
        XCTAssertFalse(s.purchase(FurnitureItem.plant), "重复购买该失败")
        XCTAssertEqual(s.wallet.coins, after, "重复购买不该再扣")
    }

    func testCannotAffordFails() {
        let s = makeStore()
        var w = s.wallet
        w.debugSetCoins(10)
        s.debugSet(wallet: w)
        XCTAssertFalse(s.purchase(FurnitureItem.bed))
        XCTAssertFalse(s.owns(FurnitureItem.bed))
    }

    /// **买了长碗就用长碗** —— 取容量最大的那个，不做「选哪个碗」的设置
    func testActiveBowlPicksLargestCapacity() {
        let s = makeStore()
        var w = s.wallet
        w.debugSetCoins(20000)
        s.debugSet(wallet: w)

        XCTAssertNil(s.activeBowl, "没买碗时该是 nil")

        s.purchase(FurnitureItem.bowl)
        XCTAssertEqual(s.activeBowl?.id, "bowl")

        s.purchase(FurnitureItem.longBowl)
        XCTAssertEqual(s.activeBowl?.id, "long_bowl", "有长碗就用长碗")
        XCTAssertEqual(s.activeBowl?.feedSlots, 4)
    }

    /// 装饰品不算碗
    func testDecorIsNotABowl() {
        let s = makeStore()
        var w = s.wallet
        w.debugSetCoins(20000)
        s.debugSet(wallet: w)
        s.purchase(FurnitureItem.bed)
        s.purchase(FurnitureItem.plant)
        XCTAssertNil(s.activeBowl, "买了床和盆栽不该有饭碗")
    }
}
