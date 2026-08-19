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

        // App Store 海报专用场景。
        //
        // 与上面几个测试场景的区别在于它**为出镜服务**，不为断言服务：
        // - 名字用英文（商店页只做英文，海报里出现中文名会前后不一致）
        // - 家具摆齐（bowl/bed/plant），房间不至于空荡
        // - 状态给成「刚照顾过」而非快饿了 —— 海报要展示健康的宠物，
        //   满格的需求条比红色警告好看
        // - 钱给够，商店页不会满屏「买不起」的暗色条目
        case "poster":
            write(pets: [pet(.cat, color: 0, name: "Mochi", daysOld: 9, awake: true),
                         pet(.dog, color: 1, name: "Pixel", daysOld: 30, awake: true)],
                  coins: 12800, breeds: ["cat", "dog"], colors: [0, 1],
                  // **不放床。** 床是全场最宽的家具，横跨近半个房间，
                  // 宠物又爱在中段游走 —— 试了 0.55/0.62/0.80/0.86 四个
                  // 位置，每次抓图都有一只被它压住或站在上面。
                  // 碗和盆栽窄，靠边放就不碍事。
                  furniture: ["bowl", "plant"],
                  // 三件家具**拉开距离**摆，别互相压。
                  // 上一版把碗放 0.30/0.22、床放 0.55/0.55，结果床的
                  // 近端和碗几乎贴在一起 —— 截图里看着像「一只宠物
                  // 躺在碗边」，我差点当成作息 bug 去查。
                  // （真相是读 debugLayoutSnapshot 得到的：两只宠物都是
                  // idle，压根没有 sleeping。教训还是那条 —— 位置的事
                  // 问场景，别看像素猜。）
                  // 家具全部**靠两侧墙边**摆，把地面中段让宠物。
                  // 上一版床在 0.60/0.62（正中偏右），宠物爱在那片区域
                  // 游走，结果每次抓图都是「两只被床挡住下半身」。
                  // 家具靠边后，中段空出来，宠物无论走到哪都完整露出。
                  // xRatio 是家具**中心**位置。床是全场最宽的家具，
                  // 中心放 0.80 时右半边仍会被画面裁掉（0.86 更惨）。
                  // 所以床往里收到 0.62，盆栽（窄）才留在 0.85。
                  slots: [("bowl", 0.15, 0.20),
                          ("plant", 0.85, 0.26)],
                  // 已达成的标为已领 —— 不弹横幅，但成就页仍有未解锁项。
                  claimMet: true,
                  in: dir)

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
                           satiety: Double = 1.0,
                           awake: Bool = false) -> PetState {
        var p = PetState(breedID: breed.id, colorIndex: color, name: name)
        let now = Date()
        p.bornAt = now.addingTimeInterval(-Double(daysOld) * 86400)
        // 成年饱食周期 8h：satiety=1 → 刚喂过，0.2 → 6.4h 前喂的
        p.lastFedAt = now.addingTimeInterval(-(1 - satiety) * 8 * 3600)
        p.lastPlayedAt = now
        p.lastCleanedAt = now
        p.lastSeenAt = now
        // 深夜时段（23:00–06:59）宠物默认犯困、播睡姿（见 PetState.isDrowsy）。
        // 海报要清醒的宠物，而截图往往就是在深夜跑的 —— 用 awakeUntil
        // 顶掉作息判定，比改系统时钟可靠。
        if awake { p.awakeUntil = now.addingTimeInterval(3600) }
        return p
    }

    private static func write(pets: [PetState], coins: Int,
                              breeds: Set<String>, colors: Set<Int>,
                              furniture: Set<String>,
                              slots: [(String, Double, Double)],
                              claimMet: Bool = false,
                              in dir: URL) {
        var w = PetWallet()
        w.debugSetCoins(coins)
        w.ownedBreeds = breeds
        w.triedColors = colors
        w.ownedFurniture = furniture
        w.hasCompletedOnboarding = true
        w.selectedPetID = pets.first?.id

        // `claimMet`：把**当前已达成**的成就标记为已领。
        //
        // 目的是别让成就横幅在启动瞬间弹出来盖住画面（海报里出现
        // 「+80 coins」既遮构图，也算促销信息）。
        //
        // ⚠️ 两个更笨的做法都试过：
        // - 手写 id 清单 → 必漏。成就分 6 组，给两个品种就触发
        //   breed_2/pets_2，给一堆钱又触发经济类。
        // - `AchievementRule.all` 全量领 → 成就页变成 29/29 全解锁，
        //   养成感没了，而且满屏金币数字。
        // 正解是拿真实条件实算：达成的标已领（不弹），没达成的留着
        // （成就页仍显示进度）。将来加成就也不用改这里。
        if claimMet {
            w.claimedRewards = Set(
                AchievementRule.all
                    .filter { rule in pets.contains { rule.condition($0, w) } }
                    .map(\.id)
            )
        }

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
