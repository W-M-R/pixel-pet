import Foundation
import Observation

/// 宠物存档。用 JSON 存文件，不用 UserDefaults——将来要加多只宠物、
/// 要导出备份都方便。
@Observable
final class PetStore {

    private(set) var pet: PetState
    private let fileURL: URL

    /// 驱动 UI 定时刷新的心跳。状态本身是按时间戳算的，
    /// 但 SwiftUI 需要一个变化信号才会重绘。
    private(set) var tick: Date = Date()
    private var timer: Timer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pet.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PetState.self, from: data) {
            self.pet = decoded
        } else {
            // 首次启动：新宠物必须立刻写盘。
            // 之前漏了这一步，导致 bornAt 每次启动都被重置 ——
            // 宠物永远显示「相伴第 0 天」，存档形同不存在。
            self.pet = PetState(species: .cat, colorIndex: 0, name: "")
            if let data = try? JSONEncoder().encode(self.pet) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        startHeartbeat()
    }

    deinit { timer?.invalidate() }

    private func startHeartbeat() {
        // 10 秒一次足够。数值变化本来就慢，刷太勤只是白耗电。
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.tick = Date()
        }
    }

    /// 从后台回到前台时立刻刷一次，不等下一个心跳。
    func refresh() { tick = Date() }

    // MARK: - 互动

    func feed() {
        extendAwakeIfNeeded()
        pet.lastFedAt = Date()
        persist()
    }

    func play() {
        extendAwakeIfNeeded()
        pet.lastPlayedAt = Date()
        persist()
    }

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

    func clean() {
        extendAwakeIfNeeded()
        pet.lastCleanedAt = Date()
        persist()
    }

    func rename(_ newName: String) {
        pet.name = newName
        persist()
    }

    func choose(species: PetSpecies, colorIndex: Int) {
        pet.species = species
        pet.colorIndex = colorIndex
        persist()
    }

    /// 调试用：把时间戳往前推，模拟放置一段时间后的状态。
    /// 这是验证「读时算」是否正确的最快方式。
    func debugAge(by seconds: TimeInterval) {
        pet.lastFedAt = pet.lastFedAt.addingTimeInterval(-seconds)
        pet.lastPlayedAt = pet.lastPlayedAt.addingTimeInterval(-seconds)
        pet.lastCleanedAt = pet.lastCleanedAt.addingTimeInterval(-seconds)
        persist()
        refresh()
    }

    func resetAll() {
        pet = PetState(species: pet.species, colorIndex: pet.colorIndex, name: pet.name)
        persist()
        refresh()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pet) else { return }
        try? data.write(to: fileURL, options: .atomic)
        tick = Date()
    }
}
