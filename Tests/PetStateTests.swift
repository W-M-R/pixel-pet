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

        // 夜间
        XCTAssertTrue(drowsy(at: 23))
        XCTAssertTrue(drowsy(at: 3))
        XCTAssertTrue(drowsy(at: 6))
        // 白天清醒
        XCTAssertFalse(drowsy(at: 7))
        XCTAssertFalse(drowsy(at: 12))
        // 午休
        XCTAssertTrue(drowsy(at: 14))
        XCTAssertTrue(drowsy(at: 15))
        XCTAssertFalse(drowsy(at: 16))
        // 傍晚清醒
        XCTAssertFalse(drowsy(at: 21))
    }

    /// 状态必须按时间戳读时计算，不能存当前值 ——
    /// iOS 没有后台定时器，存快照会导致 app 关掉后数值停滞。
    func testDecayIsComputedFromTimestamps() {
        let now = Date()
        var state = PetState(species: .cat, colorIndex: 0, name: "T", now: now)

        XCTAssertEqual(state.satiety(at: now), 1.0, accuracy: 0.001,
                       "刚喂完应该是满的")

        // 把喂食时间往前推到饱食周期的一半
        state.lastFedAt = now.addingTimeInterval(-PetState.Decay.hunger / 2)
        XCTAssertEqual(state.satiety(at: now), 0.5, accuracy: 0.01,
                       "过了一半周期应该剩一半")

        // 超过整个周期应该钳到 0，不能变负
        state.lastFedAt = now.addingTimeInterval(-PetState.Decay.hunger * 3)
        XCTAssertEqual(state.satiety(at: now), 0.0, accuracy: 0.001)
    }

    /// 生理需求优先于困倦：饿着的时候不该只提示「困了」
    func testPhysicalNeedsOutrankDrowsiness() {
        let cal = Calendar.current
        let nightTime = cal.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!

        var state = PetState(species: .cat, colorIndex: 0, name: "T", now: nightTime)
        state.lastFedAt = nightTime.addingTimeInterval(-PetState.Decay.hunger)

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
