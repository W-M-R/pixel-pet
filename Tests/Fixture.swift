import Foundation
import XCTest
@testable import PixelPet

/// 测试用的构造辅助。
///
/// **为什么需要这层**：状态是时间戳驱动的，所以「造一个饿着的宠物」
/// 不是 `pet.satiety = 0.2`，而要反推 `lastFedAt = now - span * 0.8`。
/// 这个换算原来在测试里手写了 6 次。
///
/// `PetStore` 的临时目录 fixture 也重复了两处（`PetStoreTests` 与
/// `OpeningSequenceTests`）。
enum Fixture {

    // MARK: - PetStore

    /// 独立的临时目录。**只在需要验证真实文件读写时用** ——
    /// 一般测试走 `store()` 的内存实现，更快且不用清理。
    static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    /// 可测的 store，用内存存档 + 空提醒。
    ///
    /// 比之前的「临时目录 + 两个 bool 开关」干净：
    /// 依赖是注入的对象而非行为开关，且不碰文件系统。
    ///
    /// `PetStore` 是 `@MainActor`，所以只有这类方法需要隔离；
    /// 纯值类型的构造不需要，否则非隔离的测试用不了。
    @MainActor
    static func store(
        persistence: PetPersistence = MemoryPersistence()
    ) -> PetStore {
        PetStore(storage: persistence,
                 reminders: NoopReminders(),
                 runsHeartbeat: false)
    }

    /// 用真实文件存档的 store。验证「重开 app 后状态还在」时用。
    @MainActor
    static func store(in dir: URL) -> PetStore {
        PetStore(storage: FilePersistence(directory: dir),
                 reminders: NoopReminders(),
                 runsHeartbeat: false)
    }

    // MARK: - PetState

    /// 造一个指定状态的宠物。
    ///
    /// 参数是**目标比例**（0 = 空，1 = 满），内部反推时间戳。
    /// 比手写 `lastFedAt = now - 8*3600*0.8` 可读得多。
    ///
    /// - Note: 新建的 `PetState` 是幼年期（0 天），饱食周期 12h。
    ///   要测成年期得改 `bornAt`，见 `aged(days:)`。
    static func pet(satiety: Double = 1.0,
                    mood: Double = 1.0,
                    hygiene: Double = 1.0,
                    now: Date = Date()) -> PetState {
        var p = PetState(now: now)
        let stage = p.stage
        p.lastFedAt = now.addingTimeInterval(
            -PetState.Decay.hunger(for: stage) * (1 - satiety))
        p.lastPlayedAt = now.addingTimeInterval(
            -PetState.Decay.mood * (1 - mood))
        p.lastCleanedAt = now.addingTimeInterval(
            -PetState.Decay.hygiene * (1 - hygiene))
        return p
    }

    /// 把宠物「养大」到指定天数，用于测阶段相关行为。
    ///
    /// ⚠️ `ageInDays` 内部硬调 `Date()`，所以只能靠改 `bornAt` 控制，
    /// 不能注入时间。这是目前经济测试只能覆盖幼年期的原因。
    static func aged(_ pet: PetState, days: Int) -> PetState {
        var p = pet
        p.bornAt = Calendar.current.date(byAdding: .day, value: -days,
                                         to: Date()) ?? Date()
        return p
    }

    /// 醒着的宠物 —— 避开深夜作息对测试的干扰。
    ///
    /// `isDrowsy` 看真实时钟（23:00-07:00），所以在夜里跑测试时
    /// 行为会变。需要确定性时给一个清醒宽限。
    static func awake(_ pet: PetState) -> PetState {
        var p = pet
        p.awakeUntil = Date().addingTimeInterval(3600)
        return p
    }

    // MARK: - RewardContext

    /// 奖励上下文。
    ///
    /// `RewardContext` 有 7 个字段且按位置构造，加字段会打断所有调用处 ——
    /// 集中在这里就只改一处。
    static func rewardContext(offlineHours: Double,
                              satiety: Double = 0.5,
                              mood: Double = 0.5,
                              remainingCap: Int = 9999,
                              pet: PetState = PetState(),
                              wallet: PetWallet = PetWallet(),
                              now: Date = Date()) -> RewardContext {
        RewardContext(pet: pet, wallet: wallet, now: now,
                      offlineHours: offlineHours,
                      avgSatiety: satiety, avgMood: mood,
                      remainingCap: remainingCap)
    }

    /// 用真实衰减算出平均状态的上下文（更接近实际结算）
    static func realRewardContext(offlineHours h: Double,
                                  wallet: PetWallet = PetWallet(),
                                  moodOverride: Double? = nil,
                                  remainingCap: Int = 9999) -> RewardContext {
        let pet = PetState()
        return RewardContext(
            pet: pet, wallet: wallet, now: Date(), offlineHours: h,
            avgSatiety: RewardEngine.averageLevel(
                offlineHours: h, cycleHours: pet.stage.hungerCycleHours),
            avgMood: moodOverride ?? RewardEngine.averageLevel(
                offlineHours: h, cycleHours: 18),
            remainingCap: remainingCap)
    }

    // MARK: - PetLineContext

    static func lineContext(satiety: Double = 0.5,
                           mood: Double = 0.5,
                           hygiene: Double = 0.5,
                           isDrowsy: Bool = false,
                           ageInDays: Int = 1,
                           trigger: PetLineContext.Trigger = .appeared)
    -> PetLineContext {
        PetLineContext(name: "T",
                       satiety: satiety, mood: mood, hygiene: hygiene,
                       isDrowsy: isDrowsy, ageInDays: ageInDays,
                       trigger: trigger)
    }
}

/// 给测试类用的 store 管理。
///
/// 默认走**内存存档** —— 快、无副作用、不用清理。
/// 需要验证真实文件读写时用 `makeFileStore()`。
@MainActor
class StoreTestCase: XCTestCase {

    /// 本次测试共享的内存存档。多次 `makeStore()` 会读到同一份数据，
    /// 用来模拟「重开 app」。
    private(set) var memory: MemoryPersistence!

    /// 临时目录，只在 `makeFileStore()` 时才建
    private var dir: URL?

    override func setUp() {
        super.setUp()
        memory = MemoryPersistence()
    }

    override func tearDown() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    /// 开一个 store，共享本次测试的内存存档。
    ///
    /// 连续调两次可以模拟「关掉 app 再打开」—— 第二次会读到第一次写的数据。
    func makeStore() -> PetStore { Fixture.store(persistence: memory) }

    /// 用真实文件的 store。验证 JSON 编解码往返时用。
    func makeFileStore() -> PetStore {
        if dir == nil { dir = Fixture.tempDirectory() }
        return Fixture.store(in: dir!)
    }
}
