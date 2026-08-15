import XCTest
@testable import PixelPet

/// 经济系统测试。
///
/// 平衡数值全部对照 docs/04-balance.md，改数值时这些测试会失败 ——
/// 那是提醒去更新文档，不是让你改断言。
final class EconomyTests: XCTestCase {

    // MARK: - 平均状态

    /// 线性衰减下梯形法是精确解
    func testAverageLevelWithinCycle() {
        // 离线 = 半个周期 → 平均 = 1 - 0.5/2 = 0.75
        XCTAssertEqual(RewardEngine.averageLevel(offlineHours: 4, cycleHours: 8),
                       0.75, accuracy: 0.001)
        // 离线 = 整个周期 → 平均 0.5
        XCTAssertEqual(RewardEngine.averageLevel(offlineHours: 8, cycleHours: 8),
                       0.5, accuracy: 0.001)
    }

    /// 超过周期后用面积法（衰减到 0 就一直是 0）
    func testAverageLevelBeyondCycle() {
        // 离线 16h，周期 8h → (8×0.5)/16 = 0.25
        XCTAssertEqual(RewardEngine.averageLevel(offlineHours: 16, cycleHours: 8),
                       0.25, accuracy: 0.001)
        XCTAssertEqual(RewardEngine.averageLevel(offlineHours: 24, cycleHours: 8),
                       0.167, accuracy: 0.01)
    }

    /// 三条线周期不同，同样离线时长下平均值差很多
    func testThreeAxesDifferByCycle() {
        let h = 12.0
        let s = RewardEngine.averageLevel(offlineHours: h, cycleHours: 8)    // 饱食
        let m = RewardEngine.averageLevel(offlineHours: h, cycleHours: 18)   // 心情
        let c = RewardEngine.averageLevel(offlineHours: h, cycleHours: 72)   // 清洁
        XCTAssertEqual(s, 0.33, accuracy: 0.02)
        XCTAssertEqual(m, 0.67, accuracy: 0.02)
        XCTAssertEqual(c, 0.92, accuracy: 0.02)
        XCTAssertLessThan(s, m, "饱食周期短，衰减更快")
        XCTAssertLessThan(m, c)
    }

    // MARK: - 状态系数（三维乘法）

    func testCoefficientBounds() {
        let low = OfflineCareReward.stateCoefficient(satiety: 0, mood: 0, hygiene: 0)
        let high = OfflineCareReward.stateCoefficient(satiety: 1, mood: 1, hygiene: 1)
        XCTAssertEqual(low, 0.58, accuracy: 0.02, "三维全空")
        XCTAssertEqual(high, 1.35, accuracy: 0.02, "三维全满")
        // 全空是全满的约 43%
        XCTAssertEqual(low / high, 0.43, accuracy: 0.03)
    }

    /// 回归测试：心情很差时收入必须明显降低（用户明确要求）
    func testLowMoodReducesEarningsSignificantly() {
        let good = OfflineCareReward.stateCoefficient(satiety: 0.9, mood: 1.0, hygiene: 0.95)
        let bad = OfflineCareReward.stateCoefficient(satiety: 0.9, mood: 0.0, hygiene: 0.95)
        let ratio = bad / good
        XCTAssertEqual(ratio, 0.58, accuracy: 0.03,
                       "心情从满到空，收益应降到约 58%")
        XCTAssertLessThan(ratio, 0.65, "心情惩罚必须足够明显")
    }

    /// 权重顺序：心情 > 饱食 > 清洁
    func testWeightOrdering() {
        // 各维度单独打到 0，看系数掉多少
        let base = OfflineCareReward.stateCoefficient(satiety: 1, mood: 1, hygiene: 1)
        let noMood = base - OfflineCareReward.stateCoefficient(satiety: 1, mood: 0, hygiene: 1)
        let noSatiety = base - OfflineCareReward.stateCoefficient(satiety: 0, mood: 1, hygiene: 1)
        let noHygiene = base - OfflineCareReward.stateCoefficient(satiety: 1, mood: 1, hygiene: 0)

        XCTAssertGreaterThan(noMood, noSatiety, "心情权重应大于饱食")
        XCTAssertGreaterThan(noSatiety, noHygiene, "饱食权重应大于清洁")
    }

    /// 乘法特性：任一维度差都会扣收益（不像加权平均会被高值掩盖）
    func testMultiplicativeNotAveraged() {
        // 若是等权平均，(0.1+1+1)/3 = 0.70；乘法会明显更低
        let oneAxisBad = OfflineCareReward.stateCoefficient(satiety: 0.1, mood: 1, hygiene: 1)
        let allGood = OfflineCareReward.stateCoefficient(satiety: 1, mood: 1, hygiene: 1)
        XCTAssertLessThan(oneAxisBad / allGood, 0.85,
                          "单一维度差应造成可感知的扣减")
    }

    // MARK: - 上线奖励

    func testCheckInRequiresInterval() {
        let rule = CheckInReward()
        XCTAssertNil(rule.evaluate(ctx(offlineHours: 1)), "间隔不足 5h 不发")
        XCTAssertNil(rule.evaluate(ctx(offlineHours: 4.9)))
        XCTAssertEqual(rule.evaluate(ctx(offlineHours: 5))?.coins, 10)
        XCTAssertEqual(rule.evaluate(ctx(offlineHours: 100))?.coins, 10, "只发一份，不累积")
    }

    // MARK: - 看家收益

    func testOfflineCapAt10Hours() {
        let rule = OfflineCareReward()
        // 离线 10h 与 20h：时长都按 10h 算，但 20h 的状态更差所以更少
        let c10 = rule.evaluate(realCtx(offlineHours: 10))?.coins ?? 0
        let c20 = rule.evaluate(realCtx(offlineHours: 20))?.coins ?? 0
        XCTAssertLessThanOrEqual(c20, c10, "超过上限后收益不增反降")
        XCTAssertLessThan(c10, 150, "10h 收益应在 100 枚上下，不该暴富")
    }

    /// 收益在 10h（时长上限）达峰后下降
    func testEarningsPeakThenDecline() {
        let rule = OfflineCareReward()
        let series = [5.0, 8, 10, 12, 24, 48].map {
            rule.evaluate(realCtx(offlineHours: $0))?.coins ?? 0
        }
        let peak = series.max() ?? 0
        XCTAssertEqual(peak, series[2], "峰值应在 10h")
        XCTAssertLessThan(series[5], series[2], "48h 应低于峰值")
    }

    func testTooShortOfflineNoReward() {
        XCTAssertNil(OfflineCareReward().evaluate(realCtx(offlineHours: 0.2)),
                     "不足半小时不结算，避免频繁开关刷零碎收益")
    }

    func testBoostMultiplier() {
        let rule = OfflineCareReward()
        var boosted = PetWallet()
        boosted.boostUntil = Date().addingTimeInterval(3600)

        let plain = rule.evaluate(realCtx(offlineHours: 8))?.coins ?? 0
        let withBoost = rule.evaluate(realCtx(offlineHours: 8, wallet: boosted))?.coins ?? 0
        XCTAssertGreaterThan(withBoost, plain, "buff 生效期内收益更高")
    }

    // MARK: - 平衡回归（对照 docs/04-balance.md）

    /// 一天 4 次、全吃普通粮 → 结余约 +0.5 枚
    func testBalance4TimesPerDay() {
        let income = simulateDay(offlineSegments: [8, 5, 5, 6])
        let cost = FoodItem.kibble.price * 4
        let net = income - Double(cost)
        XCTAssertEqual(net, 6, accuracy: 25, "4 次/天结余应接近 0")
    }

    func testBalance2TimesPerDay() {
        let income = simulateDay(offlineSegments: [12, 12])
        let net = income - Double(FoodItem.kibble.price * 2)
        XCTAssertEqual(net, 56, accuracy: 25)
    }

    func testBalance1TimePerDay() {
        let income = simulateDay(offlineSegments: [24])
        let net = income - Double(FoodItem.kibble.price)
        XCTAssertEqual(net, 12, accuracy: 25)
    }

    /// 只喂食不陪玩会倒亏 —— 这是"不能只喂饭"的设计意图
    func testFeedOnlyWithoutPlayLosesMoney() {
        // 心情钉在很低的水平
        let income = simulateDay(offlineSegments: [8, 5, 5, 6], moodOverride: 0.15)
        let net = income - Double(FoodItem.kibble.price * 4)
        XCTAssertLessThan(net, 0, "一天 4 次却不陪玩应入不敷出")
    }

    // MARK: - 辅助

    private func ctx(offlineHours: Double) -> RewardContext {
        RewardContext(pet: PetState(), wallet: PetWallet(), now: Date(),
                      offlineHours: offlineHours,
                      avgSatiety: 0.5, avgMood: 0.5, avgHygiene: 0.9)
    }

    /// 用真实衰减算出三维平均值的上下文
    private func realCtx(offlineHours h: Double,
                         wallet: PetWallet = PetWallet(),
                         moodOverride: Double? = nil) -> RewardContext {
        RewardContext(
            pet: PetState(), wallet: wallet, now: Date(), offlineHours: h,
            avgSatiety: RewardEngine.averageLevel(offlineHours: h, cycleHours: 8),
            avgMood: moodOverride
                ?? RewardEngine.averageLevel(offlineHours: h, cycleHours: 18),
            avgHygiene: RewardEngine.averageLevel(offlineHours: h, cycleHours: 72))
    }

    /// 模拟一天的总收入（看家 + 上线）
    private func simulateDay(offlineSegments: [Double],
                             moodOverride: Double? = nil) -> Double {
        let care = OfflineCareReward()
        let checkIn = CheckInReward()
        var total = 0.0
        for h in offlineSegments {
            let c = realCtx(offlineHours: h, moodOverride: moodOverride)
            total += Double(care.evaluate(c)?.coins ?? 0)
            total += Double(checkIn.evaluate(c)?.coins ?? 0)
        }
        return total
    }
}
