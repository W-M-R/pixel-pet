import Foundation

/// 钱包。
///
/// **独立于 `PetState` 存档**（`wallet.json`）—— 换宠物不该清空钱包，
/// 两者生命周期不同。也让 `PetState` 已经很复杂的解码兼容逻辑不再变复杂。
struct PetWallet: Codable, Equatable {

    /// 金币账本 —— **所有余额变动的唯一入口**。
    ///
    /// 之前 `coins` 是裸 `var`，收入走方法但支出三处裸写 `coins -=`。
    /// 现在收支都经过 `ledger.apply(_:reason:)`，账目可自检、流水可追溯。
    /// 详见 `CoinLedger` 的类型注释。
    private(set) var ledger: CoinLedger

    /// 当前金币。只读 —— 要改就得说明原因，见 `spend` / `earn`。
    var coins: Int { ledger.balance }

    /// 上次结算时间。离线收益与上线奖励都以它为基准。
    var lastCollectedAt: Date

    /// 小鱼干 buff 到期时间。nil = 无 buff。
    ///
    /// 存在钱包而非 `PetState`：它是经济系统的一部分，换宠物不该清除。
    var boostUntil: Date?

    /// 累计赚取（只增不减，成就用）
    var totalEarned: Int

    /// 今日已从看家收益赚到的额度，**按宠物分开记**。
    ///
    /// key 是 `PetState.id`。每只宠物各有一份额度（你定的方案）——
    /// 养两只收入翻倍，但粮钱也翻倍。
    ///
    /// **必须落盘。** 只在内存里算的话，反复开关 app 每次都能拿满额度 ——
    /// 这是额度制最主要的刷币面。
    var todayEarnedByPet: [String: Int]

    /// 全部宠物今日合计。UI 展示用。
    var todayEarned: Int { todayEarnedByPet.values.reduce(0, +) }

    /// `todayEarned` 对应的日期，用于判断跨日
    var lastEarnDate: Date

    /// 已领取的一次性奖励 ID
    var claimedRewards: Set<String>

    /// 已拥有的品种 ID。
    ///
    /// 开局选的那只自动进来。买新品种要先付钱，之后可以随时免费切换 ——
    /// 「买」是一次性解锁，不是消耗品。
    var ownedBreeds: Set<String>

    /// 已购家具的 id（含用品与装饰）。
    ///
    /// 和 `ownedBreeds` 分开：宠物买一次多一只（可以买重复的），
    /// 家具是**一次性解锁**（买了就摆在房间里，再买没有意义）。
    var ownedFurniture: Set<String>

    /// 当前选中哪只宠物。
    ///
    /// **必须落盘。** 喂食/玩耍/洗澡三个按钮、状态栏、台词全部作用于
    /// 选中那只 —— 不存的话重启后跳回第一只，玩家按「喂食」会喂到
    /// **另一只宠物**，而且没有任何提示（界面显示的就是第一只的名字，
    /// 看起来一切正常）。
    ///
    /// 存在钱包而非宠物存档：宠物存档是数组，"选了哪个"是玩家的偏好，
    /// 不属于任何一只宠物自己的属性。
    var selectedPetID: String?

    /// 是否已完成开局（选宠物 + 起名）。
    ///
    /// 存在钱包而非 PetState —— 重置宠物不该让人重走开局流程，
    /// 而且它和「送启动资金」这件事是同一个语义。
    var hasCompletedOnboarding: Bool

    /// 启动资金。
    ///
    /// 5000 枚，其中 4000 用于买第一只宠物，余 1000 起步。
    ///
    /// 1000 枚够买 28 份普通粮（35/份）或 6 份罐头 ——
    /// 有「刚好够用但要省着花」的紧张感，又不至于卡死（剩饭永久免费）。
    ///
    /// 定价推导见 docs/07-shop.md。
    static let initialCoins = 5000

    /// 第一只宠物的价格。
    ///
    /// 从启动资金里扣，让「选宠物」这件事有重量感 ——
    /// 直接送一只的话，开局的选择缺少代价。
    ///
    /// ⚠️ 真正扣的是 `PetBreed.price`（每个品种可以不同价）。
    /// 这个常量只用于开局界面的文案展示，两者由
    /// `ConfigTests.testStarterPriceMatchesBreeds` 断言一致。
    static let starterPrice = 4000

    init(now: Date = Date()) {
        ledger = CoinLedger(initial: Self.initialCoins, at: now)
        lastCollectedAt = now
        boostUntil = nil
        totalEarned = 0
        todayEarnedByPet = [:]
        lastEarnDate = now
        claimedRewards = []
        ownedBreeds = []
        ownedFurniture = []
        selectedPetID = nil
        hasCompletedOnboarding = false
    }

    // MARK: - 品种拥有

    func owns(_ breed: PetBreed) -> Bool {
        // 开局品种只要买过就算拥有；其余看解锁记录
        ownedBreeds.contains(breed.id)
    }

    /// 能否买得起某个品种
    func canAfford(_ breed: PetBreed) -> Bool {
        ledger.canAfford(breed.price)
    }

    /// 购买品种。返回是否成功。
    @discardableResult
    mutating func purchase(_ breed: PetBreed, at now: Date = Date()) -> Bool {
        guard !owns(breed) else { return true }   // 已拥有，幂等

        // 免费品种（`isStarter`，price == 0）直接解锁：
        // `spend` 只接受正数，0 价会被当成非法调用拒掉。
        if breed.price > 0 {
            guard spend(breed.price, reason: .breedPurchase,
                        at: now, note: breed.id) else { return false }
        }
        ownedBreeds.insert(breed.id)
        return true
    }

    /// 是否已拥有某件家具
    func owns(_ item: FurnitureItem) -> Bool {
        ownedFurniture.contains(item.id)
    }

    func canAfford(_ item: FurnitureItem) -> Bool {
        ledger.canAfford(item.price)
    }

    /// 买家具。一次性解锁，买过再买直接成功（幂等）。
    @discardableResult
    mutating func purchase(_ item: FurnitureItem, at now: Date = Date()) -> Bool {
        guard !owns(item) else { return true }
        guard spend(item.price, reason: .furniture,
                    at: now, note: item.id) else { return false }
        ownedFurniture.insert(item.id)
        return true
    }

    // MARK: - 每日额度

    /// 某只宠物今日剩余额度。跨日自动视为满额。
    func remainingCap(stage: PetStage, petID: String, at now: Date = Date()) -> Int {
        let cap = stage.dailyCap
        guard Calendar.current.isDate(lastEarnDate, inSameDayAs: now) else {
            return cap
        }
        return max(0, cap - (todayEarnedByPet[petID] ?? 0))
    }

    /// 记一笔看家收益。跨日先归零，再累加。
    ///
    /// 日历逻辑收在这里，`PetStore` 只调一次 —— 避免跨日判断散落多处。
    mutating func recordEarning(_ amount: Int,
                                petID: String,
                                at now: Date = Date()) {
        guard amount > 0 else { return }
        if !Calendar.current.isDate(lastEarnDate, inSameDayAs: now) {
            todayEarnedByPet = [:]          // 跨日整表清空
        }
        todayEarnedByPet[petID, default: 0] += amount
        lastEarnDate = now
        earn(amount, reason: .offlineCare, at: now, note: petID)
    }

    /// 记一笔不占额度的收入（上线奖励、成就）
    mutating func recordBonus(_ amount: Int,
                              reason: CoinReason = .achievement,
                              at now: Date = Date(),
                              note: String? = nil) {
        guard !reason.countsTowardDailyCap else {
            assertionFailure("占额度的收入要走 recordEarning，否则 todayEarned 不同步")
            return
        }
        earn(amount, reason: reason, at: now, note: note)
    }

    // MARK: - 收支统一入口

    /// 记一笔收入。
    ///
    /// `totalEarned` 在这里同步 —— 它是成就的判定依据，
    /// 语义是「累计赚了多少」，所以只跟收入走，不含 `initialGrant` 之外的调试发钱。
    mutating func earn(_ amount: Int,
                       reason: CoinReason,
                       at now: Date = Date(),
                       note: String? = nil) {
        guard reason.isIncome else {
            assertionFailure("\(reason) 是支出，该调 spend")
            return
        }
        guard ledger.apply(amount, reason: reason, at: now, note: note) else { return }
        if reason != .initialGrant && reason != .debugGrant {
            totalEarned += amount
        }
    }

    /// 记一笔支出。返回是否成功（余额不足会失败且不扣钱）。
    ///
    /// **所有花钱的地方都必须走这里** —— 之前喂食和买首宠是裸写
    /// `wallet.coins -= price`，绕过了任何记账。
    @discardableResult
    mutating func spend(_ amount: Int,
                        reason: CoinReason,
                        at now: Date = Date(),
                        note: String? = nil) -> Bool {
        guard !reason.isIncome else {
            assertionFailure("\(reason) 是收入，该调 earn")
            return false
        }
        return ledger.apply(amount, reason: reason, at: now, note: note)
    }

    // MARK: - buff

    /// buff 是否生效
    func hasBoost(at now: Date = Date()) -> Bool {
        guard let until = boostUntil else { return false }
        return now < until
    }

    /// 达成率倍率
    func boostMultiplier(at now: Date = Date()) -> Double {
        hasBoost(at: now) ? FoodItem.boostMultiplier : 1.0
    }

    // MARK: - 解码兼容

    private enum CodingKeys: String, CodingKey {
        case coins, lastCollectedAt, boostUntil, totalEarned
        case todayEarned, todayEarnedByPet, lastEarnDate, claimedRewards
        case ownedBreeds, ownedFurniture, hasCompletedOnboarding
        case selectedPetID
        case ledger
    }

    /// 所有字段都用 decodeIfPresent —— 将来加字段时旧存档不会解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalEarned = try c.decodeIfPresent(Int.self, forKey: .totalEarned) ?? 0
        if let saved = try c.decodeIfPresent(CoinLedger.self, forKey: .ledger) {
            ledger = saved
        } else {
            // 旧存档只有裸 coins，没有账本。用它作期初余额重建 ——
            // 历史流水无从恢复，但余额必须一分不差（不能让人凭空少钱）。
            let legacy = try c.decodeIfPresent(Int.self, forKey: .coins) ?? Self.initialCoins
            ledger = CoinLedger(initial: legacy, at: Date())
        }
        lastCollectedAt = try c.decodeIfPresent(Date.self, forKey: .lastCollectedAt) ?? Date()
        boostUntil = try c.decodeIfPresent(Date.self, forKey: .boostUntil)
        if let byPet = try c.decodeIfPresent([String: Int].self, forKey: .todayEarnedByPet) {
            todayEarnedByPet = byPet
        } else {
            // 旧存档只有一个总数、只有一只宠物。归到 "primary" 名下 ——
            // 和 PetState 解码时给旧存档补的 id 一致，否则今日额度会凭空重置。
            let legacy = try c.decodeIfPresent(Int.self, forKey: .todayEarned) ?? 0
            todayEarnedByPet = legacy > 0 ? [PetState.legacyID: legacy] : [:]
        }
        lastEarnDate = try c.decodeIfPresent(Date.self, forKey: .lastEarnDate) ?? .distantPast
        claimedRewards = try c.decodeIfPresent(Set<String>.self, forKey: .claimedRewards) ?? []
        ownedBreeds = try c.decodeIfPresent(Set<String>.self, forKey: .ownedBreeds) ?? []
        ownedFurniture = try c.decodeIfPresent(Set<String>.self,
                                               forKey: .ownedFurniture) ?? []
        selectedPetID = try c.decodeIfPresent(String.self, forKey: .selectedPetID)
        // 旧存档没有这个字段。如果已经有宠物在养（钱包被用过），
        // 视为已完成开局，不该把老用户拉回选宠界面。
        if let done = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) {
            hasCompletedOnboarding = done
        } else {
            hasCompletedOnboarding = (totalEarned > 0 || !claimedRewards.isEmpty)
        }
    }

    /// 手写编码。
    ///
    /// `coins` 现在是计算属性，合成的 encode 不会写它。但仍要落盘 ——
    /// 一是万一要降级到旧版本，二是直接看 json 排查时不用去 ledger 里翻。
    /// 解码时 `ledger` 优先，`coins` 只在没有账本的旧存档里当期初余额。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ledger, forKey: .ledger)
        try c.encode(coins, forKey: .coins)          // 冗余，供降级/排查
        try c.encode(lastCollectedAt, forKey: .lastCollectedAt)
        try c.encodeIfPresent(boostUntil, forKey: .boostUntil)
        try c.encode(totalEarned, forKey: .totalEarned)
        try c.encode(todayEarnedByPet, forKey: .todayEarnedByPet)
        try c.encode(todayEarned, forKey: .todayEarned)   // 冗余，供降级/排查
        try c.encode(lastEarnDate, forKey: .lastEarnDate)
        try c.encode(claimedRewards, forKey: .claimedRewards)
        try c.encode(ownedBreeds, forKey: .ownedBreeds)
        try c.encode(ownedFurniture, forKey: .ownedFurniture)
        try c.encodeIfPresent(selectedPetID, forKey: .selectedPetID)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }
}

#if DEBUG
extension PetWallet {
    /// 直接设定余额。**仅测试/调试用**，走账本记一笔 `debugGrant`。
    ///
    /// 生产代码要花钱/发钱必须走 `spend` / `earn` —— 那里有原因和流水。
    mutating func debugSetCoins(_ amount: Int, at now: Date = Date()) {
        ledger.debugSetBalance(amount, at: now)
    }
}
#endif
