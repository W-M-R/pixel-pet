import XCTest
@testable import PixelPet

/// 宠物状态与阈值。时间戳驱动的衰减、作息、需求判定。

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

final class StateThresholdTests: XCTestCase {

    func testLevelBoundaries() {
        XCTAssertEqual(StateThreshold.level(0.0), .critical)
        XCTAssertEqual(StateThreshold.level(0.24), .critical)
        XCTAssertEqual(StateThreshold.level(0.25), .low)
        XCTAssertEqual(StateThreshold.level(0.49), .low)
        XCTAssertEqual(StateThreshold.level(0.5), .ok)
        XCTAssertEqual(StateThreshold.level(0.79), .ok)
        XCTAssertEqual(StateThreshold.level(0.8), .high)
        XCTAssertEqual(StateThreshold.level(1.0), .high)
    }

    /// 档位必须可比较 —— `<= .low` 这类写法依赖它
    func testLevelIsOrdered() {
        XCTAssertLessThan(StateThreshold.Level.critical, .low)
        XCTAssertLessThan(StateThreshold.Level.low, .ok)
        XCTAssertLessThan(StateThreshold.Level.ok, .high)
    }

    /// **中英文 prompt 必须描述出同样的状态。**
    ///
    /// 这是集中阈值的核心目的 —— 扫一遍状态空间，


    /// HUD 报警线要比台词的「一般」档宽松 ——
    /// 状态栏一直报警会让人焦虑，台词是低频触发可以更严
    func testHudAlertIsLooserThanLineThresholds() {
        XCTAssertGreaterThan(StateThreshold.hudAlert, StateThreshold.lineUrgent)
        XCTAssertLessThan(StateThreshold.hudAlert, StateThreshold.low)
    }
}

/// 品种的几何参数。
