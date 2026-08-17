import Foundation
import CoreGraphics

/// 房间布局：哪件家具放在哪。
///
/// 位置存成**屏宽比例**而不是绝对点数，这样换机型、转屏都不会错位。
/// y 存成相对地面线的偏移（点数），因为家具是贴地的，
/// 地面线本身由场景高度算出。
struct RoomLayout: Codable, Equatable {

    struct Slot: Equatable, Identifiable {
        var id: String          // FurnitureItem.id
        var xRatio: Double

        /// 纵向位置，用**地板 depth**（0 = 最近/最下，1 = 最远/贴墙）。
        ///
        /// 不用绝对点数：地板范围随机型和安全区变化，
        /// 存点数会让家具在不同设备上跑到地板外面。
        /// depth 是地板自己的坐标系，换设备自动适配。
        var depth: Double = 0.5

        /// 旧字段。曾经家具只能横向拖，纵向靠这个手调偏移。
        /// 保留是为了让旧存档能解码，新代码不再读它。
        var yOffset: Double = 0

        var scaleMul: Double
        var z: Double

        init(id: String, xRatio: Double, depth: Double = 0.5,
             yOffset: Double = 0, scaleMul: Double = 1, z: Double = 7) {
            self.id = id
            self.xRatio = xRatio
            self.depth = depth
            self.yOffset = yOffset
            self.scaleMul = scaleMul
            self.z = z
        }
    }

    var slots: [Slot]

    /// 默认布局：空。
    ///
    /// 曾经用 OGA 的 Home Objects 包摆了床/书架/盆栽，但那套素材是
    /// **俯视视角**（能看到整个床面和枕头），而 LPC 宠物是**纯侧视**。
    /// 两种视角放在一起怎么摆都别扭，不是缩放或位置能修的问题。
    ///
    /// 现在房间的墙/地板/窗/挂画全部手绘，视角统一在侧视，
    /// 家具留空。要加家具的话必须是侧视素材，否则会重新引入这个问题。
    static var `default`: RoomLayout {
        RoomLayout(slots: [])
    }
}

extension RoomLayout.Slot: Codable {

    private enum CodingKeys: String, CodingKey {
        case id, xRatio, depth, yOffset, scaleMul, z
    }

    /// 手写解码。
    ///
    /// ⚠️ **属性默认值救不了缺失的 key。** Swift 的合成 `init(from:)`
    /// 对有默认值的属性**仍然要求 key 存在**，缺了就抛 `keyNotFound`。
    /// 单独验证过：
    /// ```
    /// struct S: Codable { var depth: Double = 0.5; ... }
    /// 喂缺 depth 的 JSON → keyNotFound("depth")
    /// ```
    ///
    /// 这曾经是个真 bug：`depth` 是后加的字段，注释写着「旧字段保留是为了
    /// 让旧存档能解码」，但旧格式（只有 id/xRatio/yOffset/scaleMul/z）
    /// 会整份解码失败 —— 然后 `RoomStore` 用 `try?` 静默退回 `.default`，
    /// **玩家精心摆的房间布局全部重置且有任何提示**。
    ///
    /// 所以除 `id` 外每个字段都用 `decodeIfPresent`。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        xRatio = try c.decodeIfPresent(Double.self, forKey: .xRatio) ?? 0.5
        yOffset = try c.decodeIfPresent(Double.self, forKey: .yOffset) ?? 0
        scaleMul = try c.decodeIfPresent(Double.self, forKey: .scaleMul) ?? 1
        z = try c.decodeIfPresent(Double.self, forKey: .z) ?? 7
        // 旧存档没有 depth（那时家具只能横向拖）。给中段，玩家再拖即可 ——
        // 从 yOffset 反推没有意义：它是相对墙脚线的点数偏移，
        // 而 depth 是地板的归一化坐标，参照物不同。
        depth = try c.decodeIfPresent(Double.self, forKey: .depth) ?? 0.5
    }
}

/// 房间布局存档。和 PetStore 分开，因为布局改动频率高很多。
final class RoomStore {
    private let fileURL: URL
    private(set) var layout: RoomLayout

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory,
                                 in: .userDomainMask)[0]
    }

    /// - Parameter directory: 存档目录。**测试要能注入** ——
    ///   原来硬编码 `applicationSupportDirectory`，导致整个类不可测，
    ///   于是 `move`/`place`/`sync` 和 `Slot` 的迁移全都没有测试，
    ///   `depth` 迁移失效那个 bug 就是这么漏出去的。
    ///   `FilePersistence` 早就有这个参数，这里一直没跟上。
    init(directory: URL = RoomStore.defaultDirectory) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("room.json")

        guard let data = try? Data(contentsOf: fileURL) else {
            layout = .default            // 没有文件是正常的首次启动
            return
        }
        do {
            layout = try JSONDecoder().decode(RoomLayout.self, from: data)
        } catch {
            // **文件存在但解码失败要吼出来。**
            // 原来是 `try?` 静默退默认，玩家摆好的布局无声重置，
            // 排查时完全看不到线索。`PetPersistence` 早就吸取了这个教训。
            assertionFailure("room.json 解码失败，布局将重置：\(error)")
            NSLog("[PixelPet] room.json 解码失败：%@", "\(error)")
            layout = .default
        }
    }

    /// 移动家具。
    ///
    /// **二维自由移动** —— 只要落在地板上。
    /// 曾经只能横向拖（`toXRatio`），纵向得改代码里的 yOffset。
    func move(id: String, toXRatio ratio: Double, depth: Double) {
        guard let idx = layout.slots.firstIndex(where: { $0.id == id }) else { return }
        // 留边距，别让家具跑出屏幕
        layout.slots[idx].xRatio = min(0.94, max(0.06, ratio))
        // depth 夹在地板范围内。留一点余量：
        // 0 会贴到屏幕最下缘（压住按钮），1 会插进墙里。
        layout.slots[idx].depth = min(0.92, max(0.08, depth))
        persist()
    }

    /// 买了家具后摆进房间。
    ///
    /// 默认位置按已有件数错开 —— 全摆同一个 x 会叠在一起，
    /// 而玩家得先拖开才看得清买了什么。
    func place(_ item: FurnitureItem) {
        guard appendSlot(item) else { return }
        persist()
    }

    /// 只改内存，不写盘。批量操作用，最后统一 persist 一次。
    @discardableResult
    private func appendSlot(_ item: FurnitureItem) -> Bool {
        guard !layout.slots.contains(where: { $0.id == item.id }) else { return false }
        // 0.22 / 0.42 / 0.62 / 0.82 依次排开
        let ratio = min(0.82, 0.22 + Double(layout.slots.count) * 0.20)
        // 纵向也错开一点，免得新买的家具正好压在旧的上面
        let depth = 0.45 + Double(layout.slots.count % 3) * 0.12
        layout.slots.append(RoomLayout.Slot(
            id: item.id, xRatio: ratio, depth: depth,
            // 碗的 z 比宠物(10)高一点 —— 宠物凑过来吃时碗沿仍可见。
            // 32px 宽的碗会被两侧约 24px 的身体夹住，压在下面就看不到了。
            // 装饰品放宠物之下，宠物走到前面能挡住它，那是对的。
            scaleMul: 1, z: item.isBowl ? 10.5 : 7))
        return true
    }

    /// 把已购家具同步进布局。
    ///
    /// 幂等 —— 每次启动都调，补上「买过但布局里没有」的
    /// （比如从旧存档升级过来，或 room.json 被重置过）。
    func sync(owned: Set<String>) {
        var changed = false
        for id in owned.sorted() {
            guard let item = FurnitureItem.byID(id) else { continue }
            // 用不写盘的版本 —— 原来每件家具各触发一次全量写盘
            if appendSlot(item) { changed = true }
        }
        // 反向清理：布局里有但已经不拥有的（正常不会发生，防脏数据）
        let before = layout.slots.count
        layout.slots.removeAll { !owned.contains($0.id) }
        if layout.slots.count != before { changed = true }
        if changed { persist() }
    }

    /// 某件家具当前的 xRatio。找不到返回 nil。
    func xRatio(of id: String) -> Double? {
        layout.slots.first { $0.id == id }?.xRatio
    }

    func reset() {
        layout = .default
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(layout)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // **写盘失败不能静默吞掉。**
            // 磁盘满或沙盒异常时，玩家整个 session 的布局会在重启后消失，
            // 而运行期间 UI 一切正常（内存状态是对的）—— 最难查的一类问题。
            assertionFailure("room.json 写入失败：\(error)")
            NSLog("[PixelPet] room.json 写入失败：%@", "\(error)")
        }
    }
}
