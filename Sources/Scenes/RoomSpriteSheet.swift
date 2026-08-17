import SpriteKit

/// 房间素材（家具 + 情绪气泡）的切图规则。
/// 和 PetSpriteSheet 分开，因为这两张 sheet 的网格规则完全不同。
enum RoomSpriteSheet {

    // MARK: - 家具：Home Objects by Jannax (CC0)

    /// 192×192。作者说「already set up in 32x32 spaces」，但实测**很多家具跨多格**
    /// （床占 2×2、沙发占 2×1、书架占 1×2），按单格切会切出半截家具。
    /// 所以这里用像素矩形而不是格子索引，尺寸是放大后逐个看出来的。
    /// 矩形是逐个放大核对过的（见 ASSET-PROVENANCE/home-objects）。
    /// 注意 (96,32) 和 (128,32) 两格是空的，别往那儿取。
    enum Furniture: String, CaseIterable {
        case bed          // 双人床，2×2
        case nightstand   // 床头柜
        case sofa         // 沙发，2×1
        case bookshelf    // 书架，1×2
        case plant        // 盆栽
        case rug          // 地毯，2×2

        /// 源图上的像素矩形（左上原点，与看图一致）
        var rect: CGRect {
            switch self {
            case .bed:        return CGRect(x: 0,   y: 0,   width: 64, height: 64)
            case .bookshelf:  return CGRect(x: 64,  y: 0,   width: 32, height: 64)
            case .sofa:       return CGRect(x: 96,  y: 0,   width: 64, height: 32)
            case .nightstand: return CGRect(x: 160, y: 0,   width: 32, height: 32)
            case .plant:      return CGRect(x: 160, y: 32,  width: 32, height: 32)
            case .rug:        return CGRect(x: 0,   y: 128, width: 64, height: 64)
            }
        }
    }

    /// 从自绘的侧视家具 sheet 取一件。
    ///
    /// 布局：每件占 2 格宽的位置（64px），1 格宽的家具画在左半边。
    /// 索引与 `tools/make_furniture.py` 的 `ORDER` 一一对应，
    /// 也与 `FurnitureItem.sheetIndex` 一致（由测试锁住）。
    static func furnitureTexture(from sheet: SKTexture,
                                 index: Int,
                                 cellWidth: Int) -> SKTexture? {
        let cell = FurnitureItem.cell
        let slot = cell * 2                     // 每件的格位宽度
        let sheetW = sheet.size().width
        let sheetH = sheet.size().height
        guard sheetW > 0, sheetH > 0 else { return nil }

        let x = CGFloat(index) * slot
        let w = cell * CGFloat(cellWidth)
        guard x + w <= sheetW + 0.5 else { return nil }

        let rect = CGRect(x: x / sheetW, y: 0,
                          width: w / sheetW, height: cell / sheetH)
        let tex = SKTexture(rect: rect, in: sheet)
        tex.filteringMode = .nearest
        return tex
    }

    /// 按像素矩形取图。左上原点 → SpriteKit 左下原点的翻转在这里统一处理。
    static func furnitureTexture(from sheet: SKTexture, _ item: Furniture) -> SKTexture {
        let sheetW = sheet.size().width
        let sheetH = sheet.size().height
        guard sheetW > 0, sheetH > 0 else { return sheet }

        let r = item.rect
        let yBottom = sheetH - r.origin.y - r.height
        let rect = CGRect(x: r.origin.x / sheetW,
                          y: yBottom / sheetH,
                          width: r.width / sheetW,
                          height: r.height / sheetH)
        let tex = SKTexture(rect: rect, in: sheet)
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: - 情绪气泡：16x16 Emotes by Tomcat94 (CC0)

    /// 这张图不是整数倍网格 —— 实测 140×120，靠扫空行/空列反推出：
    /// 图标 12×12，间距 20px，左边距 4，上边距 3，共 7 列 × 6 行。
    /// 直接按 16×16 或 20×20 切都会错位。
    enum EmoteGrid {
        static let iconSize: CGFloat = 12
        static let stride: CGFloat = 20
        static let insetX: CGFloat = 4
        static let insetY: CGFloat = 3
        static let columns = 7
        static let rows = 6
    }

    /// 情绪图标。坐标是放大整张网格逐个看出来的
    /// （见 ASSET-PROVENANCE/emotes/grid-map.md）。
    ///
    /// r0: ! ? … ♥ 心碎 ♪ 汗滴
    /// r1: zZ ✱ ↑ ↓ ✦ ☁ ☂
    /// r2: ✿ ☠ 💧 ⚡ ☀ ✚ ✖
    ///
    /// 包里没有食物/球/浴缸这类具体道具图标，所以喂食/玩耍/洗澡
    /// 只能用抽象符号代替（心/音符/水滴），或回退 emoji。
    enum Emote {
        case alert      // !
        case question   // ?
        case ellipsis   // …
        case heart      // ♥
        case heartbreak // 心碎
        case music      // ♪
        case sweat      // 汗滴
        case sleep      // zZ
        case droplet    // 💧

        var cell: (col: Int, row: Int) {
            switch self {
            case .alert:      return (0, 0)
            case .question:   return (1, 0)
            case .ellipsis:   return (2, 0)
            case .heart:      return (3, 0)
            case .heartbreak: return (4, 0)
            case .music:      return (5, 0)
            case .sweat:      return (6, 0)
            case .sleep:      return (0, 1)
            case .droplet:    return (2, 2)
            }
        }
    }

    static func emoteTexture(from sheet: SKTexture, _ emote: Emote) -> SKTexture? {
        let sheetW = sheet.size().width
        let sheetH = sheet.size().height
        guard sheetW > 0, sheetH > 0 else { return nil }

        typealias G = EmoteGrid
        let x = G.insetX + CGFloat(emote.cell.col) * G.stride
        let yTop = G.insetY + CGFloat(emote.cell.row) * G.stride
        // Y 翻转：从底部量起
        let yBottom = sheetH - yTop - G.iconSize
        guard x >= 0, yBottom >= 0,
              x + G.iconSize <= sheetW, yTop + G.iconSize <= sheetH else { return nil }

        let rect = CGRect(x: x / sheetW,
                          y: yBottom / sheetH,
                          width: G.iconSize / sheetW,
                          height: G.iconSize / sheetH)
        let tex = SKTexture(rect: rect, in: sheet)
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: - 加载

    /// 从自绘的 UI 图标 sheet（`Assets/ui/icons.png`）取一格。
    ///
    /// **为什么 Scenes 层要自己做这件事**：`PixelIcon` 住在 Views 层，
    /// 而 Scenes 不得引用 Views（见 tools/check_layers.sh）。
    /// 所以这里按索引取图，索引含义由 `PixelIcon` 的 case 顺序决定 ——
    /// 两处都由 `tools/make_ui_icons.py` 的 ORDER 定义，加图标只能追加到末尾。
    ///
    /// 用它替掉了喂食气泡原来的 🍖 emoji：emoji 字形随 iOS 版本变，
    /// 缺字体时还会渲染成问号。
    static func uiIconTexture(from sheet: SKTexture, index: Int) -> SKTexture? {
        let cell: CGFloat = 16
        let sheetW = sheet.size().width
        let sheetH = sheet.size().height
        guard sheetW > 0, sheetH > 0 else { return nil }
        let x = CGFloat(index) * cell
        guard x + cell <= sheetW + 0.5 else { return nil }
        let rect = CGRect(x: x / sheetW, y: 0,
                          width: cell / sheetW, height: cell / sheetH)
        let tex = SKTexture(rect: rect, in: sheet)
        tex.filteringMode = .nearest
        return tex
    }

    static func loadSheet(named name: String) -> SKTexture? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            let tex = SKTexture(image: image)
            tex.filteringMode = .nearest
            return tex
        }
        let tex = SKTexture(imageNamed: name)
        guard tex.size().width > 1 else { return nil }
        tex.filteringMode = .nearest
        return tex
    }
}

extension PetNeed {
    /// 映射到像素图标。`hungry` 在这套 emotes 里没有对应的食物图标，
    /// 返回 nil 让调用方回退到 emoji。
    var emote: RoomSpriteSheet.Emote? {
        switch self {
        case .hungry:  return nil
        case .bored:   return .ellipsis
        case .dirty:   return .droplet
        case .sleepy:  return .sleep
        case .content: return .heart
        }
    }
}
