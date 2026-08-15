import SwiftUI

/// UI 像素图标。
///
/// **为什么自绘而不用 emoji**：Apple emoji 是高分辨率渐变矢量风，
/// 紧贴 4 倍放大的像素猫时会把像素感彻底压掉，而且不同 iOS 版本字形会变。
///
/// **为什么不用 emotes.png**：那套（Tomcat94, CC0）只有抽象符号
/// （心/音符/水滴/感叹号），没有食物、球、浴缸这类具体道具 ——
/// 见 `RoomSpriteSheet.Emote` 的注释。
///
/// 所以由 `tools/make_ui_icons.py` 自绘，形状原创、配色取自 `Pixel` 色板，
/// 零授权负担。
enum PixelIcon: Int, CaseIterable {
    case meat = 0       // 喂食
    case ball           // 玩耍
    case bath           // 洗澡
    case coin           // 金币
    case scraps         // 剩饭
    case kibble         // 普通粮
    case can            // 罐头
    case fish           // 小鱼干
    case heart          // 心（陪伴）
    case star           // 星（成就）
    case sleep          // zZ（睡眠）

    /// sheet 里的图标边长（源像素）
    static let cell: CGFloat = 16
    static let sheetName = "icons"

    /// 食物档位 → 图标
    static func forFood(_ id: String) -> PixelIcon {
        switch id {
        case "kibble":     return .kibble
        case "can":        return .can
        case "dried_fish": return .fish
        default:           return .scraps
        }
    }

    /// 宠物需求 → 图标
    static func forNeed(_ need: PetNeed) -> PixelIcon {
        switch need {
        case .hungry:  return .meat
        case .bored:   return .ball
        case .dirty:   return .bath
        case .sleepy:  return .sleep
        case .content: return .heart
        }
    }
}

/// 图标 sheet 的加载与切分。
///
/// `Assets/` 是按 raw resources 拷进包的（见 project.yml），不是 asset catalog，
/// 所以 `Image("icons")` 找不到 —— 必须走 Bundle + UIImage。
private enum IconSheet {
    /// 切好的单个图标，按 rawValue 索引。整张图只解码一次。
    static let images: [Image] = {
        guard let url = Bundle.main.url(forResource: PixelIcon.sheetName,
                                        withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let full = UIImage(data: data),
              let cg = full.cgImage else { return [] }

        let cell = Int(PixelIcon.cell)
        return PixelIcon.allCases.map { icon in
            let rect = CGRect(x: icon.rawValue * cell, y: 0,
                              width: cell, height: cell)
            guard let cropped = cg.cropping(to: rect) else { return Image(uiImage: full) }
            return Image(uiImage: UIImage(cgImage: cropped))
        }
    }()
}

/// 显示一个像素图标。
///
/// 尺寸应为 16 的整数倍（16/32/48…），否则会出现半像素边。
struct PixelIconView: View {
    let icon: PixelIcon
    /// 显示边长（pt）
    var size: CGFloat = 32

    var body: some View {
        let imgs = IconSheet.images
        Group {
            if icon.rawValue < imgs.count {
                imgs[icon.rawValue]
                    .interpolation(.none)      // 关键：禁用插值，保持硬边
                    .resizable()
            } else {
                // sheet 缺失时留空位，不崩
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(PixelIcon.allCases, id: \.rawValue) { i in
            HStack {
                PixelIconView(icon: i, size: 32)
                Text(verbatim: "\(i)")
                    .font(Pixel.mono(Pixel.labelSize))
            }
        }
    }
    .padding()
    .background(Pixel.panel.color)
}
