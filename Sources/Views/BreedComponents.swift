import SwiftUI

/// 品种立绘。取侧视站立帧，按整数倍放大。
///
/// **从 `OnboardingView` 抽出来的原因**：`ShopView` 也用它 ——
/// 它是共享组件，不属于开局流程。放在那边会让「商店引用开局界面的文件」。
///
/// 用真实精灵而非抽象图标 —— 选宠物时最该看到的就是「它长什么样」。
struct BreedPortrait: View {
    let breed: PetBreed
    let colorIndex: Int

    /// 显示边长（pt）。源帧是 32×32，取 32 的整数倍保证像素完美。
    ///
    /// ⚠️ 必须显式给尺寸。曾经用 `scaledToFit()` 配只给 height 的 frame，
    /// 图片会塌成 0 宽，卡片全空。
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let img = Self.image(breed: breed, colorIndex: colorIndex) {
                img.interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                // sheet 缺失时不崩，留空位
                Color.clear.frame(width: size, height: size)
            }
        }
    }

    /// 从 sheet 里切出站立帧。
    ///
    /// 走 `Bundle` + `UIImage` 而非 `Image(name)` —— `Assets/` 是
    /// raw resources 不是 asset catalog（见 `PixelIcon` 的同类注释）。
    private static var cache: [String: Image] = [:]

    private static func image(breed: PetBreed, colorIndex: Int) -> Image? {
        let key = "\(breed.id)|\(colorIndex)"
        if let hit = cache[key] { return hit }

        guard let url = Bundle.main.url(forResource: breed.sheetName,
                                        withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let full = UIImage(data: data),
              let cg = full.cgImage else { return nil }

        // 布局从品种读 —— 不同素材的格子尺寸/毛色列数可能不同
        let layout = breed.layout
        let cell = Int(layout.cell)
        // 侧视朝右行(r0)的第 0 列，按毛色偏移
        let color = min(max(0, colorIndex), layout.colorCount - 1)
        let x = color * layout.columnsPerColor * cell
        let rect = CGRect(x: x, y: 0, width: cell, height: cell)
        guard let cropped = cg.cropping(to: rect) else { return nil }

        let img = Image(uiImage: UIImage(cgImage: cropped))
        cache[key] = img
        return img
    }
}

/// 品种属性对比面板。
///
/// **共享组件**：开局选宠物时要看，商店买之前也要看 ——
/// 商店原来把三条属性压成一行文字（`shop.stats`），信息密度太低。
///
/// 三条都用「相对基准」表述而非绝对数值 —— 玩家不需要知道
/// 「心情周期 14 小时」，只需要知道「比一般的更黏人」。
struct BreedStatPanel: View {
    let breed: PetBreed
    /// 紧凑模式：商店列表里用，去掉容器背景
    var compact: Bool = false

    var body: some View {
        VStack(spacing: Pixel.u(1.5)) {
            statRow(labelKey: "stat.mood",
                    icon: .ball,
                    // 周期越短越黏人 → 反转，让「条越长 = 越需要陪」
                    value: 1 - Self.normalized(breed.moodCycleHours,
                                               lo: 12, hi: 24),
                    detail: String(format: L("onboard.stat.mood.detail"),
                                   Int(breed.moodCycleHours)))
            statRow(labelKey: "stat.hygiene",
                    icon: .bath,
                    // 同理反转：条越长 = 越需要洗
                    value: 1 - Self.normalized(breed.hygieneCycleHours,
                                               lo: 48, hi: 96),
                    detail: String(format: L("onboard.stat.hygiene.detail"),
                                   Int(breed.hygieneCycleHours / 24)))
            statRow(labelKey: "onboard.stat.gold",
                    icon: .coin,
                    // 以 1.00 为中点（0.90~1.10 映射到 0~1），
                    // 这样「均衡型」显示在正中间而不是靠左
                    value: Self.normalized(breed.goldMultiplier,
                                           lo: 0.90, hi: 1.10),
                    detail: String(format: L("onboard.stat.gold.detail"),
                                   Int((breed.goldMultiplier - 1) * 100)))
        }
        .padding(compact ? 0 : Pixel.u(2.5))
        .background {
            if !compact {
                PixelPanel(fill: Pixel.panelDark,
                           lite: Pixel.panel,
                           dark: Pixel.panelDark)
            }
        }
    }

    private func statRow(labelKey: String,
                         icon: PixelIcon,
                         value: Double,
                         detail: String) -> some View {
        HStack(spacing: Pixel.u(2)) {
            PixelIconView(icon: icon, size: Pixel.u(4))
            Text(verbatim: L(labelKey))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
                .frame(width: Pixel.u(14), alignment: .leading)
            PixelBar(value: value, tint: Pixel.satiety, slots: 8)
                .frame(width: Pixel.u(20))
            Text(verbatim: detail)
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.text.color)
        }
    }

    /// 把属性值映射到 0...1，用于画格子条
    static func normalized(_ v: Double, lo: Double, hi: Double) -> Double {
        guard hi > lo else { return 0.5 }
        return min(1, max(0, (v - lo) / (hi - lo)))
    }
}

/// 毛色选择器。开局和设置页都用。
struct CoatPicker: View {
    let breed: PetBreed
    @Binding var colorIndex: Int

    var body: some View {
        HStack(spacing: Pixel.u(2)) {
            ForEach(0..<breed.colorCount, id: \.self) { i in
                Button { colorIndex = i } label: {
                    ZStack {
                        Rectangle().fill(Pixel.slotEmpty.color)
                        if colorIndex == i {
                            // 选中框用像素描边，不用圆角
                            Rectangle()
                                .strokeBorder(Pixel.coin.color,
                                              lineWidth: Pixel.u(1))
                        }
                        Text(verbatim: "\(i + 1)")
                            .font(Pixel.mono(Pixel.bodySize, .medium))
                            .foregroundStyle(colorIndex == i
                                             ? Pixel.coin.color
                                             : Pixel.textDim.color)
                    }
                    .frame(height: Pixel.u(9))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 家具预览图。
///
/// 和 `BreedPortrait` 同样的做法：`Assets/` 是 raw resources 不是
/// asset catalog，所以 `Image("furniture")` 找不到 ——
/// 必须走 `Bundle` + `UIImage` + `cgImage.cropping`。
struct FurniturePreview: View {
    let item: FurnitureItem
    let height: CGFloat

    /// 按 id 缓存 —— 商店列表会反复重建 View
    private static var cache: [String: Image] = [:]

    var body: some View {
        if let img = Self.crop(item) {
            img.interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: height * CGFloat(item.cellWidth), height: height)
        } else {
            // 取不到就留空位，不崩也不显示占位符 ——
            // 占位符比空白更显眼，而这是「素材缺失」的开发期问题
            Color.clear
                .frame(width: height * CGFloat(item.cellWidth), height: height)
        }
    }

    private static func crop(_ item: FurnitureItem) -> Image? {
        if let hit = cache[item.id] { return hit }

        guard let url = Bundle.main.url(forResource: "furniture",
                                        withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let full = UIImage(data: data),
              let cg = full.cgImage else { return nil }

        let cell = Int(FurnitureItem.cell)
        let slot = cell * 2                      // 每件占 2 格宽的位置
        let rect = CGRect(x: item.sheetIndex * slot, y: 0,
                          width: cell * item.cellWidth, height: cell)
        guard let cropped = cg.cropping(to: rect) else { return nil }

        let img = Image(uiImage: UIImage(cgImage: cropped))
        cache[item.id] = img
        return img
    }
}
