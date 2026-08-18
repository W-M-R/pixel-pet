#if DEBUG
import Foundation

/// UI 测试的场景预置。
///
/// ## 为什么需要它
///
/// 深层场景（有碗、多宠、有钱）靠点击玩到那一步既慢又脆 ——
/// 要攒 800 买碗、攒 4000 买第二只，中间任何一步 UI 变了测试就断。
///
/// `tools/inject_save.py` 能直接写存档，但那是**宿主机上的脚本**，
/// XCUITest 跑在模拟器里，碰不到宿主机的文件系统。所以让 app 自己
/// 认启动参数：`-uitest-scene bowl-two-pets` 启动时就把存档铺好。
///
/// ## 为什么只在 DEBUG
///
/// 和调试面板同一个原则（见 `project.yml` 的
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS`）：Release 产物里
/// 连符号都不存在。**这点很重要** —— 这段代码会清空玩家存档，
/// 绝不能有任何路径让正式版走到这里。
enum UITestScene {

    /// 从启动参数里读场景名并铺好存档。
    ///
    /// 必须在 `PetStore` 初始化**之前**调用 —— store 在 init 里就读盘了，
    /// 晚一步就来不及了。
    static func applyIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitest") else { return }

        let dir = FilePersistence.defaultDirectory
        // 每次都从干净状态开始 —— 残留存档会让「全新引导」这类
        // 测试莫名跳过引导页
        reset(in: dir)

        guard let i = args.firstIndex(of: "-uitest-scene"),
              i + 1 < args.count else { return }   // 没给场景 = 全新存档
        apply(args[i + 1], in: dir)
    }

    private static func reset(in dir: URL) {
        for name in ["pet.json", "wallet.json", "room.json"] {
            try? FileManager.default.removeItem(
                at: dir.appendingPathComponent(name))
        }
    }

    private static func apply(_ scene: String, in dir: URL) {
        switch scene {
        case "bowl-two-pets":
            write(pets: [pet(.cat, color: 0, name: "喵喵", satiety: 0.2),
                         pet(.dog, color: 1, name: "旺财", satiety: 0.2)],
                  coins: 9000, breeds: ["cat", "dog"], colors: [0, 1],
                  furniture: ["bowl"],
                  // 碗故意不用默认位置 —— 这样「宠物站位跟着碗算」
                  // 这件事才真的被验证到
                  slots: [("bowl", 0.35, 0.30)],
                  in: dir)

        case "bowl-three-pets":
            write(pets: [pet(.cat, color: 0, name: "A", satiety: 0.15),
                         pet(.dog, color: 1, name: "B", satiety: 0.15),
                         pet(.cat, color: 2, name: "C", satiety: 0.15)],
                  coins: 9000, breeds: ["cat", "dog"], colors: [0, 1, 2],
                  furniture: ["bowl"],
                  slots: [("bowl", 0.50, 0.35)],
                  in: dir)

        case "no-bowl":
            // 没买碗 —— 验证回退到「脚边放临时食盆」的老行为
            write(pets: [pet(.cat, color: 0, name: "喵喵", satiety: 0.2)],
                  coins: 500, breeds: ["cat"], colors: [0],
                  furniture: [], slots: [], in: dir)

        case "rich":
            write(pets: [pet(.cat, color: 0, name: "土豪")],
                  coins: 99999, breeds: ["cat"], colors: [0],
                  furniture: [], slots: [], in: dir)

        default:
            NSLog("[PixelPet] 未知的 UI 测试场景：%@", scene)
        }
    }

    // MARK: - 造数据

    /// 造一只宠物。
    ///
    /// 时间戳是**倒推**的：这个 app 的状态全由「距上次喂食多久」算出来
    /// （见 `PetState` 的设计），不存数值。所以要造「快饿了的猫」
    /// 就把 `lastFedAt` 往前挪，而不是写一个 satiety 字段 —— 那个字段不存在。
    private static func pet(_ breed: PetBreed, color: Int, name: String,
                           daysOld: Int = 30,
                           satiety: Double = 1.0) -> PetState {
        var p = PetState(breedID: breed.id, colorIndex: color, name: name)
        let now = Date()
        p.bornAt = now.addingTimeInterval(-Double(daysOld) * 86400)
        // 成年饱食周期 8h：satiety=1 → 刚喂过，0.2 → 6.4h 前喂的
        p.lastFedAt = now.addingTimeInterval(-(1 - satiety) * 8 * 3600)
        p.lastPlayedAt = now
        p.lastCleanedAt = now
        p.lastSeenAt = now
        return p
    }

    private static func write(pets: [PetState], coins: Int,
                              breeds: Set<String>, colors: Set<Int>,
                              furniture: Set<String>,
                              slots: [(String, Double, Double)],
                              in dir: URL) {
        var w = PetWallet()
        w.debugSetCoins(coins)
        w.ownedBreeds = breeds
        w.triedColors = colors
        w.ownedFurniture = furniture
        w.hasCompletedOnboarding = true
        w.selectedPetID = pets.first?.id

        let store = FilePersistence(directory: dir)
        store.save(pets: pets)
        store.save(wallet: w)

        if !slots.isEmpty {
            let layout = RoomLayout(slots: slots.map {
                RoomLayout.Slot(id: $0.0, xRatio: $0.1, depth: $0.2)
            })
            if let data = try? JSONEncoder().encode(layout) {
                try? data.write(to: dir.appendingPathComponent("room.json"))
            }
        }
    }
}
#endif
