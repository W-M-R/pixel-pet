import Foundation

/// 宠物种类。目前 sheet 只有猫和狗，各 4 色。
enum PetSpecies: String, Codable, CaseIterable, Identifiable {
    case cat
    case dog

    var id: String { rawValue }
    /// 对应 Assets/pets/ 下的文件名
    var sheetName: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .cat: return "species.cat"
        case .dog: return "species.dog"
        }
    }
}

/// 宠物状态。
///
/// 设计要点：**只存时间戳，不存当前数值。**
///
/// iOS 不给第三方 app 后台定时器，所以「饥饿度随时间上升」这件事没法在后台推进。
/// 如果存 `hunger: Double` 然后靠定时器累加，app 一进后台就停了，用户下次打开
/// 会看到一个停在原地的假数值。
///
/// 正解是存「上次喂食是什么时候」，需要用到饥饿度时按 `now - lastFedAt` 算。
/// 这样无论 app 关多久、设备重启几次，读出来的值都是对的。
struct PetState: Codable, Equatable {
    var species: PetSpecies
    var colorIndex: Int
    var name: String

    var bornAt: Date
    var lastFedAt: Date
    var lastPlayedAt: Date
    var lastCleanedAt: Date

    /// 各维度从「满」降到「空」所需的秒数。
    ///
    /// 节奏设计：养成类的关键是「一天打开两三次刚好」。
    /// - 饱食 12h：早晚各喂一次
    /// - 心情 18h：一天陪一次就够
    /// - 清洁 3 天：低频维护，不制造焦虑
    ///
    /// 故意让三条线的周期不同步，这样每次打开看到的「最紧急需求」会变化，
    /// 比三条线一起见底更有意思。
    enum Decay {
        static let hunger: TimeInterval   = 12 * 3600
        static let mood: TimeInterval     = 18 * 3600
        static let hygiene: TimeInterval  = 72 * 3600
    }

    init(species: PetSpecies = .cat,
         colorIndex: Int = 0,
         name: String = "",
         now: Date = Date()) {
        self.species = species
        self.colorIndex = colorIndex
        self.name = name
        self.bornAt = now
        self.lastFedAt = now
        self.lastPlayedAt = now
        self.lastCleanedAt = now
    }

    // MARK: - 派生数值（读时计算，全部 0...1）

    /// 1 = 饱，0 = 饿透
    func satiety(at now: Date = Date()) -> Double {
        remaining(since: lastFedAt, span: Decay.hunger, now: now)
    }

    /// 1 = 开心，0 = 无聊
    func mood(at now: Date = Date()) -> Double {
        remaining(since: lastPlayedAt, span: Decay.mood, now: now)
    }

    /// 1 = 干净，0 = 脏
    func hygiene(at now: Date = Date()) -> Double {
        remaining(since: lastCleanedAt, span: Decay.hygiene, now: now)
    }

    /// 精力：刚玩过会累，休息一段就恢复。
    ///
    /// 注意这里的语义和上面三条相反 —— 时间越久精力越**足**。
    /// 所以宠物只会在「刚玩累」的那 40 分钟里打瞌睡，
    /// 而不是放置越久越困（那样反直觉）。
    func energy(at now: Date = Date()) -> Double {
        let rested = now.timeIntervalSince(lastPlayedAt)
        return clamp(rested / (40 * 60))
    }

    /// 综合健康度，给 UI 一个总览
    func wellbeing(at now: Date = Date()) -> Double {
        (satiety(at: now) + mood(at: now) + hygiene(at: now)) / 3
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: bornAt, to: Date()).day ?? 0
    }

    private func remaining(since date: Date, span: TimeInterval, now: Date) -> Double {
        guard span > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(date)
        return clamp(1 - elapsed / span)
    }

    private func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

/// 宠物当下最需要什么。用来驱动情绪气泡和场景行为。
enum PetNeed: String, CaseIterable {
    case hungry
    case bored
    case dirty
    case sleepy
    case content

    var emoji: String {
        switch self {
        case .hungry:  return "🍖"
        case .bored:   return "🎾"
        case .dirty:   return "🛁"
        case .sleepy:  return "💤"
        case .content: return "💗"
        }
    }

    var messageKey: String { "need.\(rawValue)" }
}

extension PetState {
    /// 取最紧急的需求。阈值 0.35 是手调的，之后可以按体感改。
    func dominantNeed(at now: Date = Date()) -> PetNeed {
        let candidates: [(PetNeed, Double)] = [
            (.hungry, satiety(at: now)),
            (.bored,  mood(at: now)),
            (.dirty,  hygiene(at: now))
        ]
        if let worst = candidates.min(by: { $0.1 < $1.1 }), worst.1 < 0.35 {
            return worst.0
        }
        if energy(at: now) < 0.2 { return .sleepy }
        return .content
    }
}
