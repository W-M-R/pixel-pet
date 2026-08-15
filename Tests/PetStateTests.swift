import XCTest
@testable import PixelPet

final class PetStateTests: XCTestCase {

    /// 这是回归测试：曾经用「距上次玩耍的时间」算精力来决定睡觉，
    /// 导致每次抚摸都刷新 lastPlayedAt → 精力归零 → 宠物秒睡。
    /// 表现为「一点它就睡觉」。
    ///
    /// 现在睡觉只看自然作息，和互动完全无关。
    func testStrokingDoesNotCauseSleep() {
        let cal = Calendar.current
        // 取一个确定清醒的时刻：10:00
        let awakeTime = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!

        var state = PetState(species: .cat, colorIndex: 0, name: "T", now: awakeTime)
        // 模拟刚被摸过
        state.lastPlayedAt = awakeTime

        XCTAssertFalse(state.isDrowsy(at: awakeTime),
                       "10:00 刚被抚摸过，不该犯困")
    }

    func testDrowsySchedule() {
        let cal = Calendar.current
        let state = PetState(species: .cat, colorIndex: 0, name: "T")

        func drowsy(at hour: Int) -> Bool {
            let d = cal.date(bySettingHour: hour, minute: 30, second: 0, of: Date())!
            return state.isDrowsy(at: d)
        }

        // 只有深夜睡
        XCTAssertTrue(drowsy(at: 23))
        XCTAssertTrue(drowsy(at: 3))
        XCTAssertTrue(drowsy(at: 6))
        XCTAssertFalse(drowsy(at: 7))
        XCTAssertFalse(drowsy(at: 12))
        // 午休已取消 —— 曾经 14-16 点也睡，导致 42% 时间在趴着
        XCTAssertFalse(drowsy(at: 14))
        XCTAssertFalse(drowsy(at: 15))
        XCTAssertFalse(drowsy(at: 21))
    }

    /// 清醒时间必须占大头。养成类如果大半时间没事可做就废了。
    func testAwakeMajorityOfDay() {
        let cal = Calendar.current
        let state = PetState(species: .cat, colorIndex: 0, name: "T")
        let awake = (0..<24).filter { h in
            let d = cal.date(bySettingHour: h, minute: 30, second: 0, of: Date())!
            return !state.isDrowsy(at: d)
        }.count
        XCTAssertEqual(awake, 16, "应清醒 16/24 小时")
        XCTAssertGreaterThan(Double(awake) / 24.0, 0.6, "清醒时间要超过 60%")
    }

    /// 回归测试：夜里戳宠物能叫醒，且不会被下一次心跳按回去睡
    func testWakeUpOverridesNightSchedule() {
        let cal = Calendar.current
        let night = cal.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!

        var state = PetState(species: .cat, colorIndex: 0, name: "T", now: night)
        XCTAssertTrue(state.isDrowsy(at: night), "凌晨2点本该睡")

        // 叫醒
        state.awakeUntil = night.addingTimeInterval(PetState.NightTime.awakeGrace)
        XCTAssertFalse(state.isDrowsy(at: night), "叫醒后应清醒")
        // 宽限期内仍清醒
        XCTAssertFalse(state.isDrowsy(at: night.addingTimeInterval(10 * 60)))
        // 宽限期过后回去睡
        XCTAssertTrue(state.isDrowsy(at: night.addingTimeInterval(25 * 60)),
                      "宽限期结束应重新犯困")
    }

    /// 状态必须按时间戳读时计算，不能存当前值 ——
    /// iOS 没有后台定时器，存快照会导致 app 关掉后数值停滞。
    func testDecayIsComputedFromTimestamps() {
        let now = Date()
        var state = PetState(species: .cat, colorIndex: 0, name: "T", now: now)

        XCTAssertEqual(state.satiety(at: now), 1.0, accuracy: 0.001,
                       "刚喂完应该是满的")

        // 周期随生命阶段变化 —— 新生宠物是幼年期（12h），不是成年的 8h
        let span = PetState.Decay.hunger(for: state.stage)

        // 把喂食时间往前推到饱食周期的一半
        state.lastFedAt = now.addingTimeInterval(-span / 2)
        XCTAssertEqual(state.satiety(at: now), 0.5, accuracy: 0.01,
                       "过了一半周期应该剩一半")

        // 超过整个周期应该钳到 0，不能变负
        state.lastFedAt = now.addingTimeInterval(-span * 3)
        XCTAssertEqual(state.satiety(at: now), 0.0, accuracy: 0.001)
    }

    /// 生理需求优先于困倦：饿着的时候不该只提示「困了」
    func testPhysicalNeedsOutrankDrowsiness() {
        let cal = Calendar.current
        let nightTime = cal.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!

        var state = PetState(species: .cat, colorIndex: 0, name: "T", now: nightTime)
        state.lastFedAt = nightTime.addingTimeInterval(
            -PetState.Decay.hunger(for: state.stage))

        XCTAssertTrue(state.isDrowsy(at: nightTime), "凌晨2点本该犯困")
        XCTAssertEqual(state.dominantNeed(at: nightTime), .hungry,
                       "饿透了应该优先报饿，而不是困")
    }

    func testFrameGeometryConstantsMatchAsset() {
        // 食盆/影子/气泡的位置都依赖这两个常量。
        // 曾经硬编码 -24pt，导致食盆落在宠物头上。
        XCTAssertEqual(PetSpriteSheet.frameSize.width, 32)
        XCTAssertEqual(PetSpriteSheet.frameSize.height, 32)
        XCTAssertEqual(PetSpriteSheet.columnsPerColor, 4)
        XCTAssertEqual(PetSpriteSheet.colorCount, 4)
    }
}

// MARK: - 地板平面（2.5D 走动）

final class FloorPlaneTests: XCTestCase {

    private func makeFloor() -> FloorPlane {
        FloorPlane(backY: 280, frontY: 50, width: 400)
    }

    func testDepthMapping() {
        let f = makeFloor()
        XCTAssertEqual(f.depth(atY: 50), 0, accuracy: 0.001, "前缘 = depth 0")
        XCTAssertEqual(f.depth(atY: 280), 1, accuracy: 0.001, "墙脚 = depth 1")
        XCTAssertEqual(f.depth(atY: 165), 0.5, accuracy: 0.01, "中点 = depth 0.5")
        // 越界要钳住
        XCTAssertEqual(f.depth(atY: -100), 0)
        XCTAssertEqual(f.depth(atY: 9999), 1)
    }

    func testDepthYRoundTrip() {
        let f = makeFloor()
        for d in stride(from: 0.0, through: 1.0, by: 0.1) {
            let y = f.y(atDepth: CGFloat(d))
            XCTAssertEqual(f.depth(atY: y), CGFloat(d), accuracy: 0.001)
        }
    }

    /// 远处可行走范围必须比近处窄 —— 这是透视成立的前提
    func testPerspectiveNarrowsWithDepth() {
        let f = makeFloor()
        let near = f.xRange(atDepth: 0)
        let far = f.xRange(atDepth: 1)
        let nearWidth = near.upperBound - near.lowerBound
        let farWidth = far.upperBound - far.lowerBound
        XCTAssertGreaterThan(nearWidth, farWidth, "远处应该更窄")
        XCTAssertEqual(nearWidth, 400, accuracy: 0.001, "最近处占满屏宽")
    }

    /// 远处宠物必须更小
    func testScaleShrinksWithDepth() {
        let f = makeFloor()
        XCTAssertEqual(f.scaleFactor(atDepth: 0), 1, accuracy: 0.001)
        XCTAssertLessThan(f.scaleFactor(atDepth: 1), f.scaleFactor(atDepth: 0))
        XCTAssertEqual(f.scaleFactor(atDepth: 1), f.minScaleRatio, accuracy: 0.001)
    }

    /// clamp 必须把任意点拉回地板内，且尊重该深度的横向范围
    func testClampKeepsPointOnFloor() {
        let f = makeFloor()
        // 远处角落：x 应该被推进梯形内
        let c = f.clamp(CGPoint(x: 0, y: 280))
        XCTAssertGreaterThan(c.x, 0, "远处最左应被内缩")
        XCTAssertEqual(c.y, 280, accuracy: 0.001)

        // 超出上下界
        XCTAssertEqual(f.clamp(CGPoint(x: 200, y: 9999)).y, 280, accuracy: 0.001)
        XCTAssertEqual(f.clamp(CGPoint(x: 200, y: -50)).y, 50, accuracy: 0.001)
    }

    // MARK: - 深度缩放（修「走动时一闪一闪」）

    /// 缩放必须**连续**，不能有离散跳档。
    ///
    /// 曾经把缩放量化到 1/3 网格（Unity Pixel Perfect Camera 的思路），
    /// 但那套方案要求全场景共用一个像素网格 —— 伪深度让每只宠物在不同 y
    /// 有不同缩放，前提不成立。实测 young 全程只剩 3.0/2.667/2.333 三档，
    /// 相邻档差 11%，走动时「猛地缩一下」，比原本的抖动更刺眼。
    ///
    /// 现在靠 `PetSpriteSheet.prescale`（nearest 整数预放大 + linear 连续
    /// 缩小）解决采样问题，缩放本身保持连续。这个测试防量化回归。
    func testPetScaleIsContinuous() {
        let f = makeFloor()
        var distinct = Set<CGFloat>()
        for i in 0...100 {
            let s = f.petScale(pixelScale: 4, bodyScale: 1.0,
                               depth: CGFloat(i) / 100)
            distinct.insert((s * 10000).rounded() / 10000)
        }
        XCTAssertGreaterThan(distinct.count, 50,
                             "缩放应连续变化，出现离散档位说明又被量化了")
    }

    /// 相邻深度的缩放差必须很小 —— 大跳变就是肉眼可见的「闪」
    func testPetScaleHasNoLargeJumps() {
        let f = makeFloor()
        var prev = f.petScale(pixelScale: 4, bodyScale: 1.0, depth: 0)
        for i in 1...200 {
            let s = f.petScale(pixelScale: 4, bodyScale: 1.0,
                               depth: CGFloat(i) / 200)
            let jump = abs(s - prev) / prev
            XCTAssertLessThan(jump, 0.01,
                              "depth \(Double(i)/200) 处缩放跳变 \(jump * 100)%，应 <1%")
            prev = s
        }
    }

    /// 远处仍须更小
    func testPetScaleShrinksWithDepth() {
        let f = makeFloor()
        let near = f.petScale(pixelScale: 4, bodyScale: 1.0, depth: 0)
        let far = f.petScale(pixelScale: 4, bodyScale: 1.0, depth: 1)
        XCTAssertLessThan(far, near)
        XCTAssertEqual(far / near, f.minScaleRatio, accuracy: 0.001)
    }

    /// 单调性
    func testPetScaleIsMonotonic() {
        let f = makeFloor()
        var prev = CGFloat.greatestFiniteMagnitude
        for i in 0...100 {
            let s = f.petScale(pixelScale: 4, bodyScale: 1.0,
                               depth: CGFloat(i) / 100)
            XCTAssertLessThanOrEqual(s, prev + 0.0001)
            prev = s
        }
    }

    /// 预放大倍数必须是整数且 >1 —— 非整数放大会先糊一次像素画
    func testPrescaleIsIntegerAndGreaterThanOne() {
        XCTAssertGreaterThan(PetSpriteSheet.prescale, 1)
        XCTAssertEqual(PetSpriteSheet.prescale,
                       Int(PetSpriteSheet.prescale),
                       "必须是整数倍放大")
    }

    func testRandomPointsAlwaysOnFloor() {
        let f = makeFloor()
        for _ in 0..<500 {
            let p = f.randomPoint()
            XCTAssertGreaterThanOrEqual(p.y, f.frontY)
            XCTAssertLessThanOrEqual(p.y, f.backY)
            let range = f.xRange(atDepth: f.depth(atY: p.y))
            XCTAssertGreaterThanOrEqual(p.x, range.lowerBound)
            XCTAssertLessThanOrEqual(p.x, range.upperBound)
        }
    }
}

// MARK: - Sprite sheet 帧数

final class PetSpriteSheetTests: XCTestCase {

    /// 回归测试：正视/背视只有 3 帧，第 4 格不可用。
    ///
    /// 猫的第 4 格是空的；狗的第 4 格非空但是另一个姿态
    /// （侧躺的狗，宽 25-27px vs 正常 11px）。
    /// 两种都会造成宠物朝前/朝后走时画面突变 —— 即「头尾分离」。
    func testFrontBackHaveThreeFrames() {
        XCTAssertEqual(PetSpriteSheet.frameCount(row: PetSpriteSheet.Facing.front.row), 3)
        XCTAssertEqual(PetSpriteSheet.frameCount(row: PetSpriteSheet.Facing.back.row), 3)
    }

    func testSideAndEatHaveFourFrames() {
        XCTAssertEqual(PetSpriteSheet.frameCount(row: PetSpriteSheet.Facing.right.row), 4)
        XCTAssertEqual(PetSpriteSheet.frameCount(row: PetSpriteSheet.Facing.left.row), 4)
        XCTAssertEqual(PetSpriteSheet.frameCount(row: 4), 4, "进食行是 4 帧")
    }
}

// MARK: - 生命阶段与品种抽象

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
