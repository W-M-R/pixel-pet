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

    /// 默认布局。家具靠墙贴地，中间留出宠物活动区。
    static var `default`: RoomLayout {
        RoomLayout(slots: [
            Slot(id: "rug",        xRatio: 0.50, yOffset: -16, scaleMul: 1.1,  z: 0),
            Slot(id: "bed",        xRatio: 0.15, yOffset: 30,  scaleMul: 0.85, z: 1),
            Slot(id: "nightstand", xRatio: 0.33, yOffset: 14,  scaleMul: 0.85, z: 1),
            Slot(id: "bookshelf",  xRatio: 0.88, yOffset: 34,  scaleMul: 0.85, z: 1),
            Slot(id: "plant",      xRatio: 0.71, yOffset: 14,  scaleMul: 0.85, z: 1)
        ])
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
