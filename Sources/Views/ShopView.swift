import SwiftUI

/// 宠物商店。
///
/// **为什么需要它**：之前硬币只有食物一个出口，最贵的小鱼干才 250 枚，
/// 而成就总额 13350 —— 钱会持续通胀且没有攒钱目标。
/// 新品种是最自然的消耗池：一次性解锁、有明确价格、带属性差异。
///
/// 定价推导见 docs/07-shop.md：中高频（3-4 次/天）约 30 天买得起，
/// 中频 44 天，低频基本买不起。
struct ShopView: View {
    let store: PetStore

    @Environment(\.dismiss) private var dismiss
    @State private var toast: String?
    /// 每个品种各自选中的毛色。**毛色在购买时定死**，所以要在这里选。
    @State private var coat: [String: Int] = [:]

    var body: some View {
        // 自带 NavigationStack —— 它现在总是以 sheet 出现（主页商店图标、
        // 宠物页「收养更多」），没有外层导航容器就没有标题栏，
        // 也就没有任何办法关掉这一页。
        NavigationStack {
            ZStack {
                Pixel.panel.color.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Pixel.u(3)) {
                        header

                        if PetBreed.purchasable.isEmpty {
                            emptyState
                        } else {
                            ForEach(PetBreed.purchasable) { breed in
                                row(breed)
                            }
                        }

                        if let toast {
                            Text(verbatim: toast)
                                .font(Pixel.mono(Pixel.labelSize))
                                .foregroundStyle(Pixel.warn.color)
                                .transition(.opacity)
                        }
                    }
                    .padding(Pixel.u(4))
                }
            }
            .navigationTitle(L("shop.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Pixel.panelDark.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) { dismiss() }
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(verbatim: L("shop.subtitle"))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
            Spacer()
            HStack(spacing: Pixel.u(1)) {
                PixelIconView(icon: .coin, size: Pixel.u(4))
                Text(verbatim: "\(store.wallet.coins)")
                    .font(Pixel.mono(Pixel.numberSize, .semibold))
                    .foregroundStyle(Pixel.coin.color)
            }
        }
        .padding(Pixel.u(2.5))
        .background(PixelPanel(fill: Pixel.button,
                               lite: Pixel.buttonLite,
                               dark: Pixel.buttonDark))
    }

    /// 还没有可买的品种时给个说明，而不是空白页
    private var emptyState: some View {
        VStack(spacing: Pixel.u(2)) {
            PixelIconView(icon: .star, size: Pixel.u(8))
            Text(verbatim: L("shop.empty"))
                .font(Pixel.mono(Pixel.bodySize))
                .foregroundStyle(Pixel.textDim.color)
                .multilineTextAlignment(.center)
        }
        .padding(Pixel.u(6))
    }

    private func row(_ breed: PetBreed) -> some View {
        // **不再有「已拥有」概念** —— 每次购买都是多养一只，
        // 同品种不同色（甚至同色）都可以养多只。
        let affordable = store.wallet.coins >= breed.price
        let picked = coat[breed.id] ?? 0
        let ownedCount = store.pets.filter { $0.breedID == breed.id }.count

        return VStack(spacing: Pixel.u(2)) {
            HStack(spacing: Pixel.u(3)) {
                BreedPortrait(breed: breed, colorIndex: picked, size: Pixel.u(16))

                VStack(alignment: .leading, spacing: Pixel.u(1)) {
                    Text(verbatim: L(breed.nameKey))
                        .font(Pixel.mono(Pixel.bodySize, .bold))
                        .foregroundStyle(Pixel.text.color)
                    Text(verbatim: L(breed.traitKey))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                    if ownedCount > 0 {
                        Text(verbatim: String(format: L("shop.owned_count"), ownedCount))
                            .font(Pixel.mono(Pixel.labelSize))
                            .foregroundStyle(Pixel.hygiene.color)
                    }
                }

                Spacer(minLength: 0)
            }

            // 毛色在这里选 —— 买完就定死，之后只能改名字
            if breed.colorCount > 1 {
                CoatPicker(breed: breed, colorIndex: Binding(
                    get: { coat[breed.id] ?? 0 },
                    set: { coat[breed.id] = $0 }))
            }

            // 属性用共享面板 —— 原来压成一行文字，信息密度太低，
            // 而「买之前看清属性」正是这个页面的核心。
            BreedStatPanel(breed: breed, compact: true)

            // 购买按钮 / 已拥有标记
            Button {
                guard affordable else {
                    showToast(L("shop.cannot_afford"))
                    return
                }
                store.purchase(breed, colorIndex: picked)
                showToast(String(format: L("shop.purchased"),
                                 L(breed.nameKey)))
            } label: {
                HStack(spacing: Pixel.u(1)) {
                    Text(verbatim: L("shop.adopt"))
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.text.color)
                    PixelIconView(icon: .coin, size: Pixel.u(3))
                    Text(verbatim: "\(breed.price)")
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(affordable
                                         ? Pixel.coin.color
                                         : Pixel.warn.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Pixel.u(2))
                .background(
                    PixelPanel(fill: Pixel.button,
                               lite: Pixel.buttonLite,
                               dark: Pixel.buttonDark)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(Pixel.u(2.5))
        .background(PixelPanel(fill: Pixel.panelDark,
                               lite: Pixel.panel,
                               dark: Pixel.panelDark))
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toast == text { toast = nil }
        }
    }
}
