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

    /// 全部宠物。**可以养多只** —— 商店买的每个品种都是一只独立的宠物，
    /// 各有自己的名字、状态、收益额度。
    ///
    /// 顺序即主页从左到右的摆放顺序。
    private(set) var pets: [PetState]

    /// 当前选中的宠物 id。喂食/玩耍/洗澡三个按钮作用于它。
    ///
    /// 主页同时显示所有宠物，点一下切换选中。
    private(set) var selectedPetID: String

    /// 选中的那只。读写都作用在它身上。
    ///
    /// 保留 `pet` 这个名字，让原有的几十处调用点不用全改 ——
    /// 单宠时期它就叫这个，语义也没变（「当前这只」）。
    /// 找不到选中的就退回第一只（存档损坏时的兜底）。
    var pet: PetState {
        get { pets.first { $0.id == selectedPetID } ?? pets[0] }
        set {
            if let i = pets.firstIndex(where: { $0.id == newValue.id }) {
                pets[i] = newValue
            } else if let i = pets.firstIndex(where: { $0.id == selectedPetID }) {
                pets[i] = newValue
            } else {
                pets[0] = newValue
            }
        }
    }

    /// 选中某只。喂食/玩耍/洗澡随即作用于它。
    func select(petID: String) {
        guard pets.contains(where: { $0.id == petID }) else { return }
        selectedPetID = petID
    }

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
        // 访问 self.pets / self.wallet 会编译失败。
        let loaded = storage.loadPets()
        let list = loaded.isEmpty
            ? [PetState(breedID: PetBreed.cat.id, colorIndex: 0, name: "")]
            : loaded
        let loadedWallet = storage.loadWallet() ?? PetWallet()

        self.pets = list
        self.selectedPetID = list[0].id
        self.wallet = loadedWallet

        // 首次启动必须立刻写盘 —— 否则 bornAt 每次启动都被重置，
        // 宠物永远显示「相伴第 0 天」。
        if loaded.isEmpty { storage.save(pets: list) }
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
        recordCareQuality(at: now)
        pet.lastSeenAt = now
        persist()
    }

    /// 记「今天照顾达标了吗」。
    ///
    /// **和连续天数分开。** `streakDays` 只要打开 app 就 +1 ——
    /// 所以放养 30 天照样拿满 `streak_30`（2000 枚），
    /// 时间型成就一度占全部成就金额的 61%，完全不看照顾质量。
    ///
    /// 这里按「当天三维平均 ≥ StateThreshold.wellCared」判定，
    /// 同一天只记一次。达标日累计进 `wellCaredDays`，
    /// `streak_*` 类成就改看这个数。
    private func recordCareQuality(at now: Date) {
        let cal = Calendar.current
        // 同一天已经记过就跳过
        if let last = pet.lastWellCaredDay,
           cal.isDate(last, inSameDayAs: now) { return }

        let avg = (pet.satiety(at: now) + pet.mood(at: now)
                   + pet.hygiene(at: now)) / 3
        guard avg >= StateThreshold.wellCared else { return }

        pet.wellCaredDays = (pet.wellCaredDays ?? 0) + 1
        pet.lastWellCaredDay = now
    }

    // MARK: - 奖励结算

    /// 结算奖励。返回结果供 UI 展示，nil = 无收益。
    /// 要在 markSeen() 之后调用 —— 连续天数会影响成就判定。
    ///
    /// **每只宠物各结算一次，各占自己的额度。** 养两只收入翻倍
    /// （粮钱也翻倍）。返回值把各只的收益合并，UI 只关心总数。
    ///
    /// ⚠️ 一次性奖励（成就、上线签到）只算一次 —— 它们属于玩家而非宠物。
    /// 所以第一只之后要把已领集合带进去，否则同一条成就会被发 N 次。
    @discardableResult
    func settleRewards(now: Date = Date()) -> RewardSettlement? {
        var total = 0
        var capped = 0
        var claimed: [String] = []
        var messages: [(key: String, args: [CVarArg])] = []
        var payouts: [(reason: CoinReason, coins: Int, ruleID: String)] = []

        for p in pets {
            let ctx = RewardEngine.makeContext(pet: p, wallet: wallet, now: now)
            let r = RewardEngine.default.settle(ctx)
            guard !r.isEmpty else { continue }

            for out in r.payouts {
                if out.reason.countsTowardDailyCap {
                    // 占额度的走 recordEarning：它维护 todayEarnedByPet 与跨日重置
                    wallet.recordEarning(out.coins, petID: p.id, at: now)
                } else {
                    wallet.recordBonus(out.coins, reason: out.reason,
                                       at: now, note: out.ruleID)
                }
            }
            // 立刻写进已领集合 —— 下一只结算时 RewardEngine 就会跳过它们，
            // 否则两只宠物会把同一条成就各领一遍。
            for id in r.newlyClaimed { wallet.claimedRewards.insert(id) }

            total += r.totalCoins
            capped += r.cappedCoins
            claimed += r.newlyClaimed
            messages += r.messages
            payouts += r.payouts
        }

        guard total > 0 || !messages.isEmpty else { return nil }
        wallet.lastCollectedAt = now
        persist()
        return RewardSettlement(totalCoins: total,
                                cappedCoins: capped,
                                newlyClaimed: claimed,
                                messages: messages,
                                payouts: payouts)
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

    /// 选中某个品种的宠物（用于宠物页切换查看）。
    ///
    /// ⚠️ **不再改变宠物的品种和毛色。** 现在每个品种是一只独立的宠物，
    /// 毛色在购买时定死 —— 曾经这个方法会把当前宠物「变成」另一个品种，
    /// 那是单宠时期「买品种 = 解锁外观」模型的产物。
    @discardableResult
    func choose(breedID: String, colorIndex: Int = 0) -> Bool {
        guard let target = pets.first(where: { $0.breedID == breedID }) else {
            return false
        }
        selectedPetID = target.id
        return true
    }

    // MARK: - 开局与商店

    /// 是否还没走完开局流程（选宠物 + 起名）
    var needsOnboarding: Bool { !wallet.hasCompletedOnboarding }

    /// 完成开局：扣掉首宠价格、起名。
    ///
    /// 首宠从启动资金里扣（5000 送、4000 扣），让「选宠物」有重量感 ——
    /// 直接送的话开局的选择缺少代价。剩下 1000 作为起步资金。
    ///
    /// **毛色在这里定死。** 之后只能改名字，不能换色 ——
    /// 想要别的颜色就再买一只（每只都是独立的宠物）。
    @discardableResult
    func completeOnboarding(breedID: String, colorIndex: Int,
                            name: String) -> Bool {
        let breed = PetBreed.byID(breedID)
        guard wallet.spend(breed.price, reason: .starterPet,
                           note: breed.id) else { return false }
        wallet.ownedBreeds.insert(breed.id)
        wallet.hasCompletedOnboarding = true

        // 开局那只直接改写 pets[0]（init 造的占位），
        // 而不是 append —— 否则会多出一只没人要的默认猫。
        var first = pets[0]
        first.breedID = breed.id
        first.colorIndex = colorIndex
        first.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines)
                                .prefix(12))
        var breeds = first.triedBreeds ?? []; breeds.insert(breed.id)
        first.triedBreeds = breeds
        var colors = first.triedColors ?? []; colors.insert(colorIndex)
        first.triedColors = colors
        pets[0] = first
        selectedPetID = first.id

        persist()
        return true
    }

    /// 买一只新宠物。
    ///
    /// **这是真的多一只**，不是解锁外观 —— 新宠物有自己的 id、名字、
    /// 状态时间戳、收益额度。主页会同时显示所有宠物。
    ///
    /// 毛色在购买时定死，之后不能改。
    @discardableResult
    func purchase(_ breed: PetBreed, colorIndex: Int = 0) -> Bool {
        guard wallet.canAfford(breed) else { return false }
        guard wallet.spend(breed.price, reason: .breedPurchase,
                           note: breed.id) else { return false }
        wallet.ownedBreeds.insert(breed.id)

        var newPet = PetState(breedID: breed.id, colorIndex: colorIndex, name: "")
        newPet.triedBreeds = [breed.id]
        newPet.triedColors = [colorIndex]
        pets.append(newPet)
        selectedPetID = newPet.id      // 买完直接选中它，方便马上起名

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

    /// 把时间往前推，模拟放置一段时间。
    ///
    /// **作用于全部宠物**，不只选中那只 —— 否则养两只时会出现
    /// 「一只饿透了另一只刚吃过」的假状态，看不出真实的多宠表现。
    ///
    /// `bornAt` 也要推：不推的话「前进一周」宠物不会长大，
    /// 而年龄相关的东西（阶段、额度、成就）全都测不到。
    /// `lastCollectedAt` 同理 —— 不推的话离线收益永远是 0。
    func debugAge(by seconds: TimeInterval) {
        for i in pets.indices {
            pets[i].lastFedAt = pets[i].lastFedAt.addingTimeInterval(-seconds)
            pets[i].lastPlayedAt = pets[i].lastPlayedAt.addingTimeInterval(-seconds)
            pets[i].lastCleanedAt = pets[i].lastCleanedAt.addingTimeInterval(-seconds)
            pets[i].bornAt = pets[i].bornAt.addingTimeInterval(-seconds)
            pets[i].awakeUntil = nil          // 清掉「被叫醒」，否则不会犯困
        }
        wallet.lastCollectedAt = wallet.lastCollectedAt.addingTimeInterval(-seconds)
        persist()
        refresh()
    }

    /// 直接发钱。
    ///
    /// 走账本记一笔 `debugGrant` —— 所以账目仍然平，
    /// 而且流水里看得见「这笔是调试加的」，
    /// 不会再出现「为什么我有这么多金币」查不出来的情况。
    func debugAddCoins(_ amount: Int) {
        wallet.earn(amount, reason: .debugGrant, note: "debug +\(amount)")
        persist()
        refresh()
    }

    /// 把状态调到指定比例（0 = 空，1 = 满），作用于选中那只。
    func debugSetStats(satiety: Double? = nil,
                      mood: Double? = nil,
                      hygiene: Double? = nil) {
        let now = Date()
        var p = pet
        if let s = satiety {
            p.lastFedAt = now.addingTimeInterval(
                -PetState.Decay.hunger(for: p.stage) * (1 - s))
        }
        if let m = mood {
            p.lastPlayedAt = now.addingTimeInterval(-PetState.Decay.mood * (1 - m))
        }
        if let h = hygiene {
            p.lastCleanedAt = now.addingTimeInterval(-PetState.Decay.hygiene * (1 - h))
        }
        pet = p
        persist()
        refresh()
    }

    /// 清掉已领成就记录，让它们可以重新触发（验证成就文案/金额时用）。
    func debugResetAchievements() {
        wallet.claimedRewards = []
        persist()
        refresh()
    }

    /// 删掉选中的宠物。至少留一只 —— 空数组会让 `pet` 崩。
    func debugRemoveSelectedPet() {
        guard pets.count > 1 else { return }
        pets.removeAll { $0.id == selectedPetID }
        selectedPetID = pets[0].id
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
        storage.save(pets: pets)
        tick = Date()
        // 状态变了就重排提醒 —— 因为「何时会饿」是从时间戳算的
        let name = pet.name.isEmpty ? L(pet.breed.nameKey) : pet.name
        reminders.reschedule(for: pet, petName: name)
    }
}
