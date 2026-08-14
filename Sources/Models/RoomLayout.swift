import Foundation
import CoreGraphics

/// 房间布局：哪件家具放在哪。
///
/// 位置存成**屏宽比例**而不是绝对点数，这样换机型、转屏都不会错位。
/// y 存成相对地面线的偏移（点数），因为家具是贴地的，
/// 地面线本身由场景高度算出。
struct RoomLayout: Codable, Equatable {

    struct Slot: Codable, Equatable, Identifiable {
        var id: String          // Furniture 的 rawValue
        var xRatio: Double
        var yOffset: Double
        var scaleMul: Double
        var z: Double
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

/// 房间布局存档。和 PetStore 分开，因为布局改动频率高很多。
final class RoomStore {
    private let fileURL: URL
    private(set) var layout: RoomLayout

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("room.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(RoomLayout.self, from: data) {
            layout = decoded
        } else {
            layout = .default
        }
    }

    func move(id: String, toXRatio ratio: Double) {
        guard let idx = layout.slots.firstIndex(where: { $0.id == id }) else { return }
        // 留边距，别让家具跑出屏幕
        layout.slots[idx].xRatio = min(0.94, max(0.06, ratio))
        persist()
    }

    func reset() {
        layout = .default
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
