import SwiftUI
import SpriteKit

/// 开局流程：选宠物 → 起名。
///
/// **为什么要有这个**：原来 app 一启动就直接给一只默认猫，
/// 玩家没有「这是我选的」这种归属感。而归属感是养成类留存的核心。
///
/// 两步而非一步：选宠物时要看属性对比（信息量大），起名要专注（输入）。
/// 挤在一屏会让两件事都做不好。
struct OnboardingView: View {
    let store: PetStore
    /// 完成后回调
    let onDone: () -> Void

    @State private var step: Step = .pickBreed
    @State private var breedID: String = PetBreed.cat.id
    @State private var colorIndex: Int = 0
    @State private var draftName: String = ""

    private enum Step { case pickBreed, name }

    private var breed: PetBreed { PetBreed.byID(breedID) }

    var body: some View {
        ZStack {
            Pixel.panel.color.ignoresSafeArea()

            VStack(spacing: Pixel.u(4)) {
                header

                switch step {
                case .pickBreed: breedPicker
                case .name:      namePanel
                }

                Spacer(minLength: 0)
                footer
            }
            .padding(Pixel.u(4))
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: Pixel.u(1.5)) {
            Text(verbatim: L(step == .pickBreed
                             ? "onboard.pick.title" : "onboard.name.title"))
                .font(Pixel.mono(Pixel.titleSize, .bold))
                .foregroundStyle(Pixel.text.color)

            Text(verbatim: L(step == .pickBreed
                             ? "onboard.pick.subtitle" : "onboard.name.subtitle"))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
                .multilineTextAlignment(.center)

            // 钱包：让「花 4000 买宠物」这件事从一开始就可见
            HStack(spacing: Pixel.u(1)) {
                PixelIconView(icon: .coin, size: Pixel.u(4))
                Text(verbatim: "\(store.wallet.coins)")
                    .font(Pixel.mono(Pixel.numberSize, .semibold))
                    .foregroundStyle(Pixel.coin.color)
                Text(verbatim: L("onboard.gift"))
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
            }
            .padding(.top, Pixel.u(1))
        }
    }

    // MARK: - 选宠物

    private var breedPicker: some View {
        VStack(spacing: Pixel.u(3)) {
            // 品种卡片
            HStack(spacing: Pixel.u(2)) {
                ForEach(PetBreed.starters) { b in
                    breedCard(b)
                }
            }

            // 选中品种的属性明细
            statPanel

            // 毛色
            VStack(alignment: .leading, spacing: Pixel.u(1.5)) {
                Text(verbatim: L("settings.color"))
                    .font(Pixel.mono(Pixel.labelSize, .bold))
                    .foregroundStyle(Pixel.textDim.color)
                HStack(spacing: Pixel.u(2)) {
                    ForEach(0..<breed.colorCount, id: \.self) { i in
                        Button { colorIndex = i } label: {
                            ZStack {
                                Rectangle().fill(Pixel.slotEmpty.color)
                                if colorIndex == i {
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
    }

    private func breedCard(_ b: PetBreed) -> some View {
        let selected = b.id == breedID
        return Button {
            breedID = b.id
            colorIndex = 0        // 换品种时毛色归零
        } label: {
            VStack(spacing: Pixel.u(1.5)) {
                // 用宠物精灵本身当图标，比抽象图形直观
                BreedPortrait(breed: b,
                              colorIndex: selected ? colorIndex : 0,
                              size: Pixel.u(16))

                Text(verbatim: L(b.nameKey))
                    .font(Pixel.mono(Pixel.bodySize, .bold))
                    .foregroundStyle(Pixel.text.color)
                Text(verbatim: L(b.traitKey))
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
            }
            .frame(maxWidth: .infinity)
            .padding(Pixel.u(2))
            .background(
                PixelPanel(fill: selected ? Pixel.button : Pixel.buttonDark,
                           lite: selected ? Pixel.coin : Pixel.button,
                           dark: Pixel.buttonDark)
            )
        }
        .buttonStyle(.plain)
    }

    /// 属性对比面板。
    ///
    /// 三条都用「相对基准」表述而非绝对数值 —— 玩家不需要知道
    /// 「心情周期 14 小时」，只需要知道「比一般的更黏人」。
    private var statPanel: some View {
        VStack(spacing: Pixel.u(1.5)) {
            statRow(labelKey: "stat.mood",
                    icon: .ball,
                    // 周期越短越黏人 → 反转，让「条越长 = 越需要陪」
                    value: 1 - normalized(breed.moodCycleHours,
                                          lo: 12, hi: 24),
                    detail: String(format: L("onboard.stat.mood.detail"),
                                   Int(breed.moodCycleHours)))
            statRow(labelKey: "stat.hygiene",
                    icon: .bath,
                    // 同理反转：条越长 = 越需要洗
                    value: 1 - normalized(breed.hygieneCycleHours,
                                          lo: 48, hi: 96),
                    detail: String(format: L("onboard.stat.hygiene.detail"),
                                   Int(breed.hygieneCycleHours / 24)))
            statRow(labelKey: "onboard.stat.gold",
                    icon: .coin,
                    // 以 1.00 为中点（0.90~1.10 映射到 0~1），
                    // 这样「均衡型」显示在正中间而不是靠左
                    value: normalized(breed.goldMultiplier,
                                      lo: 0.90, hi: 1.10),
                    detail: String(format: L("onboard.stat.gold.detail"),
                                   Int((breed.goldMultiplier - 1) * 100)))
        }
        .padding(Pixel.u(2.5))
        .background(PixelPanel(fill: Pixel.panelDark,
                               lite: Pixel.panel,
                               dark: Pixel.panelDark))
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
    private func normalized(_ v: Double, lo: Double, hi: Double) -> Double {
        guard hi > lo else { return 0.5 }
        return min(1, max(0, (v - lo) / (hi - lo)))
    }

    // MARK: - 起名

    private var namePanel: some View {
        VStack(spacing: Pixel.u(3)) {
            BreedPortrait(breed: breed, colorIndex: colorIndex,
                          size: Pixel.u(24))

            TextField(L("settings.name.placeholder"), text: $draftName)
                .font(Pixel.mono(Pixel.titleSize))
                .foregroundStyle(Pixel.text.color)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(Pixel.u(2.5))
                .background(PixelPanel(fill: Pixel.slotEmpty,
                                       lite: Pixel.button,
                                       dark: Pixel.panelDark))
                .submitLabel(.done)

            Text(verbatim: L("settings.name.footer"))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
        }
    }

    // MARK: - 底部按钮

    private var footer: some View {
        VStack(spacing: Pixel.u(2)) {
            // 价格提示：明确告诉玩家这一步要花多少
            if step == .pickBreed {
                HStack(spacing: Pixel.u(1)) {
                    Text(verbatim: L("onboard.price"))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                    PixelIconView(icon: .coin, size: Pixel.u(3))
                    Text(verbatim: "\(PetWallet.starterPrice)")
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }
            }

            Button {
                if step == .pickBreed {
                    step = .name
                } else {
                    finish()
                }
            } label: {
                Text(verbatim: L(step == .pickBreed
                                 ? "onboard.next" : "onboard.start"))
                    .font(Pixel.mono(Pixel.bodySize, .bold))
                    .foregroundStyle(Pixel.text.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Pixel.u(2.5))
                    .background(PixelPanel(fill: Pixel.button,
                                           lite: Pixel.buttonLite,
                                           dark: Pixel.buttonDark))
            }
            .buttonStyle(.plain)

            if step == .name {
                Button {
                    step = .pickBreed
                } label: {
                    Text(verbatim: L("onboard.back"))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func finish() {
        // 名字留空就用品种名，不强迫玩家一定要起名
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.completeOnboarding(breedID: breedID,
                                 colorIndex: colorIndex,
                                 name: name)
        onDone()
    }
}

/// 品种立绘。取侧视站立帧，按整数倍放大。
///
/// 用真实精灵而非抽象图标 —— 选宠物时最该看到的就是「它长什么样」。
struct BreedPortrait: View {
    let breed: PetBreed
    let colorIndex: Int

    /// 显示边长（pt）。源帧是 32×32，取 32 的整数倍保证像素完美。
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
    /// raw resources 不是 asset catalog（见 PixelIcon 的同类注释）。
    private static var cache: [String: Image] = [:]

    private static func image(breed: PetBreed, colorIndex: Int) -> Image? {
        let key = "\(breed.id)|\(colorIndex)"
        if let hit = cache[key] { return hit }

        guard let url = Bundle.main.url(forResource: breed.sheetName,
                                        withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let full = UIImage(data: data),
              let cg = full.cgImage else { return nil }

        let cell = Int(PetSpriteSheet.frameSize.width)
        // 侧视朝右行(r0)的第 0 列，按毛色偏移
        let x = colorIndex * PetSpriteSheet.columnsPerColor * cell
        let rect = CGRect(x: x, y: 0, width: cell, height: cell)
        guard let cropped = cg.cropping(to: rect) else { return nil }

        let img = Image(uiImage: UIImage(cgImage: cropped))
        cache[key] = img
        return img
    }
}
