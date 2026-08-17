import XCTest
@testable import PixelPet

/// 经济系统测试。
///
/// 平衡数值全部对照 docs/04-balance.md，改数值时这些测试会失败 ——
/// 那是提醒去更新文档，不是让你改断言。
///
/// ⚠️ 支出用「逐餐取整」，与理论值有 ±4% 偏差（周期除不尽 24 时更明显），
/// 所以收支类断言一律留容差，不写精确相等。
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

    /// 两条线周期不同，同样离线时长下平均值差很多
    func testAxesDifferByCycle() {
        let h = 12.0
        let s = RewardEngine.averageLevel(offlineHours: h, cycleHours: 8)    // 饱食
        let m = RewardEngine.averageLevel(offlineHours: h, cycleHours: 18)   // 心情
        XCTAssertEqual(s, 0.33, accuracy: 0.02)
        XCTAssertEqual(m, 0.67, accuracy: 0.02)
        XCTAssertLessThan(s, m, "饱食周期短，衰减更快")
    }

    // MARK: - 阶段参数

    /// 硬约束：每日额度必须大于该阶段的日常粮钱，否则新手期怎么玩都亏
    func testDailyCapExceedsDailyFoodCost() {
        for stage in PetStage.allCases {
            let dailyRestore = 24.0 / stage.hungerCycleHours     // 一天要补的饱食量
            let cost = dailyRestore * 10 * Double(FoodItem.coinsPer10Percent)
            XCTAssertGreaterThan(Double(stage.dailyCap), cost,
                                 "\(stage) 额度 \(stage.dailyCap) 不足以覆盖日常粮钱 \(Int(cost))")
        }
    }

    /// 小宠物吃得少：周期随成长变短
    func testHungerCycleShortensWithGrowth() {
        XCTAssertGreaterThan(PetStage.young.hungerCycleHours,
                             PetStage.growing.hungerCycleHours)
        XCTAssertGreaterThan(PetStage.growing.hungerCycleHours,
                             PetStage.adult.hungerCycleHours)
    }

    /// 额度梯度：成年最高，老年回落但高于幼年
    func testDailyCapOrdering() {
        XCTAssertLessThan(PetStage.young.dailyCap, PetStage.growing.dailyCap)
        XCTAssertLessThan(PetStage.growing.dailyCap, PetStage.adult.dailyCap)
        XCTAssertLessThan(PetStage.elder.dailyCap, PetStage.adult.dailyCap)
        XCTAssertGreaterThan(PetStage.elder.dailyCap, PetStage.young.dailyCap)
    }

    // MARK: - 达成率

    func testRateBounds() {
        let low = OfflineCareReward.achievementRate(satiety: 0, mood: 0)
        let high = OfflineCareReward.achievementRate(satiety: 1, mood: 1)
        XCTAssertEqual(low, 0.05, accuracy: 0.001, "全空")
        XCTAssertEqual(high, 0.35, accuracy: 0.001, "全满")
    }

    /// 上界必须显著小于 1.0 —— 否则一次结算就领满额度，
    /// 「开 1 次」和「开 5 次」收入相同，激励结构失效。
    func testRateCannotFillCapInOneSettlement() {
        let best = OfflineCareReward.achievementRate(satiety: 1, mood: 1)
        XCTAssertLessThan(best, 0.5,
                          "单次达成率过高会让额度一次领满，失去「多照顾多赚」的激励")
    }

    /// 心情权重高于饱食
    func testMoodWeighsMoreThanSatiety() {
        let base = OfflineCareReward.achievementRate(satiety: 1, mood: 1)
        let noMood = base - OfflineCareReward.achievementRate(satiety: 1, mood: 0)
        let noSatiety = base - OfflineCareReward.achievementRate(satiety: 0, mood: 1)
        XCTAssertGreaterThan(noMood, noSatiety, "心情权重应大于饱食")
    }

    /// 状态必须真正影响收益 —— 这是「照顾好宠物=赚得多」的底线。
    ///
    /// 早先加过「单次领取上限」，实测它会盖住达成率，
    /// 导致任何正常状态下收益都一样。这个测试就是防它回归。
    func testStateActuallyAffectsEarnings() {
        let rule = OfflineCareReward()
        let good = rule.evaluate(ctx(offlineHours: 6, satiety: 0.9, mood: 0.9))?.coins ?? 0
        let bad = rule.evaluate(ctx(offlineHours: 6, satiety: 0.2, mood: 0.2))?.coins ?? 0
        XCTAssertGreaterThan(good, bad, "状态好应该赚得更多")
        XCTAssertGreaterThan(Double(good) / Double(max(bad, 1)), 2.0,
                             "状态差距应带来至少 2 倍收益差")
    }

    // MARK: - 上线奖励

    func testCheckInRequiresInterval() {
        let rule = CheckInReward()
        XCTAssertNil(rule.evaluate(ctx(offlineHours: 1)), "间隔不足 5h 不发")
        XCTAssertNil(rule.evaluate(ctx(offlineHours: 4.9)))
        XCTAssertEqual(rule.evaluate(ctx(offlineHours: 5))?.coins, 10)
        XCTAssertEqual(rule.evaluate(ctx(offlineHours: 100))?.coins, 10, "只发一份，不累积")
    }

    /// 上线奖励与成就不占额度 —— 否则「领了成就反而少赚」
    func testOnlyOfflineCareCountsTowardCap() {
        XCTAssertTrue(OfflineCareReward().countsTowardDailyCap)
        XCTAssertFalse(CheckInReward().countsTowardDailyCap)
        XCTAssertFalse(AchievementRule.all[0].countsTowardDailyCap)
    }

    // MARK: - 看家收益

    func testTooShortOfflineNoReward() {
        XCTAssertNil(OfflineCareReward().evaluate(realCtx(offlineHours: 0.2)),
                     "不足半小时不结算，避免频繁开关刷零碎收益")
    }

    func testNoRewardWhenCapExhausted() {
        let rule = OfflineCareReward()
        var c = realCtx(offlineHours: 8)
        c = RewardContext(pet: c.pet, wallet: c.wallet, now: c.now,
                          offlineHours: c.offlineHours,
                          avgSatiety: c.avgSatiety, avgMood: c.avgMood,
                          remainingCap: 0)
        XCTAssertNil(rule.evaluate(c), "额度用完不再发")
    }

    func testRewardClampedByRemainingCap() {
        let rule = OfflineCareReward()
        var c = realCtx(offlineHours: 8)
        c = RewardContext(pet: c.pet, wallet: c.wallet, now: c.now,
                          offlineHours: c.offlineHours,
                          avgSatiety: c.avgSatiety, avgMood: c.avgMood,
                          remainingCap: 7)
        XCTAssertEqual(rule.evaluate(c)?.coins, 7, "不能超过剩余额度")
    }

    /// 小鱼干 buff 抬高达成率
    func testBoostRaisesRate() {
        let rule = OfflineCareReward()
        var boosted = PetWallet()
        boosted.boostUntil = Date().addingTimeInterval(3600)
        let plain = rule.evaluate(realCtx(offlineHours: 6))?.coins ?? 0
        let withBoost = rule.evaluate(realCtx(offlineHours: 6, wallet: boosted))?.coins ?? 0
        XCTAssertGreaterThan(withBoost, plain, "buff 生效期内收益更高")
    }

    // MARK: - 钱包每日额度

    func testCapResetsNextDay() {
        var w = PetWallet()
        let day1 = Date()
        w.recordEarning(200, petID: "primary", at: day1)
        XCTAssertEqual(w.todayEarned, 200)

        let day2 = day1.addingTimeInterval(26 * 3600)
        XCTAssertEqual(w.remainingCap(stage: .adult, petID: "primary", at: day2),
                       PetStage.adult.dailyCap, "跨日应重置为满额")
        w.recordEarning(50, petID: "primary", at: day2)
        XCTAssertEqual(w.todayEarned, 50, "跨日先归零再累加")
    }

    func testRemainingCapShrinksWithinDay() {
        var w = PetWallet()
        let now = Date()
        let cap = PetStage.adult.dailyCap
        w.recordEarning(60, petID: "primary", at: now)
        XCTAssertEqual(w.remainingCap(stage: .adult, petID: "primary", at: now), cap - 60)
    }

    /// **额度制最主要的刷币面**：反复开关 app 不能绕过每日上限。
    ///
    /// 这要求 todayEarned 真正落盘并参与下次结算的 remainingCap 计算。
    func testDailyCapCannotBeFarmedByRelaunching() {
        var wallet = PetWallet()
        let pet = PetState()
        let stage = pet.stage
        var now = Date()
        let rule = OfflineCareReward()

        // 一天内结算 20 次，每次都造 6 小时离线
        for _ in 0..<20 {
            let c = RewardContext(
                pet: pet, wallet: wallet, now: now, offlineHours: 6,
                avgSatiety: 0.8, avgMood: 0.8,
                remainingCap: wallet.remainingCap(stage: stage, petID: "primary", at: now))
            if let out = rule.evaluate(c) {
                wallet.recordEarning(out.coins, petID: "primary", at: now)
            }
            now = now.addingTimeInterval(60)   // 同一天内
        }

        XCTAssertLessThanOrEqual(wallet.todayEarned, stage.dailyCap,
                                 "一天赚到的不能超过额度上限")
    }

    // MARK: - 按量计价

    func testCostScalesWithActualRestore() {
        // 空腹吃普通粮：补 70% → 70/10 × 5 = 35
        XCTAssertEqual(FoodItem.kibble.cost(currentSatiety: 0), 35)
        // 已 80% 饱：只能补 20% → 20/10 × 5 = 10
        XCTAssertEqual(FoodItem.kibble.cost(currentSatiety: 0.8), 10)
        // 满饱：落到最低价，**不是 0**
        XCTAssertEqual(FoodItem.kibble.cost(currentSatiety: 1.0),
                       FoodItem.kibble.minPrice)
    }

    /// **满饱时不能免费** —— 否则可以零成本反复点喂食刷 foodCounts
    /// 和美食类成就。剩饭是唯一例外（防死锁的兜底）。
    func testNothingIsFreeWhenFullExceptScraps() {
        for food in FoodItem.all where !food.isFree {
            XCTAssertGreaterThan(food.cost(currentSatiety: 1.0), 0,
                                 "\(food.id) 满饱时免费 —— 可以零成本刷成就")
        }
        XCTAssertEqual(FoodItem.scraps.cost(currentSatiety: 1.0), 0,
                       "剩饭必须永久免费")
    }

    /// **附加效果按固定价收费。**
    ///
    /// 曾经整个价格都按恢复量算，导致饱食 99% 时小鱼干只要 3 枚
    /// 却拿满额 buff（24h 达成率 ×1.6）—— 那就成了最优解，
    /// 「奢侈品」定位被破坏。
    func testExtraEffectsCostFixedPrice() {
        // 满饱时只剩附加效果的钱
        XCTAssertEqual(FoodItem.can.cost(currentSatiety: 1.0), 100)
        XCTAssertEqual(FoodItem.driedFish.cost(currentSatiety: 1.0), 200)

        // 有附加效果的食物，满饱价必须远高于普通粮
        XCTAssertGreaterThan(FoodItem.driedFish.cost(currentSatiety: 1.0),
                             FoodItem.kibble.cost(currentSatiety: 1.0) * 10,
                             "buff 不该白送")
    }

    func testScrapsAlwaysFree() {
        XCTAssertTrue(FoodItem.scraps.isFree)
        for s in [0.0, 0.5, 1.0] {
            XCTAssertEqual(FoodItem.scraps.cost(currentSatiety: s), 0)
        }
    }

    func testFullPricesMatchDocs() {
        XCTAssertEqual(FoodItem.kibble.fullPrice, 35)
        XCTAssertEqual(FoodItem.can.fullPrice, 150)
        XCTAssertEqual(FoodItem.driedFish.fullPrice, 250)
    }

    /// 半饱时吃好东西不再「浪费」—— **饱食部分**按实际恢复量走。
    ///
    /// 注意不是整个价格减半：附加效果是固定价，半饱时照收。
    /// 罐头空腹 150 = 饱食 50 + 心情 100；半饱 125 = 饱食 25 + 心情 100。
    func testSatietyPartScalesWithRestore() {
        let atEmpty = FoodItem.can.cost(currentSatiety: 0)
        let atHalf = FoodItem.can.cost(currentSatiety: 0.5)
        let fixed = FoodItem.can.extraPrice

        let satietyAtEmpty = atEmpty - fixed
        let satietyAtHalf = atHalf - fixed
        XCTAssertEqual(Double(satietyAtHalf), Double(satietyAtEmpty) * 0.5,
                       accuracy: 1.0, "饱食部分补一半只该花一半钱")
        XCTAssertEqual(atHalf, 125)
    }

    // MARK: - 平衡回归（对照 docs/04-balance.md）

    /// **设计目标**：从「放养」到「目标节奏」净结余严格递增。
    ///
    /// 这是 docs/00-overview.md 第五条约束「照顾好宠物=赚得多」的
    /// 可执行版本。额度制下导数不可能全区间为正（领满后再喂只增支出），
    /// 所以只断言到目标节奏（5 次/天）为止。
    func testCareIncentiveIncreasesUpToTarget() {
        let nets = [1, 2, 3, 4, 5].map { netDaily(feedsPerDay: $0) }
        for i in 0..<(nets.count - 1) {
            XCTAssertLessThan(nets[i], nets[i + 1],
                              "\(i + 1) 次/天的结余应低于 \(i + 2) 次/天")
        }
    }

    /// 超过目标节奏后不应暴跌 —— 不惩罚热情玩家
    func testOverFeedingDoesNotCollapseEarnings() {
        let peak = netDaily(feedsPerDay: 5)
        for n in [6, 8, 12] {
            let net = netDaily(feedsPerDay: n)
            XCTAssertGreaterThan(Double(net), Double(peak) * 0.9,
                                 "\(n) 次/天不应比峰值低 10% 以上")
        }
    }

    /// 放养（一天 1-2 次）会亏 —— 不管宠物就该亏
    func testNeglectLosesMoney() {
        XCTAssertLessThan(netDaily(feedsPerDay: 1), 0)
        XCTAssertLessThan(netDaily(feedsPerDay: 2), 0)
    }

    /// 目标节奏下攒一份小鱼干约 3-4 天
    func testSavingPaceForDriedFish() {
        let peak = netDaily(feedsPerDay: 5)
        XCTAssertGreaterThan(peak, 0)
        let days = Double(FoodItem.driedFish.fullPrice) / Double(peak)
        XCTAssertEqual(days, 3.3, accuracy: 1.0, "攒小鱼干应在 2.3~4.3 天")
    }

    /// 只喂食不陪玩会倒亏 —— 心情占达成率 60% 权重
    func testFeedOnlyWithoutPlayLosesMoney() {
        let net = netDaily(feedsPerDay: 5, moodOverride: 0.15)
        XCTAssertLessThan(net, 0, "不陪玩应入不敷出")
    }

    // MARK: - 辅助

    // 构造转发到 Fixture（见 Fixture.swift）—— RewardContext 有 7 个字段
    // 且按位置构造，加字段时只改 Fixture 一处

    private func ctx(offlineHours: Double,
                     satiety: Double = 0.5,
                     mood: Double = 0.5,
                     remainingCap: Int = 9999) -> RewardContext {
        Fixture.rewardContext(offlineHours: offlineHours,
                              satiety: satiety, mood: mood,
                              remainingCap: remainingCap)
    }

    /// 用真实衰减算出平均状态的上下文
    private func realCtx(offlineHours h: Double,
                         wallet: PetWallet = PetWallet(),
                         moodOverride: Double? = nil,
                         remainingCap: Int = 9999) -> RewardContext {
        Fixture.realRewardContext(offlineHours: h, wallet: wallet,
                                  moodOverride: moodOverride,
                                  remainingCap: remainingCap)
    }

    /// 模拟一整天：均匀分 n 段离线，算「看家收入 − 粮钱」。
    ///
    /// 注意收入要走 wallet 累加，否则每段都能拿满额度（那正是刷币漏洞）。
    private func netDaily(feedsPerDay n: Int, moodOverride: Double? = nil) -> Int {
        let pet = PetState()
        let stage = pet.stage
        let cycle = stage.hungerCycleHours
        let gap = 24.0 / Double(n)
        let rule = OfflineCareReward()

        var wallet = PetWallet()
        // 从当天 0 点起算，让 n 段离线全部落在同一日历日内。
        // 否则跨过午夜会重置额度，把「一天的收入」算高。
        var now = Calendar.current.startOfDay(for: Date())
        var income = 0
        var cost = 0

        for _ in 0..<n {
            let c = RewardContext(
                pet: pet, wallet: wallet, now: now, offlineHours: gap,
                avgSatiety: RewardEngine.averageLevel(offlineHours: gap,
                                                      cycleHours: cycle),
                avgMood: moodOverride ?? RewardEngine.averageLevel(
                    offlineHours: gap, cycleHours: 18),
                remainingCap: wallet.remainingCap(stage: stage, petID: "primary", at: now))
            if let out = rule.evaluate(c) {
                income += out.coins
                wallet.recordEarning(out.coins, petID: "primary", at: now)
            }
            // 喂食：饱食从「离线后的值」补回，逐餐单独取整
            let after = max(0, 1 - gap / cycle)
            cost += FoodItem.kibble.cost(currentSatiety: after)
            now = now.addingTimeInterval(gap * 3600)
        }
        return income - cost
    }
}

/// 成就的平衡性。
///
/// 守的是 docs/00-overview.md 第 5 条：**照顾好宠物 = 赚得多**。
/// 这条曾经被成就系统破坏 —— 时间型成就占全部金额的 61%，
/// 而 `streak_*` 只看「打开 app 的天数」，放养 30 天照样拿满。
final class AchievementBalanceTests: XCTestCase {

    /// **连续型成就必须看照顾质量，不能只看天数。**
    ///
    /// 这是那个失衡的根因：只要每天点开 app 就 +1。
    func testStreakAchievementsRequireGoodCare() {
        let rules = AchievementRule.all.filter { $0.id.hasPrefix("streak_") }
        XCTAssertFalse(rules.isEmpty)

        var neglected = Fixture.pet(satiety: 0.1, mood: 0.1, hygiene: 0.1)
        neglected.streakDays = 60          // 天天打开
        neglected.wellCaredDays = 0        // 但从没照顾好
        let wallet = PetWallet()

        for r in rules {
            XCTAssertFalse(r.condition(neglected, wallet),
                           "\(r.id) 在放养 60 天时仍能达成 —— 又变回只看天数了")
        }

        var cared = neglected
        cared.wellCaredDays = 60
        for r in rules {
            XCTAssertTrue(r.condition(cared, wallet),
                          "\(r.id) 照顾达标 60 天却拿不到")
        }
    }

    /// 时间型成就（纯时间流逝就能拿）占比不能过高。
    ///
    /// 阈值 25%：它们该是「陪伴的纪念」而非收入主力。
    /// 曾经是 61%，导致放养 30 天和认真养 13 天都能买第二只。
    func testTimeOnlyAchievementsAreMinorShareOfCoins() {
        let timeOnly = AchievementRule.all.filter {
            $0.id.hasPrefix("stage_") || $0.id == "age_100"
        }
        let total = AchievementRule.all.reduce(0) { $0 + $1.coins }
        let timeSum = timeOnly.reduce(0) { $0 + $1.coins }
        let share = Double(timeSum) / Double(total)

        XCTAssertLessThan(share, 0.25,
                          "纯时间型成就占了 \(Int(share * 100))% 的金币 —— 放养也能白拿")
    }

    /// 照料型（要真互动）应该是最大的一组
    func testCareIsTheBiggestGroup() {
        var byGroup: [AchievementRule.Group: Int] = [:]
        for r in AchievementRule.all {
            byGroup[r.group, default: 0] += r.coins
        }
        let care = byGroup[.care] ?? 0
        for (g, sum) in byGroup where g != .care {
            XCTAssertGreaterThan(care, sum,
                                 "照料型(\(care)) 不该少于 \(g)(\(sum))")
        }
    }

    /// 每条成就都要有名字和解锁条件说明
    func testEveryAchievementHasNameAndDescription() {
        for r in AchievementRule.all {
            XCTAssertNotEqual(L(r.nameKey), r.nameKey,
                              "\(r.id) 缺名字译文")
            XCTAssertNotEqual(L(r.descKey), r.descKey,
                              "\(r.id) 缺解锁条件说明（key: \(r.descKey)）")
            XCTAssertFalse(L(r.descKey).isEmpty)
        }
    }

    /// **名字不能重复。** 界面上两条同名成就分不清哪个是哪个。
    ///
    /// 抓到过一次：play_30 和 play_100 都叫「玩伴」。
    func testAchievementNamesAreUnique() {
        let names = AchievementRule.all.map { L($0.nameKey) }
        let dupes = names.filter { n in names.filter { $0 == n }.count > 1 }
        XCTAssertTrue(dupes.isEmpty, "重名成就：\(Set(dupes))")
    }

    /// id 不能重复 —— 重复会让 claimedRewards 判定串味
    func testAchievementIDsAreUnique() {
        let ids = AchievementRule.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count,
                       "有重复 id：\(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }

    /// **刚开局不该白拿任何成就。**
    ///
    /// 这条抓到过两个真 bug：
    /// 1. `all_high`（三维 ≥90%）—— 新宠物三维是满的，开局第一秒就达成
    /// 2. `rich_5000`（存款 5000）—— 启动资金正好 5000
    ///
    /// 两条都是「用初始值当成就条件」，白送 800 枚而玩家什么都没做。
    func testNoAchievementUnlocksAtOnboarding() {
        let fresh = PetState(breedID: "cat", colorIndex: 0, name: "新")
        let wallet = PetWallet()          // 含启动资金

        let unlocked = AchievementRule.all.filter { $0.condition(fresh, wallet) }
        XCTAssertTrue(unlocked.isEmpty,
                      "开局白送了这些成就：\(unlocked.map(\.id))")
    }

    /// 经济型用累计赚取而非余额 —— 用余额的话玩家不敢花钱
    func testEarningAchievementsUseTotalEarnedNotBalance() {
        var w = PetWallet()
        w.debugSetCoins(0)                 // 花光了
        w.earn(60000, reason: .offlineCare)
        w.spend(59000, reason: .breedPurchase)
        let pet = Fixture.pet()

        let earn = AchievementRule.all.filter { $0.id.hasPrefix("earn_") }
        XCTAssertFalse(earn.isEmpty)
        for r in earn {
            XCTAssertTrue(r.condition(pet, w),
                          "\(r.id) 因为余额被花掉就不算了 —— 该看 totalEarned")
        }
    }
}

/// 「照顾达标」的判定。
@MainActor
final class WellCaredDayTests: StoreTestCase {

    /// 状态好 → 记一天
    func testGoodCareCountsADay() {
        let s = makeStore()
        s.completeOnboarding(breedID: "cat", colorIndex: 0, name: "T")
        s.debugSetStats(satiety: 1, mood: 1, hygiene: 1)

        var p = s.pet
        p.lastWellCaredDay = nil
        p.wellCaredDays = 0
        s.debugSet(pet: p)

        s.markSeen()
        XCTAssertEqual(s.pet.wellCaredDays, 1)
    }

    /// 状态差 → 不记
    func testPoorCareDoesNotCount() {
        let s = makeStore()
        s.completeOnboarding(breedID: "cat", colorIndex: 0, name: "T")
        s.debugSetStats(satiety: 0.1, mood: 0.1, hygiene: 0.1)

        var p = s.pet
        p.lastWellCaredDay = nil
        p.wellCaredDays = 0
        s.debugSet(pet: p)

        s.markSeen()
        XCTAssertEqual(s.pet.wellCaredDays, 0, "放养不该算达标")
    }

    /// 同一天只记一次 —— 否则反复开关 app 能刷满
    func testSameDayCountsOnce() {
        let s = makeStore()
        s.completeOnboarding(breedID: "cat", colorIndex: 0, name: "T")
        s.debugSetStats(satiety: 1, mood: 1, hygiene: 1)

        var p = s.pet
        p.lastWellCaredDay = nil
        p.wellCaredDays = 0
        s.debugSet(pet: p)

        for _ in 0..<10 { s.markSeen() }
        XCTAssertEqual(s.pet.wellCaredDays, 1,
                       "同一天记了多次 —— 反复开关 app 就能刷满")
    }
}
