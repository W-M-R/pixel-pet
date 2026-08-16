import Foundation
import Observation

/// 宠物状态的唯一持有者。
///
/// 所有状态变更都经过这里，因为每次变更都要落盘 —— 分散写会漏。
/// `@Observable` 让 SwiftUI 自动跟随。
///
/// 存档与提醒都通过协议注入（`PetPersistence` / `PetReminderScheduling`），
/// 所以测试可以用内存实现，不碰文件系统也不碰系统通知。
@Observable
@MainActor
final class PetStore {

    private(set) var pet: PetState
    private(set) var wallet: PetWallet

    /// 存档后端。协议而非具体类型 —— 测试注入 `MemoryPersistence`。
    private let storage: PetPersistence
    /// 提醒调度。测试注入 `NoopReminders`。
    private let reminders: PetReminderScheduling

    /// 驱动 UI 定时刷新的心跳。状态本身是按时间戳算的，
    /// 但 SwiftUI 需要一个变化信号才会重绘。
    private(set) var tick: Date = Date()
    private var timer: Timer?

    /// - Parameters:
    ///   - storage: 存档后端。默认写 Application Support。
    ///   - reminders: 提醒调度。默认走系统通知。
    ///   - runsHeartbeat: 是否跑心跳定时器。测试关掉，否则会留下 Timer。
    init(storage: PetPersistence = FilePersistence(),
         reminders: (any PetReminderScheduling)? = nil,
         runsHeartbeat: Bool = true) {
        self.storage = storage
        // 默认值不能写在参数列表里 —— SystemReminders 是 @MainActor，
        // 而参数默认值在非隔离上下文求值。init 本身是 @MainActor，
        // 所以在这里构造是安全的。
        self.reminders = reminders ?? SystemReminders()

        // 用局部变量算好再赋值 —— init 里在所有 stored property 就位前
        // 访问 self.pet / self.wallet 会编译失败。
        let loadedPet = storage.loadPet()
            ?? PetState(breedID: PetBreed.cat.id, colorIndex: 0, name: "")
        let loadedWallet = storage.loadWallet() ?? PetWallet()

        self.pet = loadedPet
        self.wallet = loadedWallet

        // 首次启动必须立刻写盘 —— 否则 bornAt 每次启动都被重置，
        // 宠物永远显示「相伴第 0 天」。
        if storage.loadPet() == nil { storage.save(pet: loadedPet) }
        if storage.loadWallet() == nil { storage.save(wallet: loadedWallet) }

        if runsHeartbeat { startHeartbeat() }
    }

    // 注：@MainActor 类的 deinit 不能访问隔离状态，
    // 所以不在这里 invalidate。PetStore 生命周期与 app 相同，可忽略。

    private func startHeartbeat() {
        // 10 秒一次足够。数值变化本来就慢，刷太勤只是白耗电。
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.tick = Date()
        }
    }

    /// 从后台回到前台时立刻刷一次，不等下一个心跳。
    func refresh() { tick = Date() }

    /// 距上次打开过了几天。用于"久别重逢"台词。
    var daysSinceLastSeen: Int {
        guard let last = pet.lastSeenAt else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0)
    }

    /// 记录本次打开。要在读过 daysSinceLastSeen 之后调用。
    /// 记录本次打开，并更新连续打开天数。
    ///
    /// 按**日历天**去重：同一天多次打开只算一次；隔一天算连续；
    /// 隔两天以上断签重置为 1。要在读过 daysSinceLastSeen 之后调用。
    func markSeen() {
        let now = Date()
        let cal = Calendar.current
        if let last = pet.lastStreakDay {
            let d = cal.dateComponents([.day],
                                       from: cal.startOfDay(for: last),
                                       to: cal.startOfDay(for: now)).day ?? 0
            if d == 1 {
                pet.streakDays = (pet.streakDays ?? 0) + 1
                pet.lastStreakDay = now
            } else if d >= 2 {
                pet.streakDays = 1                  // 断签
                pet.lastStreakDay = now
            }
            // d == 0：同一天，不动
        } else {
            pet.streakDays = 1
            pet.lastStreakDay = now
        }
        pet.lastSeenAt = now
        persist()
    }

    // MARK: - 奖励结算

    /// 结算奖励。返回结果供 UI 展示，nil = 无收益。
    /// 要在 markSeen() 之后调用 —— 连续天数会影响成就判定。
    @discardableResult
    func settleRewards(now: Date = Date()) -> RewardSettlement? {
        let ctx = RewardEngine.makeContext(pet: pet, wallet: wallet, now: now)
        let result = RewardEngine.default.settle(ctx)
        guard !result.isEmpty else { return nil }

        // 逐笔入账 —— 账本里能分清签到 / 成就 / 看家。
        // 之前是「看家一笔 + 其余合并一笔」，排查时分不出后者的来源。
        for p in result.payouts {
            if p.reason.countsTowardDailyCap {
                // 占额度的要走 recordEarning：它额外维护 todayEarned 与跨日重置
                wallet.recordEarning(p.coins, at: now)
            } else {
                wallet.recordBonus(p.coins, reason: p.reason, at: now, note: p.ruleID)
            }
        }
        for id in result.newlyClaimed { wallet.claimedRewards.insert(id) }
        wallet.lastCollectedAt = now
        persist()
        return result
    }

    /// 某条成就的进度。已领取或无进度型返回 nil。
    func achievementProgress(_ rule: AchievementRule) -> (current: Int, target: Int)? {
        guard !wallet.claimedRewards.contains(rule.id), let p = rule.progress else { return nil }
        let (c, t) = p(pet, wallet)
        return (c, t)
    }

    func isClaimed(_ rule: AchievementRule) -> Bool {
        wallet.claimedRewards.contains(rule.id)
    }

    /// 当前状态快照，供台词生成用。
    func lineContext(trigger: PetLineContext.Trigger) -> PetLineContext {
        let now = Date()
        return PetLineContext(
            name: pet.name.isEmpty
                ? L(pet.breed.nameKey)
                : pet.name,
            satiety: pet.satiety(at: now),
            mood: pet.mood(at: now),
            hygiene: pet.hygiene(at: now),
            isDrowsy: pet.isDrowsy(at: now),
            ageInDays: pet.ageInDays,
            trigger: trigger)
    }

    // MARK: - 互动

    /// 能否买得起。
    ///
    /// 按量计价，所以价格取决于**当前饱食度** —— 越饱越便宜。
    func canAfford(_ food: FoodItem, at now: Date = Date()) -> Bool {
        wallet.coins >= food.cost(currentSatiety: pet.satiety(at: now))
    }

    /// 喂食。返回是否成功（钱不够会失败）。
    @discardableResult
    func feed(_ food: FoodItem = .kibble) -> Bool {
        extendAwakeIfNeeded()
        let now = Date()

        // ⚠️ 顺序要紧：按量计价必须**先读饱食度**再算价扣钱。
        // 之前是先扣钱后读饱食，算出来的价基准是错的。
        let before = pet.satiety(at: now)
        let price = food.cost(currentSatiety: before)

        // 剩饭是 0 价，不记流水（`apply` 只接受正数）。
        // 写成显式的 if 而不是 `spend(...) || price == 0` ——
        // 后者读起来像「花钱失败也放过」，容易被误改成真的绕过扣钱。
        if price > 0 {
            guard wallet.spend(price, reason: .food, at: now, note: food.id) else {
                return false
            }
        }

        // 饱食：加到当前值并封顶。
        // 用「反推 lastFedAt」而不是存数值 —— 状态必须保持时间戳驱动。
        let after = min(1.0, before + food.satietyRestore)
        pet.lastFedAt = now.addingTimeInterval(
            -(1 - after) * PetState.Decay.hunger(for: pet.stage))

        if food.moodBonus > 0 {
            let m = min(1.0, pet.mood(at: now) + food.moodBonus)
            pet.lastPlayedAt = now.addingTimeInterval(
                -(1 - m) * PetState.Decay.mood(for: pet.breed))
        }

        if food.grantsBoost {
            wallet.boostUntil = now.addingTimeInterval(FoodItem.boostDuration)
        }

        pet.totalFeedCount = (pet.totalFeedCount ?? 0) + 1
        var counts = pet.foodCounts ?? [:]
        counts[food.id, default: 0] += 1
        pet.foodCounts = counts

        persist()
        return true
    }

    /// 执行一次互动。
    ///
    /// play/clean 原本是两个逐字同构的 4 行方法，每加一个互动就复制一次。
    /// 现在把「改哪个时间戳、涨哪个计数」交给 `InteractionEffect.apply`。
    ///
    /// 参数是 `InteractionEffect`（Models）而非 `Interaction`（Views）——
    /// Services 不该依赖 UI 配置。
    func perform(_ effect: InteractionEffect) {
        extendAwakeIfNeeded()
        effect.apply(&pet, Date())
        persist()
    }

    /// 保留具名方法 —— 调用处读起来比 `perform(.play)` 更直白，
    /// 且测试和调试面板已在用。
    func play() { perform(.play) }

    /// 抚摸。也算陪玩（涨心情），但独立成一个方法，
    /// 因为要加冷却 —— 连续戳不该无限刷心情。
    ///
    /// 注意：抚摸**不该**让宠物犯困。睡觉由 PetState.isDrowsy 的
    /// 作息决定，和这里无关。
    @discardableResult
    func stroke(cooldown: TimeInterval = 1.5) -> Bool {
        let now = Date()
        if let last = lastStrokeAt, now.timeIntervalSince(last) < cooldown {
            return false        // 冷却中
        }
        lastStrokeAt = now
        pet.lastPlayedAt = now
        persist()
        return true
    }

    private var lastStrokeAt: Date?

    /// 叫醒宠物，并维持一段清醒。
    ///
    /// 没有这个的话，夜里戳宠物它会站起来，然后下一次 10 秒心跳
    /// 又把它按回去睡 —— 用户完全没法在睡眠时段跟它互动。
    func wakeUp() {
        pet.awakeUntil = Date().addingTimeInterval(PetState.NightTime.awakeGrace)
        persist()
    }

    /// 任何主动互动都顺带延长清醒时间。
    /// 喂食/玩耍/洗澡的时候宠物不该还趴着。
    private func extendAwakeIfNeeded() {
        guard pet.isDrowsy() else { return }
        wakeUp()
    }

    func clean() { perform(.clean) }

    func rename(_ newName: String) {
        pet.name = newName
        persist()
    }

    /// 切换品种/毛色。
    ///
    /// ⚠️ 只能切**已拥有**的品种。买过就永久解锁，之后免费切换 ——
    /// 「买」是一次性解锁而非消耗品，否则玩家会不敢换。
    @discardableResult
    func choose(breedID: String, colorIndex: Int) -> Bool {
        let breed = PetBreed.byID(breedID)
        guard wallet.owns(breed) else { return false }

        pet.breedID = breedID
        pet.colorIndex = colorIndex
        // 记录用于收藏成就
        var breeds = pet.triedBreeds ?? []; breeds.insert(breedID); pet.triedBreeds = breeds
        var colors = pet.triedColors ?? []; colors.insert(colorIndex); pet.triedColors = colors
        persist()
        return true
    }

    // MARK: - 开局与商店

    /// 是否还没走完开局流程（选宠物 + 起名）
    var needsOnboarding: Bool { !wallet.hasCompletedOnboarding }

    /// 完成开局：扣掉首宠价格、解锁该品种、起名。
    ///
    /// 首宠从启动资金里扣（5000 送、4000 扣），让「选宠物」有重量感 ——
    /// 直接送的话开局的选择缺少代价。剩下 1000 作为起步资金。
    @discardableResult
    func completeOnboarding(breedID: String, colorIndex: Int,
                            name: String) -> Bool {
        let breed = PetBreed.byID(breedID)
        guard breed.isStarter else { return false }   // 开局只能选免费品种
        guard wallet.spend(PetWallet.starterPrice, reason: .starterPet,
                           note: breed.id) else { return false }
        wallet.ownedBreeds.insert(breed.id)
        wallet.hasCompletedOnboarding = true

        pet.breedID = breed.id
        pet.colorIndex = colorIndex
        pet.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines)
                              .prefix(12))
        var breeds = pet.triedBreeds ?? []; breeds.insert(breed.id)
        pet.triedBreeds = breeds
        var colors = pet.triedColors ?? []; colors.insert(colorIndex)
        pet.triedColors = colors

        persist()
        return true
    }

    /// 买一个新品种。买完不自动切换 —— 让玩家自己决定什么时候换。
    @discardableResult
    func purchase(_ breed: PetBreed) -> Bool {
        guard wallet.purchase(breed) else { return false }
        persist()
        return true
    }

    func owns(_ breed: PetBreed) -> Bool { wallet.owns(breed) }

    /// 调试用：把时间戳往前推，模拟放置一段时间后的状态。
    /// 这是验证「读时算」是否正确的最快方式。
    #if DEBUG
    /// 测试专用：直接置入状态以构造场景。
    ///
    /// `pet`/`wallet` 是 `private(set)` —— 生产代码只能通过语义方法改状态，
    /// 这个约束是对的，不放开。测试要造「饿透的宠物」「没钱的钱包」
    /// 这类场景，走这个显式的后门比放开 setter 安全。
    func debugSet(pet newPet: PetState? = nil, wallet newWallet: PetWallet? = nil) {
        if let newPet { pet = newPet }
        if let newWallet { wallet = newWallet }
    }

    func debugAge(by seconds: TimeInterval) {
        pet.lastFedAt = pet.lastFedAt.addingTimeInterval(-seconds)
        pet.lastPlayedAt = pet.lastPlayedAt.addingTimeInterval(-seconds)
        pet.lastCleanedAt = pet.lastCleanedAt.addingTimeInterval(-seconds)
        persist()
        refresh()
    }

    /// 调试用：把 bornAt 往前推，直接跳到指定阶段。
    func debugSetStage(_ stage: PetStage) {
        pet.bornAt = Calendar.current.date(byAdding: .day,
                                           value: -stage.minDays, to: Date()) ?? Date()
        persist()
        refresh()
    }
    #endif

    func resetAll() {
        wallet = PetWallet()
        pet = PetState(breedID: pet.breedID, colorIndex: pet.colorIndex, name: pet.name)
        persist()
        refresh()
    }

    private func persist() {
        storage.save(wallet: wallet)
        storage.save(pet: pet)
        tick = Date()
        // 状态变了就重排提醒 —— 因为「何时会饿」是从时间戳算的
        let name = pet.name.isEmpty ? L(pet.breed.nameKey) : pet.name
        reminders.reschedule(for: pet, petName: name)
    }
}
