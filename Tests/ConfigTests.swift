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
            XCTAssertLessThan(b.footPadding, PetSpriteSheet.frameSize.height / 2,
                              "\(b.id) 的 footPadding 过大")
        }
    }

    /// 中英文物种称呼都要有 —— 原来中文是硬编码三元，加品种会显示错
    func testEveryBreedHasBothNouns() {
        for b in PetBreed.all {
            XCTAssertFalse(b.englishNoun.isEmpty)
            XCTAssertFalse(b.chineseNoun.isEmpty)
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
