import XCTest
@testable import PixelPet

/// `PetStore` 的行为测试。
///
/// **这些测试原来写不出来** —— `init()` 直接读 `applicationSupportDirectory`，
/// 无法注入路径，所以 299 行的状态变更 + 结算编排零覆盖。
/// 现在 init 接受 `directory:`，测试用临时目录独立跑。
@MainActor
final class PetStoreTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// 关掉通知与心跳 —— 前者有系统副作用，后者会让测试留下定时器
    private func makeStore() -> PetStore {
        PetStore(directory: dir,
                 schedulesNotifications: false,
                 runsHeartbeat: false)
    }

    // MARK: - 互动表

    /// 遍历所有注册的互动，验证每个都真的改了状态。
    ///
    /// 加新互动时这个测试自动覆盖它 —— 这是 `Interaction.all` 表的收益。
    func testEveryInteractionMutatesState() {
        for act in Interaction.all {
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

        Interaction.play.apply(&pet, now)
        XCTAssertEqual(pet.totalPlayCount, 1)

        Interaction.clean.apply(&pet, now)
        XCTAssertEqual(pet.totalCleanCount, 1)
    }

    /// 注册表里的 id 不能重复 —— `PetScene.playAnimation(for:)` 按 id 分发
    func testInteractionIDsAreUnique() {
        let ids = Interaction.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
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
        w.coins = 0
        store.debugSet(pet: p, wallet: w)

        XCTAssertFalse(store.feed(.driedFish), "钱不够应失败")
        XCTAssertEqual(store.wallet.coins, 0, "失败不该扣钱")
    }

    func testScrapsAlwaysAffordable() {
        let store = makeStore()
        var w = store.wallet
        w.coins = 0
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

    func testFirstLaunchPersistsImmediately() {
        _ = makeStore()
        let petFile = dir.appendingPathComponent("pet.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: petFile.path),
                      "首次启动必须立刻写盘，否则 bornAt 每次都重置")
    }

    func testWalletSurvivesPetReset() {
        let store = makeStore()
        var w = store.wallet
        w.coins = 500
        store.debugSet(wallet: w)
        store.play()                      // 触发 persist

        // 换宠物不该清空钱包 —— 这是钱包独立存档的设计意图
        store.choose(breedID: PetBreed.dog.id, colorIndex: 1)
        XCTAssertEqual(store.wallet.coins, 500)
    }

    func testRenameTrimsAndPersists() {
        let store = makeStore()
        store.rename("小咪")
        XCTAssertEqual(store.pet.name, "小咪")

        let reopened = makeStore()
        XCTAssertEqual(reopened.pet.name, "小咪")
    }

    /// 换品种要记进收藏成就的进度
    func testChooseRecordsTriedBreeds() {
        let store = makeStore()
        store.choose(breedID: PetBreed.dog.id, colorIndex: 0)
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
