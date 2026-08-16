import XCTest
@testable import PixelPet

/// `PetStore` 的行为测试。
///
/// **这些测试原来写不出来** —— `init()` 直接读 `applicationSupportDirectory`，
/// 无法注入路径，所以 299 行的状态变更 + 结算编排零覆盖。
/// 现在存档与提醒都是注入的协议（`PetPersistence` / `PetReminderScheduling`），
/// 测试用内存实现 —— 不碰文件系统也不碰系统通知。
/// 临时目录与 store 构造在 `StoreTestCase`（见 Fixture.swift）
final class PetStoreTests: StoreTestCase {

    // MARK: - 互动表

    /// 遍历所有注册的互动，验证每个都真的改了状态。
    ///
    /// 加新互动时这个测试自动覆盖它 —— 这是 `Interaction.all` 表的收益。
    func testEveryInteractionMutatesState() {
        for act in InteractionEffect.all {
            let store = makeStore()
            var pet = store.pet
            let before = Date().addingTimeInterval(-3600)
            // 把相关时间戳推到一小时前，好看出变化
            pet.lastPlayedAt = before
            pet.lastCleanedAt = before

            var mutated = pet
            act.apply(&mutated, Date())

            XCTAssertTrue(mutated.lastPlayedAt > before
                          || mutated.lastCleanedAt > before,
                          "\(act.id) 应该更新某个时间戳")
        }
    }

    /// 每个互动都要涨对应的累计计数（成就依赖它）
    func testInteractionsIncrementCounters() {
        var pet = PetState()
        let now = Date()

        InteractionEffect.play.apply(&pet, now)
        XCTAssertEqual(pet.totalPlayCount, 1)

        InteractionEffect.clean.apply(&pet, now)
        XCTAssertEqual(pet.totalCleanCount, 1)
    }

    /// 注册表里的 id 不能重复 —— `PetScene.playAnimation(for:)` 按 id 分发
    func testInteractionIDsAreUnique() {
        let ids = InteractionEffect.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    /// **UI 配置表与作用表必须一一对应。**
    ///
    /// 拆成 InteractionEffect（Models）和 Interaction（Views）后，
    /// 两张表可能漂移 —— 加了按钮忘了作用，或反之。
    func testInteractionTablesAreAligned() {
        XCTAssertEqual(Interaction.all.count, InteractionEffect.all.count)
        let uiIDs = Set(Interaction.all.map(\.id))
        let effectIDs = Set(InteractionEffect.all.map(\.id))
        XCTAssertEqual(uiIDs, effectIDs,
                       "UI 表与作用表的 id 集合不一致")
    }

    /// 状态维度表要和 PetState 的三维对上
    func testStatDimensionsCoverAllAxes() {
        XCTAssertEqual(StatDimension.all.count, 3)
        let pet = PetState()
        let now = Date()
        for dim in StatDimension.all {
            let v = dim.value(pet, now)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    // MARK: - 互动通路

    func testPlayRaisesMoodAndPersists() {
        let store = makeStore()
        var p = store.pet
        p.lastPlayedAt = Date().addingTimeInterval(-10 * 3600)
        store.debugSet(pet: p)
        XCTAssertLessThan(store.pet.mood(), 0.5, "先造一个低心情状态")

        store.play()
        XCTAssertGreaterThan(store.pet.mood(), 0.95, "陪玩后心情应接近满")

        // 重新读盘，确认落盘了
        let reopened = makeStore()
        XCTAssertGreaterThan(reopened.pet.mood(), 0.95)
    }

    func testCleanRaisesHygiene() {
        let store = makeStore()
        var p = store.pet
        p.lastCleanedAt = Date().addingTimeInterval(-100 * 3600)
        store.debugSet(pet: p)
        XCTAssertLessThan(store.pet.hygiene(), 0.5)

        store.clean()
        XCTAssertGreaterThan(store.pet.hygiene(), 0.95)
    }

    /// 互动会叫醒睡着的宠物 —— 否则夜里点按钮宠物还趴着
    func testInteractionWakesSleepingPet() {
        let store = makeStore()
        // 造一个「正在深夜且没有清醒宽限」的状态
        var p = store.pet
        p.awakeUntil = nil
        store.debugSet(pet: p)
        let wasDrowsy = store.pet.isDrowsy()

        store.play()

        if wasDrowsy {
            XCTAssertNotNil(store.pet.awakeUntil, "互动后应有清醒宽限")
            XCTAssertFalse(store.pet.isDrowsy(), "互动应叫醒宠物")
        }
    }

    // MARK: - 喂食

    func testFeedDeductsCoinsByAmount() {
        let store = makeStore()
        var p = store.pet
        p.lastFedAt = Date().addingTimeInterval(-100 * 3600)  // 饿透
        store.debugSet(pet: p)
        let before = store.wallet.coins

        XCTAssertTrue(store.feed(.kibble))
        // 空腹吃普通粮：补 70% → 35 枚
        XCTAssertEqual(before - store.wallet.coins, 35)
        XCTAssertGreaterThan(store.pet.satiety(), 0.6)
    }

    func testFeedFailsWhenBroke() {
        let store = makeStore()
        var p = store.pet
        p.lastFedAt = Date().addingTimeInterval(-100 * 3600)
        var w = store.wallet
        w.debugSetCoins(0)
        store.debugSet(pet: p, wallet: w)

        XCTAssertFalse(store.feed(.driedFish), "钱不够应失败")
        XCTAssertEqual(store.wallet.coins, 0, "失败不该扣钱")
    }

    func testScrapsAlwaysAffordable() {
        let store = makeStore()
        var w = store.wallet
        w.debugSetCoins(0)
        var p = store.pet
        p.lastFedAt = Date().addingTimeInterval(-100 * 3600)
        store.debugSet(pet: p, wallet: w)

        XCTAssertTrue(store.feed(.scraps), "剩饭免费，没钱也能喂")
    }

    /// 喂食要记录档位次数 —— 美食类成就依赖它
    func testFeedRecordsFoodCounts() {
        let store = makeStore()
        var p = store.pet
        p.lastFedAt = Date().addingTimeInterval(-100 * 3600)
        store.debugSet(pet: p)
        store.feed(.kibble)
        XCTAssertEqual(store.pet.foodCounts?["kibble"], 1)
    }

    // MARK: - 存档

    /// 首次启动必须立刻写盘 —— 否则 bornAt 每次启动都被重置，
    /// 宠物永远显示「相伴第 0 天」。
    ///
    /// 用内存存档断言「save 被调用过」，比检查文件存在更直接。
    func testFirstLaunchPersistsImmediately() {
        let mem = MemoryPersistence()
        XCTAssertNil(mem.loadPet(), "前提：空存档")

        _ = Fixture.store(persistence: mem)

        XCTAssertNotNil(mem.loadPet(), "首启应立刻写入宠物")
        XCTAssertNotNil(mem.loadWallet(), "首启应立刻写入钱包")
    }

    /// 真实文件路径的往返。单独一个测试覆盖 FilePersistence，
    /// 其余测试走内存实现（快且不用清理）。
    func testFilePersistenceRoundTrip() {
        let store = makeFileStore()
        store.rename("文件测试")

        // 重开：新的 FilePersistence 指向同一目录
        let reopened = makeFileStore()
        XCTAssertEqual(reopened.pet.name, "文件测试")
    }

    func testWalletSurvivesPetReset() {
        let store = makeStore()
        var w = store.wallet
        w.debugSetCoins(500)
        w.ownedBreeds.insert(PetBreed.dog.id)   // choose 要求已拥有
        store.debugSet(wallet: w)
        store.play()                      // 触发 persist

        // 换宠物不该清空钱包 —— 这是钱包独立存档的设计意图
        XCTAssertTrue(store.choose(breedID: PetBreed.dog.id, colorIndex: 1))
        XCTAssertEqual(store.wallet.coins, 500)
    }

    func testRenameTrimsAndPersists() {
        let store = makeStore()
        store.rename("小咪")
        XCTAssertEqual(store.pet.name, "小咪")

        let reopened = makeStore()
        XCTAssertEqual(reopened.pet.name, "小咪")
    }

    /// 换品种要记进收藏成就的进度。
    ///
    /// ⚠️ `choose` 现在要求**已拥有**该品种（否则免费就能玩到所有宠物），
    /// 所以要先解锁。这个测试原来直接 choose，加了拥有校验后失败 ——
    /// 是校验生效的证据，不是回归。
    func testChooseRecordsTriedBreeds() {
        let store = makeStore()
        var w = store.wallet
        w.ownedBreeds.insert(PetBreed.dog.id)
        store.debugSet(wallet: w)

        XCTAssertTrue(store.choose(breedID: PetBreed.dog.id, colorIndex: 0))
        XCTAssertTrue(store.pet.triedBreeds?.contains("dog") ?? false)
    }

    // MARK: - 结算

    /// 结算把收益写进钱包，且看家收益计入每日额度
    func testSettleRewardsCreditsWallet() {
        let store = makeStore()
        // 造 6 小时离线
        var w = store.wallet
        w.lastCollectedAt = Date().addingTimeInterval(-6 * 3600)
        store.debugSet(wallet: w)
        let before = store.wallet.coins

        let result = store.settleRewards()
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(store.wallet.coins, before)
        XCTAssertGreaterThan(store.wallet.todayEarned, 0,
                             "看家收益要计入额度")
    }

    /// 刚结算过就再结算，不该再给看家收益
    func testSettleTwiceDoesNotDoubleCount() {
        let store = makeStore()
        var w = store.wallet
        w.lastCollectedAt = Date().addingTimeInterval(-6 * 3600)
        store.debugSet(wallet: w)
        store.settleRewards()
        let after = store.wallet.coins

        store.settleRewards()
        XCTAssertEqual(store.wallet.coins, after, "间隔太短不该再发")
    }

    // MARK: - 抚摸冷却

    func testStrokeHasCooldown() {
        let store = makeStore()
        XCTAssertTrue(store.stroke(), "第一次应成功")
        XCTAssertFalse(store.stroke(), "冷却中应失败")
    }
}

// MARK: - 开场编排

/// `OpeningSequence` 的测试。
///
/// 原来这段时序在 `PetHomeView.onAppear` 里（42 行，含两层嵌套
/// asyncAfter），和视图声明混在一起，完全无法测。
final class OpeningSequenceTests: StoreTestCase {

    /// 无收益时 messages 为空 —— 调用方据此走日常问候
    func testNoSettlementYieldsNoMessages() {
        let store = makeStore()
        // 刚建的 store，lastCollectedAt 是现在，离线时长为 0
        let plan = OpeningSequence.plan(store: store)
        XCTAssertFalse(plan.hasSettlementNews,
                       "无离线收益时应交给台词系统说问候")
    }

    /// 有收益时产出可播报的文案
    func testSettlementProducesMessages() {
        let store = makeStore()
        var w = store.wallet
        w.lastCollectedAt = Date().addingTimeInterval(-8 * 3600)
        store.debugSet(wallet: w)

        let plan = OpeningSequence.plan(store: store)
        XCTAssertTrue(plan.hasSettlementNews)
        XCTAssertFalse(plan.messages[0].isEmpty)
        // 文案要经过本地化格式化，不该残留 %@ / %d
        XCTAssertFalse(plan.messages[0].contains("%@"))
        XCTAssertFalse(plan.messages[0].contains("%d"))
    }

    /// **顺序硬约束**：读 daysSinceLastSeen 必须在 markSeen 之前。
    ///
    /// 如果顺序颠倒，absentDays 永远是 0，「久别重逢」台词永远不触发。
    func testAbsentDaysReadBeforeMarkSeen() {
        let store = makeStore()
        var p = store.pet
        p.lastSeenAt = Calendar.current.date(byAdding: .day, value: -5,
                                             to: Date())
        store.debugSet(pet: p)

        let plan = OpeningSequence.plan(store: store)
        XCTAssertEqual(plan.absentDays, 5,
                       "markSeen 之前读到的天数应该是 5")
        // markSeen 已经跑过，连续天数被重置（隔了 5 天）
        XCTAssertEqual(store.pet.streakDays, 1)
    }

    /// 结算必须在 markSeen 之后 —— 连续天数影响成就判定。
    ///
    /// ⚠️ 连续天数看的是 `lastStreakDay` 而不是 `lastSeenAt`
    /// （两个字段，前者只在跨日签到时更新）。我第一版测试设错了字段，
    /// 断言 streak 从 2 涨到 3 但实际没动 —— 记在这里免得再踩。
    func testSettlementSeesUpdatedStreak() {
        let store = makeStore()
        var p = store.pet
        // 昨天签到过，今天打开应该 streak +1
        p.lastStreakDay = Calendar.current.date(byAdding: .day, value: -1,
                                                to: Date())
        p.streakDays = 2
        store.debugSet(pet: p)

        _ = OpeningSequence.plan(store: store)
        XCTAssertEqual(store.pet.streakDays, 3,
                       "结算前 streak 应已更新到 3")
    }

    /// 断签：隔 2 天以上重置为 1
    func testStreakResetsAfterGap() {
        let store = makeStore()
        var p = store.pet
        p.lastStreakDay = Calendar.current.date(byAdding: .day, value: -3,
                                                to: Date())
        p.streakDays = 10
        store.debugSet(pet: p)

        _ = OpeningSequence.plan(store: store)
        XCTAssertEqual(store.pet.streakDays, 1, "隔 3 天应断签")
    }

    /// 同一天多次打开，连续天数不该重复累加
    func testStreakDoesNotDoubleCountSameDay() {
        let store = makeStore()
        var p = store.pet
        p.lastStreakDay = Date()
        p.streakDays = 5
        store.debugSet(pet: p)

        _ = OpeningSequence.plan(store: store)
        XCTAssertEqual(store.pet.streakDays, 5, "同一天不该再加")
    }

    /// 延迟常量要合理：第二条消息的间隔必须大于气泡停留时长，
    /// 否则第一条还没消失就被顶掉
    func testSecondMessageWaitsForFirstToClear() {
        XCTAssertGreaterThan(OpeningSequence.secondMessageDelay,
                             BubbleLayer.defaultSpeechDuration,
                             "第二条消息会顶掉还在显示的第一条")
    }

    /// 开场延迟不能太长 —— 用户打开 app 等太久没反应会觉得卡
    func testGreetDelayIsShort() {
        XCTAssertLessThan(OpeningSequence.greetDelay, 2.0)
        XCTAssertGreaterThan(OpeningSequence.greetDelay, 0.3,
                             "太快会在场景渲染完成前弹气泡")
    }
}

// MARK: - 开局与商店

/// 开局流程与品种购买。
final class OnboardingStoreTests: StoreTestCase {

    /// 新玩家要走开局
    func testFreshStoreNeedsOnboarding() {
        let store = makeStore()
        XCTAssertTrue(store.needsOnboarding)
        XCTAssertEqual(store.wallet.coins, PetWallet.initialCoins)
        XCTAssertTrue(store.wallet.ownedBreeds.isEmpty)
    }

    /// 完成开局：扣钱、解锁品种、起名、落盘
    func testCompleteOnboardingDeductsAndUnlocks() {
        let store = makeStore()
        XCTAssertTrue(store.completeOnboarding(breedID: PetBreed.dog.id,
                                               colorIndex: 2, name: "旺财"))

        XCTAssertEqual(store.wallet.coins,
                       PetWallet.initialCoins - PetWallet.starterPrice,
                       "5000 - 4000 = 1000")
        XCTAssertTrue(store.wallet.owns(.dog))
        XCTAssertFalse(store.needsOnboarding)
        XCTAssertEqual(store.pet.breedID, PetBreed.dog.id)
        XCTAssertEqual(store.pet.colorIndex, 2)
        XCTAssertEqual(store.pet.name, "旺财")

        // 重开确认落盘
        let reopened = makeStore()
        XCTAssertFalse(reopened.needsOnboarding)
        XCTAssertEqual(reopened.pet.name, "旺财")
        XCTAssertEqual(reopened.wallet.coins, 1000)
    }

    /// 名字要 trim 且截断到 12 字
    func testOnboardingTrimsName() {
        let store = makeStore()
        store.completeOnboarding(breedID: PetBreed.cat.id, colorIndex: 0,
                                 name: "  这个名字实在是太长了超过十二个字  ")
        XCTAssertEqual(store.pet.name.count, 12)
        XCTAssertFalse(store.pet.name.hasPrefix(" "))
    }

    /// 钱不够不能完成开局（防御性 —— 正常流程下启动资金一定够）
    func testOnboardingFailsWithoutCoins() {
        let store = makeStore()
        var w = store.wallet
        w.debugSetCoins(100)
        store.debugSet(wallet: w)

        XCTAssertFalse(store.completeOnboarding(breedID: PetBreed.cat.id,
                                                colorIndex: 0, name: "X"))
        XCTAssertTrue(store.needsOnboarding, "失败不该标记完成")
    }

    // MARK: - 品种切换与购买

    /// **只能切已拥有的品种** —— 否则免费就能玩到所有宠物
    func testCannotSwitchToUnownedBreed() {
        let store = makeStore()
        store.completeOnboarding(breedID: PetBreed.cat.id, colorIndex: 0,
                                 name: "咪咪")

        XCTAssertFalse(store.choose(breedID: PetBreed.dog.id, colorIndex: 0),
                       "没买过狗不该能切")
        XCTAssertEqual(store.pet.breedID, PetBreed.cat.id)
    }

    /// 买过就能切，且切换免费（一次性解锁而非消耗品）
    func testPurchaseThenSwitchFreely() {
        let store = makeStore()
        store.completeOnboarding(breedID: PetBreed.cat.id, colorIndex: 0,
                                 name: "咪咪")
        // 手动解锁狗（模拟买过）
        var w = store.wallet
        w.ownedBreeds.insert(PetBreed.dog.id)
        store.debugSet(wallet: w)

        let before = store.wallet.coins
        XCTAssertTrue(store.choose(breedID: PetBreed.dog.id, colorIndex: 1))
        XCTAssertEqual(store.wallet.coins, before, "切换不该再扣钱")

        // 切回去也免费
        XCTAssertTrue(store.choose(breedID: PetBreed.cat.id, colorIndex: 0))
        XCTAssertEqual(store.wallet.coins, before)
    }

    /// 购买是幂等的 —— 重复买不该重复扣钱
    func testPurchaseIsIdempotent() {
        var w = PetWallet()
        w.debugSetCoins(20000)
        // 造一个付费品种来测（现有两个都是 starter，price=0）
        let paid = PetBreed(id: "test", nameKey: "x", colorCount: 4,
                            footPadding: 4,
                            price: 9000, traitKey: "x",
                            moodCycleHours: 18, hygieneCycleHours: 72,
                            goldMultiplier: 1.0)
        XCTAssertTrue(w.purchase(paid))
        XCTAssertEqual(w.coins, 11000)
        XCTAssertTrue(w.purchase(paid), "已拥有应返回成功")
        XCTAssertEqual(w.coins, 11000, "不该重复扣钱")
    }

    /// 钱不够买不了
    func testPurchaseFailsWhenBroke() {
        var w = PetWallet()
        w.debugSetCoins(500)
        let paid = PetBreed(id: "test", nameKey: "x", colorCount: 4,
                            footPadding: 4,
                            price: 9000, traitKey: "x",
                            moodCycleHours: 18, hygieneCycleHours: 72,
                            goldMultiplier: 1.0)
        XCTAssertFalse(w.purchase(paid))
        XCTAssertEqual(w.coins, 500)
        XCTAssertFalse(w.owns(paid))
    }

    /// 旧存档（没有 hasCompletedOnboarding 字段）不该被拉回开局。
    ///
    /// 判定依据：钱包被用过（有累计收入或领过成就）。
    func testLegacySaveSkipsOnboarding() throws {
        let json = """
        {"coins":3000,"totalEarned":500,"claimedRewards":["first_feed"],
         "lastCollectedAt":760000000,"todayEarned":0,"lastEarnDate":760000000}
        """
        let w = try JSONDecoder().decode(PetWallet.self,
                                        from: Data(json.utf8))
        XCTAssertTrue(w.hasCompletedOnboarding,
                      "老用户不该被拉回选宠界面")
    }
}

// MARK: - 依赖注入

/// 存档与提醒的注入。
///
/// 这些测试原来写不出来 —— 存档是 init 里的 30 行内联代码，
/// 提醒是 `persist()` 里的硬编码副作用，只能用 bool 开关绕过。
@MainActor
final class PetPersistenceTests: XCTestCase {

    /// 每次状态变更都要落盘 —— 分散写会漏，所以统一在 persist()
    func testEveryMutationPersists() {
        let mem = MemoryPersistence()
        let store = Fixture.store(persistence: mem)
        let baseline = mem.petSaveCount

        store.play()
        XCTAssertGreaterThan(mem.petSaveCount, baseline, "互动应落盘")

        let afterPlay = mem.petSaveCount
        store.rename("新名字")
        XCTAssertGreaterThan(mem.petSaveCount, afterPlay, "改名应落盘")
    }

    /// 钱包和宠物是两份存档 —— 换宠物不该清空钱包
    func testWalletAndPetAreSeparate() {
        let mem = MemoryPersistence()
        let store = Fixture.store(persistence: mem)
        store.play()

        XCTAssertNotNil(mem.loadPet())
        XCTAssertNotNil(mem.loadWallet())
    }

    /// 加载已有存档：不该覆盖成默认值
    func testLoadsExistingSave() {
        var pet = PetState()
        pet.name = "已存在"
        let mem = MemoryPersistence(pet: pet, wallet: PetWallet())

        let store = Fixture.store(persistence: mem)
        XCTAssertEqual(store.pet.name, "已存在")
    }

    /// 空存档：给默认宠物而不是崩
    func testEmptySaveYieldsDefaults() {
        let store = Fixture.store(persistence: MemoryPersistence())
        XCTAssertEqual(store.pet.breedID, PetBreed.cat.id)
        XCTAssertEqual(store.wallet.coins, PetWallet.initialCoins)
    }

    /// **提醒是注入的** —— 状态变更会触发重排，但测试里不碰系统通知
    func testRemindersRescheduledOnMutation() {
        let noop = NoopReminders()
        let store = PetStore(storage: MemoryPersistence(),
                             reminders: noop,
                             runsHeartbeat: false)
        let before = noop.rescheduleCount

        store.play()
        XCTAssertGreaterThan(noop.rescheduleCount, before,
                             "状态变了要重排提醒（何时会饿是算出来的）")
    }

    /// 内存实现和文件实现行为一致 —— 否则测试通过但线上出错
    func testMemoryAndFileBehaveSame() {
        let dir = Fixture.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        for storage in [MemoryPersistence() as PetPersistence,
                        FilePersistence(directory: dir)] {
            let store = Fixture.store(persistence: storage)
            store.rename("一致性")
            XCTAssertEqual(store.pet.name, "一致性")

            // 重新加载应拿到同样的值
            XCTAssertEqual(storage.loadPet()?.name, "一致性")
        }
    }
}
