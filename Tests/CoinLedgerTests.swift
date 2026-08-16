import XCTest
@testable import PixelPet

/// 金币账本的不变量。
///
/// 这一组测试守的是「经济系统的账目永远平」——
/// 之前支出是三处裸写 `coins -=`，没有任何东西能发现写错。
final class CoinLedgerTests: XCTestCase {

    // MARK: - 账目恒等式

    func testBalanceStartsAtInitialGrant() {
        let l = CoinLedger(initial: 5000)
        XCTAssertEqual(l.balance, 5000)
        XCTAssertEqual(l.totalIn, 5000)
        XCTAssertEqual(l.totalOut, 0)
        XCTAssertTrue(l.isBalanced)
    }

    /// **核心不变量：收入 − 支出 == 余额。**
    ///
    /// 随机走一串收支，每步都验。任何绕过 `apply` 的写法都会让它失败。
    func testLedgerStaysBalancedThroughManyOperations() {
        var l = CoinLedger(initial: 1000)
        var rng = SystemRandomNumberGenerator()
        let reasons = CoinReason.allCases

        for _ in 0..<500 {
            let r = reasons.randomElement(using: &rng)!
            let amount = Int.random(in: 1...300, using: &rng)
            l.apply(amount, reason: r)
            XCTAssertTrue(l.isBalanced,
                          "\(r) \(amount) 之后账目不平：\(l.totalIn) - \(l.totalOut) != \(l.balance)")
            XCTAssertGreaterThanOrEqual(l.balance, 0, "余额不该为负")
        }
    }

    func testSpendFailsWhenInsufficientAndChangesNothing() {
        var l = CoinLedger(initial: 100)
        let before = l
        XCTAssertFalse(l.apply(101, reason: .food))
        XCTAssertEqual(l, before, "失败的支出不该留下任何痕迹")
    }

    /// 金额一律传正数，方向由 reason 决定 —— 传 0 或负数直接拒绝。
    ///
    /// 这样 `spend(-100)` 那种把符号搞反、结果变成加钱的 bug
    /// 在类型/契约层面就不存在。
    func testRejectsNonPositiveAmounts() {
        var l = CoinLedger(initial: 100)
        XCTAssertFalse(l.apply(0, reason: .food))
        XCTAssertFalse(l.apply(-50, reason: .food))
        XCTAssertFalse(l.apply(-50, reason: .achievement))
        XCTAssertEqual(l.balance, 100)
    }

    // MARK: - 原因分类

    /// 每个 reason 都必须在 isIncome 里有明确归属。
    /// 加新 case 忘了分类的话，这里会因为 allCases 覆盖不全而暴露。
    func testEveryReasonIsClassified() {
        let income = CoinReason.allCases.filter(\.isIncome)
        let spend = CoinReason.allCases.filter { !$0.isIncome }
        XCTAssertEqual(income.count + spend.count, CoinReason.allCases.count)
        XCTAssertFalse(income.isEmpty)
        XCTAssertFalse(spend.isEmpty)
    }

    /// **只有看家收益占每日额度。**
    ///
    /// 上线奖励和成就刻意不占 —— 否则领了成就当天反而少赚，
    /// 见 docs/04-balance.md。
    func testOnlyOfflineCareCountsTowardCap() {
        for r in CoinReason.allCases {
            XCTAssertEqual(r.countsTowardDailyCap, r == .offlineCare,
                           "\(r) 的额度归属不对")
        }
    }

    /// 支出不该占额度 —— 额度是收入侧的概念
    func testNoSpendReasonCountsTowardCap() {
        for r in CoinReason.allCases where !r.isIncome {
            XCTAssertFalse(r.countsTowardDailyCap)
        }
    }

    // MARK: - 流水

    func testRecordsTraceWithReasonAndBalance() {
        var l = CoinLedger(initial: 1000)
        l.apply(35, reason: .food, note: "kibble")
        l.apply(10, reason: .loginBonus)

        XCTAssertEqual(l.recent.count, 3)   // 含 initialGrant
        let food = l.recent[1]
        XCTAssertEqual(food.reason, .food)
        XCTAssertEqual(food.amount, 35)
        XCTAssertEqual(food.balance, 965, "流水要记变动后的余额，方便对账")
        XCTAssertEqual(food.note, "kibble")
        XCTAssertEqual(food.signed, -35, "支出的 signed 应为负")

        XCTAssertEqual(l.recent[2].signed, 10)
    }

    /// 流水只留尾部 —— 否则存档无限增长
    func testHistoryIsCapped() {
        var l = CoinLedger(initial: 100_000)
        for _ in 0..<(CoinLedger.historyLimit * 3) {
            l.apply(1, reason: .food)
        }
        XCTAssertEqual(l.recent.count, CoinLedger.historyLimit)
        XCTAssertTrue(l.isBalanced, "裁剪流水不该影响账目")
        // 留下的必须是最近的
        XCTAssertEqual(l.recent.last?.balance, l.balance)
    }

    // MARK: - 分项汇总（收支明细页的数据源）

    /// **终身累计不能用 `recent` 求和** —— 它只留最近 40 笔。
    ///
    /// 这是给收支明细页加数据时踩到的坑：原来 `total(for:)` 扫 `recent`，
    /// 玩久了明细页会显示错数（少算被裁掉的那些）。
    func testTotalsAreLifetimeNotJustRecent() {
        var l = CoinLedger(initial: 100_000)
        let n = CoinLedger.historyLimit * 2
        for _ in 0..<n { l.apply(3, reason: .food) }

        XCTAssertEqual(l.total(for: .food), 3 * n,
                       "终身累计要算全部，不只是流水里剩下的")
        XCTAssertEqual(l.recent.count, CoinLedger.historyLimit)
        XCTAssertEqual(l.totalOut, 3 * n)
    }

    func testBreakdownSplitsIncomeAndSpendSortedDescending() {
        var l = CoinLedger(initial: 5000)
        l.apply(300, reason: .achievement)
        l.apply(99, reason: .offlineCare)
        l.apply(4000, reason: .starterPet)
        l.apply(35, reason: .food)

        let inc = l.incomeBreakdown
        XCTAssertEqual(inc.map(\.reason), [.initialGrant, .achievement, .offlineCare],
                       "收入项按金额降序")
        XCTAssertTrue(inc.allSatisfy { $0.reason.isIncome })

        let out = l.spendBreakdown
        XCTAssertEqual(out.map(\.reason), [.starterPet, .food])
        XCTAssertTrue(out.allSatisfy { !$0.reason.isIncome })

        // 分项之和要等于总额，否则明细页和余额对不上
        XCTAssertEqual(inc.reduce(0) { $0 + $1.amount }, l.totalIn)
        XCTAssertEqual(out.reduce(0) { $0 + $1.amount }, l.totalOut)
    }

    /// 没发生过的原因不该出现在明细里（不然一堆 0 占版面）
    func testBreakdownSkipsZeroReasons() {
        var l = CoinLedger(initial: 100)
        l.apply(10, reason: .food)
        XCTAssertEqual(l.spendBreakdown.count, 1)
        XCTAssertFalse(l.incomeBreakdown.contains { $0.reason == .achievement })
    }

    /// 每个 reason 都要有本地化 key
    func testEveryReasonHasLabelKey() {
        for r in CoinReason.allCases {
            XCTAssertEqual(r.labelKey, "coin.reason.\(r.rawValue)")
            XCTAssertFalse(L(r.labelKey).isEmpty)
            XCTAssertNotEqual(L(r.labelKey), r.labelKey,
                              "\(r) 缺本地化 —— 界面上会显示 key 本身")
        }
    }

    // MARK: - 存档

    func testRoundTripsThroughJSON() throws {
        var l = CoinLedger(initial: 5000)
        l.apply(4000, reason: .starterPet, note: "dog")
        l.apply(99, reason: .offlineCare)

        let data = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(CoinLedger.self, from: data)
        XCTAssertEqual(back, l)
        XCTAssertTrue(back.isBalanced)
    }

    /// 旧存档只有裸 `coins`，没有 ledger。
    /// **余额必须一分不差** —— 不能让人升级后凭空少钱。
    func testLegacyWalletMigratesBalanceExactly() throws {
        let legacy = """
        {"coins": 10098, "lastCollectedAt": 800000000,
         "totalEarned": 899, "todayEarned": 99, "lastEarnDate": 800000000,
         "claimedRewards": ["first_feed"], "ownedBreeds": ["dog"],
         "hasCompletedOnboarding": true}
        """.data(using: .utf8)!

        let w = try JSONDecoder().decode(PetWallet.self, from: legacy)
        XCTAssertEqual(w.coins, 10098, "迁移不能改变余额")
        XCTAssertTrue(w.ledger.isBalanced)
        XCTAssertEqual(w.totalEarned, 899, "totalEarned 是成就依据，要保留")
    }
}

/// 经过 `PetStore` 的端到端账目检查。
///
/// `CoinLedgerTests` 验的是账本自身；这里验**真实玩法路径**
/// 有没有绕过账本 —— 那才是之前 bug 的所在。
@MainActor
final class LedgerIntegrationTests: StoreTestCase {

    func testFeedingGoesThroughLedger() {
        let s = makeStore()
        let before = s.wallet.coins
        XCTAssertTrue(s.feed(.kibble))

        XCTAssertLessThan(s.wallet.coins, before, "喂食要扣钱")
        XCTAssertTrue(s.wallet.ledger.isBalanced)
        XCTAssertEqual(s.wallet.ledger.recent.last?.reason, .food,
                       "喂食必须留下 .food 流水 —— 之前是裸写 coins -= 不记账")
        XCTAssertEqual(s.wallet.ledger.recent.last?.note, "kibble")
    }

    func testFreeFoodLeavesNoTrace() {
        let s = makeStore()
        let n = s.wallet.ledger.recent.count
        XCTAssertTrue(s.feed(.scraps))
        XCTAssertEqual(s.wallet.ledger.recent.count, n, "0 价不该产生流水")
        XCTAssertTrue(s.wallet.ledger.isBalanced)
    }

    func testOnboardingPurchaseGoesThroughLedger() {
        let s = makeStore()
        XCTAssertTrue(s.completeOnboarding(breedID: "dog", colorIndex: 0, name: "阿黄"))

        XCTAssertEqual(s.wallet.coins,
                       PetWallet.initialCoins - PetWallet.starterPrice)
        XCTAssertTrue(s.wallet.ledger.isBalanced)
        XCTAssertTrue(s.wallet.ledger.recent.contains { $0.reason == .starterPet })
    }

    /// 结算后账目仍要平，且**签到与成就在账本里可区分**。
    ///
    /// 之前两者被合并成一次 `recordBonus`，事后分不出那笔钱的来源。
    func testSettlementRecordsEachPayoutSeparately() {
        let s = makeStore()
        var w = s.wallet
        w.debugSetCoins(1000)
        w.lastCollectedAt = Date().addingTimeInterval(-6 * 3600)
        s.debugSet(pet: Fixture.pet(satiety: 0.5, mood: 0.6), wallet: w)

        guard let r = s.settleRewards() else { return XCTFail("该有收益") }

        XCTAssertTrue(s.wallet.ledger.isBalanced)
        XCTAssertEqual(r.payouts.reduce(0) { $0 + $1.coins }, r.totalCoins,
                       "分项之和要等于总额")

        let capped = r.payouts.filter { $0.reason.countsTowardDailyCap }
        XCTAssertEqual(capped.reduce(0) { $0 + $1.coins }, r.cappedCoins)
    }

    /// 走一串完整玩法，账目全程平
    func testFullPlaythroughStaysBalanced() {
        let s = makeStore()
        s.completeOnboarding(breedID: "cat", colorIndex: 0, name: "咪咪")
        XCTAssertTrue(s.wallet.ledger.isBalanced)

        for _ in 0..<10 {
            s.feed(.kibble)
            s.play()
            s.clean()
            XCTAssertTrue(s.wallet.ledger.isBalanced)
        }

        var rich = s.wallet
        rich.debugSetCoins(20000)
        s.debugSet(wallet: rich)
        XCTAssertTrue(s.wallet.ledger.isBalanced, "调试发钱也要保持账目平")

        // 品种解锁。注意目前两个品种都是免费 starter（price == 0），
        // 0 价不产生流水 —— 所以这里只断言「账目仍平 + 确实解锁了」。
        // 等有付费品种时，`.breedPurchase` 流水由
        // `testPaidBreedRecordsPurchase` 覆盖。
        var buyer = s.wallet
        let dog = PetBreed.byID("dog")
        XCTAssertTrue(buyer.purchase(dog))
        s.debugSet(wallet: buyer)
        XCTAssertTrue(s.wallet.ledger.isBalanced)
        XCTAssertTrue(s.wallet.owns(dog))
    }

    /// 付费品种要留下 `.breedPurchase` 流水。
    ///
    /// 现在两个品种都免费，所以这里造一个带价格的品种来验计价路径 ——
    /// 否则等真加付费品种时才发现没记账就晚了。
    func testPaidBreedRecordsPurchase() {
        var w = PetWallet()
        w.debugSetCoins(12000)
        let paid = PetBreed(id: "test_paid", nameKey: "breed.cat",
                            layout: .lpc(footPadding: 5),
                            price: 10000, traitKey: "trait.balanced",
                            moodCycleHours: 18, hygieneCycleHours: 72,
                            goldMultiplier: 1.0)

        XCTAssertTrue(w.purchase(paid))
        XCTAssertEqual(w.coins, 2000)
        XCTAssertTrue(w.ledger.isBalanced)
        let last = w.ledger.recent.last
        XCTAssertEqual(last?.reason, .breedPurchase)
        XCTAssertEqual(last?.amount, 10000)
        XCTAssertEqual(last?.note, "test_paid")

        // 买不起就该失败且不留痕
        var poor = PetWallet()
        poor.debugSetCoins(500)
        let before = poor.ledger
        XCTAssertFalse(poor.purchase(paid))
        XCTAssertEqual(poor.ledger, before, "失败的购买不该动账本")
        XCTAssertFalse(poor.owns(paid))
    }

    /// 存档往返后账目仍平（流水也要跟着落盘）
    func testLedgerSurvivesPersistence() {
        let s = makeStore()
        s.feed(.kibble)
        let coins = s.wallet.coins
        let traceCount = s.wallet.ledger.recent.count

        let reloaded = makeStore()   // 同一个 MemoryPersistence
        XCTAssertEqual(reloaded.wallet.coins, coins)
        XCTAssertEqual(reloaded.wallet.ledger.recent.count, traceCount,
                       "流水要落盘，否则重启后无法追溯")
        XCTAssertTrue(reloaded.wallet.ledger.isBalanced)
    }
}
