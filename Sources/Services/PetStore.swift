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
            self.pet = PetState(species: .cat, colorIndex: 0, name: "")
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
        pet.lastFedAt = Date()
        persist()
    }

    func play() {
        pet.lastPlayedAt = Date()
        persist()
    }

    func clean() {
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
